//! Осадки целиком на видеокарте (порт homeview/gl_particles.py, шейдеры без изменений).

use std::path::PathBuf;

use glow::HasContext;

// MARK: - Сезоны (season.py)

struct Layer {
    image: &'static str,
    rate: f32,
    velocity: f32,
    scale: f32,
    alpha: f32,
    spin: f32,
    emission_range: f32,
    sway: f32,
}

const fn l(image: &'static str, rate: f32, velocity: f32, scale: f32, alpha: f32, spin: f32, emission_range: f32, sway: f32) -> Layer {
    Layer { image, rate, velocity, scale, alpha, spin, emission_range, sway }
}

fn season_layers(kind: &str) -> [Layer; 3] {
    match kind {
        "spring" => [
            l("hv_p_petal_white", 14., 26., 0.34, 0.8, 1.2, 0.5, 18.),
            l("hv_p_petal_pink", 11., 36., 0.5, 0.95, 1.6, 0.5, 24.),
            l("hv_p_petal_pink", 6., 50., 0.7, 1.0, 2.0, 0.5, 30.),
        ],
        "summer" => [
            l("hv_p_fluff", 7., 12., 0.4, 0.7, 0.3, 1.2, 26.),
            l("hv_p_fluff", 5., 16., 0.6, 0.85, 0.4, 1.2, 34.),
            l("hv_p_fluff", 3., 22., 0.85, 0.9, 0.5, 1.2, 40.),
        ],
        "autumn" => [
            l("hv_p_leaf_gold", 12., 30., 0.4, 0.85, 1.6, 0.45, 22.),
            l("hv_p_leaf_orange", 9., 42., 0.6, 0.95, 2.0, 0.45, 30.),
            l("hv_p_leaf_red", 5., 56., 0.82, 1.0, 2.4, 0.45, 36.),
        ],
        _ => [
            l("hv_p_flake_dot", 36., 30., 0.26, 0.75, 0.0, 0.18, 0.),
            l("hv_p_flake_soft", 28., 44., 0.42, 0.9, 0.0, 0.18, 0.),
            l("hv_p_flake_crystal", 16., 64., 0.62, 1.0, 0.6, 0.18, 6.),
        ],
    }
}

/// Месяц по UTC-дате (без chrono): 12–2 зима, 3–5 весна, 6–8 лето, 9–11 осень.
pub fn season_for_today() -> &'static str {
    let days = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_secs() as i64 / 86400;
    // civil_from_days (H. Hinnant)
    let z = days + 719468;
    let doe = z.rem_euclid(146097);
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let month = if mp < 10 { mp + 3 } else { mp - 9 };
    match month {
        12 | 1 | 2 => "winter",
        3..=5 => "spring",
        6..=8 => "summer",
        _ => "autumn",
    }
}

// MARK: - Шейдеры (gl_particles.py без изменений)

const VERTEX: &str = r#"
#version 120
attribute vec3 a0;   // x0, phase, vy
attribute vec3 a1;   // slope, angle0, spin
attribute vec3 a2;   // size, sway, sway_phase
uniform float u_time;
uniform vec2 u_size;
uniform float u_travel;
uniform float u_ground;
uniform float u_dpr;
varying float v_angle;
void main() {
    float y = mod(a0.y + a0.z * u_time, u_travel) - 24.0;
    float x = a0.x + (y + 24.0) * a1.x + a2.y * sin(u_time * 1.3 + a2.z);
    v_angle = a1.y + a1.z * u_time;
    gl_Position = vec4(x / u_size.x * 2.0 - 1.0, 1.0 - y / u_size.y * 2.0, 0.0, 1.0);
    gl_PointSize = y > u_ground ? 0.0 : a2.x * u_dpr * 1.42;
}
"#;

const FRAGMENT: &str = r#"
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
    gl_FragColor = vec4(t.rgb * a, a);
}
"#;

const TOP: f32 = 24.0;
const BASE_POINTS: f32 = 16.0;
const SPAWN_MARGIN: f32 = 40.0;
const FLOATS_PER_PARTICLE: usize = 9;
const GL_POINT_SPRITE: u32 = 0x8861;

fn generate(layer: &Layer, width: f32, ground: f32, density: f32) -> Vec<f32> {
    let travel = ground + TOP * 2.0;
    let rate = layer.rate * (width + 2.0 * SPAWN_MARGIN) / 1440.0 * density;
    let count = (rate * travel / layer.velocity.max(1.0)).max(0.0) as usize;
    let u = |a: f32, b: f32| a + (b - a) * fastrand::f32();
    let tau = std::f32::consts::TAU;
    let mut data = Vec::with_capacity(count * FLOATS_PER_PARTICLE);
    for _ in 0..count {
        let speed = layer.velocity * u(0.75, 1.25);
        let direction = u(-layer.emission_range / 2.0, layer.emission_range / 2.0);
        data.extend_from_slice(&[
            u(-SPAWN_MARGIN, width + SPAWN_MARGIN),
            u(0.0, travel),
            direction.cos() * speed,
            direction.tan(),
            u(0.0, tau),
            u(-layer.spin, layer.spin),
            BASE_POINTS * layer.scale * u(0.7, 1.3),
            layer.sway * u(0.5, 1.0),
            u(0.0, tau),
        ]);
    }
    data
}

pub struct GpuLayer {
    buffer: glow::Buffer,
    pub count: i32,
    texture: glow::Texture,
    alpha: f32,
}

impl GpuLayer {
    /// Текстуры общие для слоёв (кэш в ParticleRenderer) — удаляем только буфер.
    pub unsafe fn delete(&self, gl: &glow::Context) {
        gl.delete_buffer(self.buffer);
    }
}

pub struct ParticleRenderer {
    pub gl: glow::Context,
    pub vao: glow::VertexArray,
    program: glow::Program,
    attribs: [u32; 3],
    textures: Vec<(&'static str, glow::Texture)>,
}

pub fn art_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../HomeView/Art")
}

impl ParticleRenderer {
    pub unsafe fn new(gl: glow::Context) -> ParticleRenderer {
        let program = gl.create_program().unwrap();
        for (kind, src) in [(glow::VERTEX_SHADER, VERTEX), (glow::FRAGMENT_SHADER, FRAGMENT)] {
            let shader = gl.create_shader(kind).unwrap();
            gl.shader_source(shader, src);
            gl.compile_shader(shader);
            if !gl.get_shader_compile_status(shader) {
                panic!("шейдер не собрался: {}", gl.get_shader_info_log(shader));
            }
            gl.attach_shader(program, shader);
        }
        gl.link_program(program);
        if !gl.get_program_link_status(program) {
            panic!("программа не слинковалась: {}", gl.get_program_info_log(program));
        }
        let attribs = ["a0", "a1", "a2"].map(|n| gl.get_attrib_location(program, n).expect(n));
        // В core-профиле без VAO glDrawArrays ничего не рисует — заводим его всегда.
        let vao = gl.create_vertex_array().unwrap();
        ParticleRenderer { gl, program, attribs, vao, textures: Vec::new() }
    }

    unsafe fn texture(&mut self, name: &'static str) -> glow::Texture {
        if let Some((_, t)) = self.textures.iter().find(|(n, _)| *n == name) {
            return *t;
        }
        let gl = &self.gl;
        let img = image::open(art_dir().join(format!("{name}.png"))).expect(name).to_rgba8();
        let t = gl.create_texture().unwrap();
        gl.bind_texture(glow::TEXTURE_2D, Some(t));
        gl.tex_image_2d(glow::TEXTURE_2D, 0, glow::RGBA as i32, img.width() as i32, img.height() as i32, 0,
                        glow::RGBA, glow::UNSIGNED_BYTE, glow::PixelUnpackData::Slice(Some(img.as_raw())));
        gl.generate_mipmap(glow::TEXTURE_2D);
        gl.tex_parameter_i32(glow::TEXTURE_2D, glow::TEXTURE_MIN_FILTER, glow::LINEAR_MIPMAP_LINEAR as i32);
        gl.tex_parameter_i32(glow::TEXTURE_2D, glow::TEXTURE_MAG_FILTER, glow::LINEAR as i32);
        gl.tex_parameter_i32(glow::TEXTURE_2D, glow::TEXTURE_WRAP_S, glow::CLAMP_TO_EDGE as i32);
        gl.tex_parameter_i32(glow::TEXTURE_2D, glow::TEXTURE_WRAP_T, glow::CLAMP_TO_EDGE as i32);
        self.textures.push((name, t));
        t
    }

    pub unsafe fn prepare(&mut self, season: &str, width: f32, ground: f32, density: f32) -> Vec<GpuLayer> {
        season_layers(season).iter().map(|layer| {
            let data = generate(layer, width, ground, density);
            let gl = &self.gl;
            let buffer = gl.create_buffer().unwrap();
            gl.bind_buffer(glow::ARRAY_BUFFER, Some(buffer));
            let bytes = std::slice::from_raw_parts(data.as_ptr() as *const u8, data.len() * 4);
            gl.buffer_data_u8_slice(glow::ARRAY_BUFFER, bytes, glow::STATIC_DRAW);
            let texture = self.texture(layer.image);
            GpuLayer { buffer, count: (data.len() / FLOATS_PER_PARTICLE) as i32, texture, alpha: layer.alpha }
        }).collect()
    }

    pub unsafe fn draw(&self, layers: &[GpuLayer], width: f32, height: f32, ground: f32, time: f32) {
        let gl = &self.gl;
        gl.viewport(0, 0, width as i32, height as i32);
        gl.enable(glow::BLEND);
        gl.blend_func(glow::ONE, glow::ONE_MINUS_SRC_ALPHA);
        gl.enable(glow::PROGRAM_POINT_SIZE);
        gl.enable(GL_POINT_SPRITE);
        gl.get_error();
        gl.use_program(Some(self.program));
        gl.bind_vertex_array(Some(self.vao));
        let loc = |n: &str| gl.get_uniform_location(self.program, n);
        gl.uniform_1_f32(loc("u_dpr").as_ref(), 1.0);
        gl.uniform_1_i32(loc("u_texture").as_ref(), 0);
        gl.uniform_1_f32(loc("u_time").as_ref(), time);
        gl.uniform_2_f32(loc("u_size").as_ref(), width, height);
        gl.uniform_1_f32(loc("u_travel").as_ref(), ground + TOP * 2.0);
        gl.uniform_1_f32(loc("u_ground").as_ref(), ground);
        let alpha_loc = loc("u_alpha");
        let stride = (4 * FLOATS_PER_PARTICLE) as i32;
        gl.active_texture(glow::TEXTURE0);
        for layer in layers.iter().filter(|l| l.count > 0) {
            gl.uniform_1_f32(alpha_loc.as_ref(), layer.alpha);
            gl.bind_texture(glow::TEXTURE_2D, Some(layer.texture));
            gl.bind_buffer(glow::ARRAY_BUFFER, Some(layer.buffer));
            for (i, &a) in self.attribs.iter().enumerate() {
                gl.enable_vertex_attrib_array(a);
                gl.vertex_attrib_pointer_f32(a, 3, glow::FLOAT, false, stride, (i * 12) as i32);
            }
            gl.draw_arrays(glow::POINTS, 0, layer.count);
            for &a in &self.attribs {
                gl.disable_vertex_attrib_array(a);
            }
        }
    }
}

