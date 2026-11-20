"""Осадки целиком на видеокарте.

Каждая частица хранит в видеопамяти только начальные параметры (где появилась, скорость,
снос, вращение, размер, покачивание). Положение в момент t считает вершинный шейдер:

    y = (phase + vy·t) mod travel − 24          — падает и по кругу появляется сверху
    x = x0 + (y + 24)·slope + sway·sin(1.3t + φ) — снос и покачивание
    angle = angle0 + spin·t

Поэтому на кадр — одна команда glDrawArrays(GL_POINTS) на слой, а процессор лишь передаёт t.
Частица рисуется точкой-спрайтом (gl_PointSize), поворот — во фрагментном шейдере.
"""

from __future__ import annotations

import array
import logging
import math
import random

from PySide6.QtGui import QImage, QOpenGLContext
from PySide6.QtOpenGL import QOpenGLBuffer, QOpenGLShader, QOpenGLShaderProgram, QOpenGLTexture

from . import art
from .particles import BASE_POINTS, SPAWN_MARGIN, ParticleSystem

log = logging.getLogger(__name__)

GL_FLOAT = 0x1406
GL_POINTS = 0x0000
GL_BLEND = 0x0BE2
GL_ONE = 1
GL_ONE_MINUS_SRC_ALPHA = 0x0303
GL_PROGRAM_POINT_SIZE = 0x8642
GL_POINT_SPRITE = 0x8861
FLOATS_PER_PARTICLE = 9
TOP = 24.0  # частицы появляются чуть выше края экрана

VERTEX = """
#version 120
attribute vec3 a0;   // x0, phase, vy
attribute vec3 a1;   // slope, angle0, spin
attribute vec3 a2;   // size, sway, sway_phase
uniform float u_time;
uniform vec2 u_size;      // ширина и высота окна в точках
uniform float u_travel;   // путь от верха до «земли» + запас
uniform float u_ground;
uniform float u_dpr;
varying float v_angle;
void main() {
    float y = mod(a0.y + a0.z * u_time, u_travel) - 24.0;
    float x = a0.x + (y + 24.0) * a1.x + a2.y * sin(u_time * 1.3 + a2.z);
    v_angle = a1.y + a1.z * u_time;
    gl_Position = vec4(x / u_size.x * 2.0 - 1.0, 1.0 - y / u_size.y * 2.0, 0.0, 1.0);
    // 1.42 ≈ √2 — место под повёрнутый квадрат спрайта; ниже «земли» не рисуем
    gl_PointSize = y > u_ground ? 0.0 : a2.x * u_dpr * 1.42;
}
"""

FRAGMENT = """
#version 120
uniform sampler2D u_texture;
uniform float u_alpha;
varying float v_angle;
void main() {
    vec2 p = gl_PointCoord - 0.5;
    float c = cos(v_angle);
    float s = sin(v_angle);
    vec2 q = vec2(c * p.x - s * p.y, s * p.x + c * p.y) * 1.42 + 0.5;
    if (q.x < 0.0 || q.x > 1.0 || q.y < 0.0 || q.y > 1.0) discard;
    vec4 t = texture2D(u_texture, q);
    float a = t.a * u_alpha;
    gl_FragColor = vec4(t.rgb * a, a);   // окно ждёт премультиплицированную альфу
}
"""


def travel_for(ground_y: float) -> float:
    return ground_y + TOP * 2


def generate(system: ParticleSystem) -> list[bytes]:
    """Начальные параметры частиц для каждого слоя (по тем же правилам, что и Python-версия)."""
    result = []
    travel = travel_for(system.ground_y)
    for style in system.season.layers:
        rate = style.rate * (system.width + 2 * SPAWN_MARGIN) / 1440 * system.density
        count = max(0, int(rate * travel / max(style.velocity, 1)))
        data = array.array("f")
        for _ in range(count):
            speed = style.velocity * random.uniform(0.75, 1.25)
            direction = random.uniform(-style.emission_range / 2, style.emission_range / 2)
            vy = math.cos(direction) * speed
            data.extend((
                random.uniform(-SPAWN_MARGIN, system.width + SPAWN_MARGIN),
                random.uniform(0, travel),
                vy,
                math.tan(direction),
                random.uniform(0, 2 * math.pi),
                random.uniform(-style.spin, style.spin),
                BASE_POINTS * style.scale * random.uniform(0.7, 1.3),
                style.sway * random.uniform(0.5, 1.0),
                random.uniform(0, 2 * math.pi),
            ))
        result.append(data.tobytes())
    return result


class _Prepared:
    def __init__(self, system: ParticleSystem) -> None:
        self.system = system
        self.key = (system.season.kind, system.width, system.ground_y, system.density)
        self.layers: list[tuple[QOpenGLBuffer, int, QOpenGLTexture, float]] = []
        for style, data in zip(system.season.layers, generate(system)):
            buffer = QOpenGLBuffer(QOpenGLBuffer.VertexBuffer)
            buffer.create()
            buffer.bind()
            buffer.allocate(data, len(data))
            buffer.release()
            picture = art.image(style.image) or art._fallback_flake()
            texture = QOpenGLTexture(picture.convertToFormat(QImage.Format_RGBA8888), QOpenGLTexture.GenerateMipMaps)
            texture.setMinMagFilters(QOpenGLTexture.LinearMipMapLinear, QOpenGLTexture.Linear)
            texture.setWrapMode(QOpenGLTexture.ClampToEdge)
            self.layers.append((buffer, len(data) // (4 * FLOATS_PER_PARTICLE), texture, style.alpha))

    def destroy(self) -> None:
        for buffer, _, texture, _ in self.layers:
            buffer.destroy()
            texture.destroy()
        self.layers.clear()


class GLParticleRenderer:
    """Живёт в одном OpenGL-окне; вызывается между beginNativePainting/endNativePainting."""

    def __init__(self) -> None:
        self._program: QOpenGLShaderProgram | None = None
        self._failed = False
        self._prepared: dict[int, _Prepared] = {}

    @property
    def failed(self) -> bool:
        return self._failed

    def _ensure_program(self) -> bool:
        if self._program is not None or self._failed:
            return not self._failed
        program = QOpenGLShaderProgram()
        ok = (program.addShaderFromSourceCode(QOpenGLShader.Vertex, VERTEX)
              and program.addShaderFromSourceCode(QOpenGLShader.Fragment, FRAGMENT)
              and program.link())
        if not ok:
            log.error("Шейдер частиц не собрался: %s", program.log())
            self._failed = True
            return False
        self._program = program
        return True

    def draw(self, systems: list[ParticleSystem], width: float, height: float, dpr: float) -> bool:
        """Рисует наборы частиц (текущий и тающий при смене сезона). False — не получилось."""
        if not self._ensure_program():
            return False
        alive = {id(s) for s in systems}
        for key in [k for k in self._prepared if k not in alive]:
            self._prepared.pop(key).destroy()

        functions = QOpenGLContext.currentContext().functions()
        functions.glEnable(GL_BLEND)
        functions.glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA)
        functions.glEnable(GL_PROGRAM_POINT_SIZE)
        functions.glEnable(GL_POINT_SPRITE)  # нужно в compatibility-профиле
        functions.glGetError()  # GL_POINT_SPRITE может быть «неизвестен» драйверу — это не страшно

        program = self._program
        program.bind()
        program.setUniformValue1f("u_dpr", float(dpr))
        program.setUniformValue1i("u_texture", 0)
        for system in systems:
            if system.opacity <= 0:
                continue
            prepared = self._prepared.get(id(system))
            key = (system.season.kind, system.width, system.ground_y, system.density)
            if prepared is None or prepared.system is not system or prepared.key != key:
                if prepared is not None:
                    prepared.destroy()
                prepared = _Prepared(system)
                self._prepared[id(system)] = prepared
            program.setUniformValue1f("u_time", float(system.time))
            program.setUniformValue("u_size", float(width), float(height))
            program.setUniformValue1f("u_travel", float(travel_for(system.ground_y)))
            program.setUniformValue1f("u_ground", float(system.ground_y))
            for buffer, count, texture, alpha in prepared.layers:
                if count == 0:
                    continue
                program.setUniformValue1f("u_alpha", float(alpha * system.opacity))
                texture.bind(0)
                buffer.bind()
                stride = 4 * FLOATS_PER_PARTICLE
                for index, name in enumerate(("a0", "a1", "a2")):
                    program.enableAttributeArray(name)
                    program.setAttributeBuffer(name, GL_FLOAT, index * 12, 3, stride)
                functions.glDrawArrays(GL_POINTS, 0, count)
                for name in ("a0", "a1", "a2"):
                    program.disableAttributeArray(name)
                buffer.release()
                texture.release(0)
        program.release()
        return True

    def destroy(self) -> None:
        for prepared in self._prepared.values():
            prepared.destroy()
        self._prepared.clear()
