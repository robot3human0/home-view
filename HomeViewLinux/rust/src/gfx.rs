//! 2D-спрайты на GPU: текстуры (премультиплицированная альфа), аффинные преобразования
//! и пакетная отрисовка квадов с перекраской (multiply) и прозрачностью.

use glow::HasContext;

/// x' = a·x + c·y + e,  y' = b·x + d·y + f  (как QTransform/CGAffineTransform)
#[derive(Clone, Copy, Debug)]
pub struct Affine {
    pub a: f32,
    pub b: f32,
    pub c: f32,
    pub d: f32,
    pub e: f32,
    pub f: f32,
}

impl Affine {
    pub const IDENTITY: Affine = Affine { a: 1.0, b: 0.0, c: 0.0, d: 1.0, e: 0.0, f: 0.0 };

    fn then_local(self, m: Affine) -> Affine {
        // self × m: m применяется первым (как painter.translate/rotate — в локальных координатах)
        Affine {
            a: self.a * m.a + self.c * m.b,
            b: self.b * m.a + self.d * m.b,
            c: self.a * m.c + self.c * m.d,
            d: self.b * m.c + self.d * m.d,
            e: self.a * m.e + self.c * m.f + self.e,
            f: self.b * m.e + self.d * m.f + self.f,
        }
    }
    pub fn translate(self, x: f32, y: f32) -> Affine {
        self.then_local(Affine { e: x, f: y, ..Affine::IDENTITY })
    }
    pub fn scale(self, sx: f32, sy: f32) -> Affine {
        self.then_local(Affine { a: sx, d: sy, ..Affine::IDENTITY })
    }
    /// Положительный угол — против часовой стрелки в системе с осью Y вверх (как в Core Animation).
    pub fn rotate(self, angle: f32) -> Affine {
        if angle == 0.0 {
            return self;
        }
        let (s, c) = angle.sin_cos();
        self.then_local(Affine { a: c, b: s, c: -s, d: c, e: 0.0, f: 0.0 })
    }
    pub fn apply(&self, x: f32, y: f32) -> (f32, f32) {
        (self.a * x + self.c * y + self.e, self.b * x + self.d * y + self.f)
    }
}

#[derive(Clone, Copy)]
pub struct Texture {
    pub id: glow::Texture,
    pub width: u32,
    pub height: u32,
}

/// RGBA с премультиплицированной альфой → текстура. `mipmaps` — для сильного уменьшения (спрайты 8 px/pt).
pub unsafe fn upload(gl: &glow::Context, width: u32, height: u32, premultiplied_rgba: &[u8], mipmaps: bool) -> Texture {
    let id = gl.create_texture().unwrap();
    gl.bind_texture(glow::TEXTURE_2D, Some(id));
    gl.pixel_store_i32(glow::UNPACK_ALIGNMENT, 1);
    gl.tex_image_2d(glow::TEXTURE_2D, 0, glow::RGBA as i32, width as i32, height as i32, 0,
                    glow::RGBA, glow::UNSIGNED_BYTE, glow::PixelUnpackData::Slice(Some(premultiplied_rgba)));
    let min = if mipmaps {
        gl.generate_mipmap(glow::TEXTURE_2D);
        glow::LINEAR_MIPMAP_LINEAR
    } else {
        glow::LINEAR
    };
    gl.tex_parameter_i32(glow::TEXTURE_2D, glow::TEXTURE_MIN_FILTER, min as i32);
    gl.tex_parameter_i32(glow::TEXTURE_2D, glow::TEXTURE_MAG_FILTER, glow::LINEAR as i32);
    gl.tex_parameter_i32(glow::TEXTURE_2D, glow::TEXTURE_WRAP_S, glow::CLAMP_TO_EDGE as i32);
    gl.tex_parameter_i32(glow::TEXTURE_2D, glow::TEXTURE_WRAP_T, glow::CLAMP_TO_EDGE as i32);
    Texture { id, width, height }
}

/// Простое изображение в памяти: RGBA8, альфа премультиплицирована.
#[derive(Clone)]
pub struct Image {
    pub width: u32,
    pub height: u32,
    pub data: Vec<u8>,
}

impl Image {
    pub fn load_png(path: &std::path::Path) -> Image {
        let img = image::open(path).unwrap_or_else(|e| panic!("{}: {e}", path.display())).to_rgba8();
        let (width, height) = img.dimensions();
        let mut data = img.into_raw();
        for p in data.chunks_exact_mut(4) {
            let a = p[3] as u32;
            for c in &mut p[..3] {
                *c = ((*c as u32 * a + 127) / 255) as u8;
            }
        }
        Image { width, height, data }
    }

    pub fn empty(width: u32, height: u32) -> Image {
        Image { width, height, data: vec![0; (width * height * 4) as usize] }
    }

    /// Наложить `src` того же размера поверх (source-over); с `tint` — серый × цвет, альфа как у исходника.
    pub fn draw_over(&mut self, src: &Image, tint: Option<u32>) {
        assert_eq!((self.width, self.height), (src.width, src.height));
        let t = tint.map(|c| [((c >> 16) & 0xFF) as u32, ((c >> 8) & 0xFF) as u32, (c & 0xFF) as u32]);
        for (d, s) in self.data.chunks_exact_mut(4).zip(src.data.chunks_exact(4)) {
            let sa = s[3] as u32;
            if sa == 0 {
                continue;
            }
            let inv = 255 - sa;
            for i in 0..3 {
                let sc = match t {
                    Some(t) => (s[i] as u32 * t[i] + 127) / 255,
                    None => s[i] as u32,
                };
                d[i] = (sc + (d[i] as u32 * inv + 127) / 255).min(255) as u8;
            }
            d[3] = (sa + (d[3] as u32 * inv + 127) / 255).min(255) as u8;
        }
    }
}

const VERTEX: &str = r#"
#version 120
attribute vec2 a_pos;
attribute vec2 a_uv;
attribute vec4 a_color;
uniform vec2 u_size;
varying vec2 v_uv;
varying vec4 v_color;
void main() {
    v_uv = a_uv;
    v_color = a_color;
    gl_Position = vec4(a_pos.x / u_size.x * 2.0 - 1.0, 1.0 - a_pos.y / u_size.y * 2.0, 0.0, 1.0);
}
"#;

const FRAGMENT: &str = r#"
#version 120
uniform sampler2D u_texture;
varying vec2 v_uv;
varying vec4 v_color;   // rgb — перекраска (multiply), a — прозрачность
void main() {
    vec4 t = texture2D(u_texture, v_uv);
    gl_FragColor = vec4(t.rgb * v_color.rgb, t.a) * v_color.a;
}
"#;

const FLOATS_PER_VERTEX: usize = 8;

pub struct SpriteBatch {
    program: glow::Program,
    buffer: glow::Buffer,
    attribs: [u32; 3],
    vertices: Vec<f32>,
    texture: Option<glow::Texture>,
    pub draw_calls: u32,
}

pub unsafe fn compile(gl: &glow::Context, vertex: &str, fragment: &str) -> glow::Program {
    let program = gl.create_program().unwrap();
    for (kind, src) in [(glow::VERTEX_SHADER, vertex), (glow::FRAGMENT_SHADER, fragment)] {
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
    program
}

impl SpriteBatch {
    pub unsafe fn new(gl: &glow::Context) -> SpriteBatch {
        let program = compile(gl, VERTEX, FRAGMENT);
        let attribs = ["a_pos", "a_uv", "a_color"].map(|n| gl.get_attrib_location(program, n).expect(n));
        let buffer = gl.create_buffer().unwrap();
        SpriteBatch { program, buffer, attribs, vertices: Vec::with_capacity(4096), texture: None, draw_calls: 0 }
    }

    pub unsafe fn begin(&mut self, gl: &glow::Context, width: f32, height: f32) {
        gl.use_program(Some(self.program));
        gl.uniform_2_f32(gl.get_uniform_location(self.program, "u_size").as_ref(), width, height);
        gl.uniform_1_i32(gl.get_uniform_location(self.program, "u_texture").as_ref(), 0);
        gl.enable(glow::BLEND);
        gl.blend_func(glow::ONE, glow::ONE_MINUS_SRC_ALPHA);
        self.draw_calls = 0;
    }

    /// Квад: прямоугольник (x, y, w, h) в локальных координатах `m`; v=0 (верх картинки) — у `y_top`.
    pub unsafe fn quad(&mut self, gl: &glow::Context, texture: Texture, m: &Affine,
                       x: f32, y_top: f32, w: f32, h_signed: f32, tint: [f32; 3], alpha: f32) {
        if self.texture != Some(texture.id) {
            self.flush(gl);
            self.texture = Some(texture.id);
        }
        let corners = [(x, y_top, 0.0, 0.0), (x + w, y_top, 1.0, 0.0), (x + w, y_top + h_signed, 1.0, 1.0),
                       (x, y_top + h_signed, 0.0, 1.0)];
        for i in [0usize, 1, 2, 0, 2, 3] {
            let (px, py, u, v) = corners[i];
            let (sx, sy) = m.apply(px, py);
            self.vertices.extend_from_slice(&[sx, sy, u, v, tint[0], tint[1], tint[2], alpha]);
        }
    }

    pub unsafe fn flush(&mut self, gl: &glow::Context) {
        let Some(texture) = self.texture else { return };
        if self.vertices.is_empty() {
            return;
        }
        gl.active_texture(glow::TEXTURE0);
        gl.bind_texture(glow::TEXTURE_2D, Some(texture));
        gl.bind_buffer(glow::ARRAY_BUFFER, Some(self.buffer));
        let bytes = std::slice::from_raw_parts(self.vertices.as_ptr() as *const u8, self.vertices.len() * 4);
        gl.buffer_data_u8_slice(glow::ARRAY_BUFFER, bytes, glow::STREAM_DRAW);
        let stride = (FLOATS_PER_VERTEX * 4) as i32;
        for (&a, (size, offset)) in self.attribs.iter().zip([(2, 0), (2, 8), (4, 16)]) {
            gl.enable_vertex_attrib_array(a);
            gl.vertex_attrib_pointer_f32(a, size, glow::FLOAT, false, stride, offset);
        }
        gl.draw_arrays(glow::TRIANGLES, 0, (self.vertices.len() / FLOATS_PER_VERTEX) as i32);
        for &a in &self.attribs {
            gl.disable_vertex_attrib_array(a);
        }
        self.vertices.clear();
        self.draw_calls += 1;
    }

    pub unsafe fn end(&mut self, gl: &glow::Context) {
        self.flush(gl);
        self.texture = None;
    }
}
