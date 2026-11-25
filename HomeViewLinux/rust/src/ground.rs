//! Снег на земле (порт snowpile.py, физика та же), но рисуется целиком на видеокарте:
//!
//! * высоты столбцов (по 3 pt) — float-текстура шириной в число столбцов, обновляется 20 раз/с;
//! * тело кучи — один прямоугольник: фрагментный шейдер сравнивает y пикселя с высотой (линейная
//!   интерполяция между столбцами), заливает цветом (зима, лето) или бесшовной плиткой из листьев/лепестков
//!   (осень, весна), добавляет мягкую тень у основания и контур;
//! * по краю — спрайты листьев/лепестков точками (как осадки): вершинный шейдер сам берёт высоту
//!   из той же текстуры, поэтому край растёт вместе с кучей без перерисовки картинок.
//!
//! В Python кучу приходилось держать картинками по кускам и перерисовывать по одному куску за кадр
//! (иначе рывки); здесь на CPU — только физика.

use glow::HasContext;
use tiny_skia::{Pixmap, PixmapPaint, Transform};

use crate::gfx::{self, compile, Image};
use crate::particles::art_dir;

pub const COLUMN: f32 = 3.0;
const MAX_HEIGHT: f32 = 150.0;
const REPOSE: f32 = 2.0;
const STEP_SECONDS: f32 = 0.05;
/// Невидимых снежинок в секунду на ширину 1440 точек при плотности 1 (baseFlakeRate в SnowWorld.swift).
const BASE_FLAKE_RATE: f32 = 80.0;
/// Растёт в 2.5 раза медленнее мака — так решил пользователь (на маке кучу разгребает бригада).
const PILE_GROWTH: f32 = 0.4;

const TILE: u32 = 256;
const TILE_SPRITES: usize = 2800;
const SPRITE_SIZES: (f32, f32) = (8.0, 14.0);
const EDGE_STEP: f32 = 5.0;
const EDGE_ROTATIONS: usize = 12;

/// Как выглядит то, что накопилось (season.py: pile_fill, pile_stroke, pile_sprites, pile_under).
struct Look {
    fill: u32,
    stroke: (u32, f32),
    sprites: &'static [&'static str],
    under: u32,
    accumulation: f32,
}

fn look(season: &str) -> Look {
    match season {
        "spring" => Look { fill: 0xFCE4EC, stroke: (0xF48FB1, 0.9), sprites: &["hv_p_petal_pink", "hv_p_petal_white"],
                           under: 0xF3A6C0, accumulation: 0.7 },
        "summer" => Look { fill: 0xF7F5EE, stroke: (0xD7CCC8, 0.9), sprites: &[], under: 0, accumulation: 0.35 },
        "autumn" => Look { fill: 0xE8A04C, stroke: (0xB5651D, 0.9),
                           sprites: &["hv_p_leaf_gold", "hv_p_leaf_orange", "hv_p_leaf_red"], under: 0x8A4B1C,
                           accumulation: 0.8 },
        _ => Look { fill: 0xFFFFFF, stroke: (0xA9B9CF, 0.95), sprites: &[], under: 0, accumulation: 1.0 },
    }
}

fn rgb(hex: u32) -> [f32; 3] {
    crate::effects::rgb(hex)
}

// MARK: - Физика (одна куча на монитор)

pub struct Pile {
    heights: Vec<f32>,
    width: f32,
    pub base_y: f32,
    step_timer: f32,
    sky_carry: f32,
    changed: bool,
    texture: Option<glow::Texture>,
}

impl Pile {
    pub fn new(width: f32, base_y: f32) -> Pile {
        Pile { heights: vec![0.0; (width / COLUMN).ceil().max(1.0) as usize], width, base_y, step_timer: 0.0,
               sky_carry: 0.0, changed: true, texture: None }
    }

    pub fn height(&self, x: f32) -> f32 {
        if !x.is_finite() {
            return 0.0;
        }
        let i = (x / COLUMN).floor();
        if i < 0.0 || i as usize >= self.heights.len() { 0.0 } else { self.heights[i as usize] }
    }

    /// Куда ставить ступни: на снег, чуть провалившись (groundSurface в Mac-версии).
    pub fn surface(&self, x: f32) -> f32 {
        self.base_y - self.height(x) * 0.8
    }

    fn add(&mut self, i: isize, amount: f32) {
        if i >= 0 && (i as usize) < self.heights.len() {
            let h = &mut self.heights[i as usize];
            *h = (*h + amount).min(MAX_HEIGHT);
        }
    }

    /// Упавшая снежинка: половина — в свой столбец, по четверти — соседям.
    pub fn deposit(&mut self, x: f32, amount: f32) {
        if !x.is_finite() || x < 0.0 {
            return;
        }
        let i = (x / COLUMN).floor() as isize;
        if i as usize >= self.heights.len() {
            return;
        }
        self.add(i, amount * 0.5);
        self.add(i - 1, amount * 0.25);
        self.add(i + 1, amount * 0.25);
        self.changed = true;
    }

    #[allow(dead_code)] // «Убрать снег» в трее — следующим шагом
    pub fn clear(&mut self) {
        self.heights.iter_mut().for_each(|h| *h = 0.0);
        self.changed = true;
    }

    /// Слишком крутой склон осыпается: разница соседних столбцов сглаживается до REPOSE.
    fn relax(&mut self) {
        let h = &mut self.heights;
        for _ in 0..2 {
            for i in 0..h.len().saturating_sub(1) {
                let diff = h[i] - h[i + 1];
                if diff.abs() > REPOSE {
                    let t = (diff.abs() - REPOSE) * 0.3 * diff.signum();
                    h[i] -= t;
                    h[i + 1] += t;
                    self.changed = true;
                }
            }
        }
    }

    fn melt(&mut self, amount: f32) {
        for h in self.heights.iter_mut().filter(|h| **h > 0.0) {
            *h = (*h - amount).max(0.0);
            self.changed = true;
        }
    }

    /// С неба падают «невидимые» снежинки с той же частотой, что и видимые; каждая ложится на землю.
    /// Без осадков (выключены в настройках) — тает.
    pub fn tick(&mut self, dt: f32, season: &str, density: f32, snowing: bool) {
        if snowing {
            let rate = BASE_FLAKE_RATE * density * self.width / 1440.0;
            self.sky_carry += rate * dt;
            let count = (self.sky_carry as usize).min(400);
            self.sky_carry -= self.sky_carry.floor();
            let factor = 0.32 * look(season).accumulation * PILE_GROWTH;
            for _ in 0..count {
                let r = fastrand::f32();
                self.deposit(fastrand::f32() * self.width, (2.2 + r * r * 5.5) * factor);
            }
        }
        self.step_timer += dt;
        if self.step_timer < STEP_SECONDS {
            return;
        }
        let step = self.step_timer;
        self.step_timer = 0.0;
        self.relax();
        if !snowing {
            self.melt(step * 0.5);
        }
    }

    pub fn is_empty(&self) -> bool {
        self.heights.iter().all(|&h| h <= 0.25)
    }

    /// Отправить высоты на видеокарту, если изменились (не чаще физики — 20 раз/с).
    unsafe fn upload(&mut self, gl: &glow::Context) -> glow::Texture {
        let n = self.heights.len() as i32;
        let bytes = std::slice::from_raw_parts(self.heights.as_ptr() as *const u8, self.heights.len() * 4);
        match self.texture {
            Some(t) if !self.changed => t,
            Some(t) => {
                gl.bind_texture(glow::TEXTURE_2D, Some(t));
                gl.tex_sub_image_2d(glow::TEXTURE_2D, 0, 0, 0, n, 1, glow::RED, glow::FLOAT, glow::PixelUnpackData::Slice(Some(bytes)));
                self.changed = false;
                t
            }
            None => {
                let t = gl.create_texture().unwrap();
                gl.bind_texture(glow::TEXTURE_2D, Some(t));
                gl.tex_image_2d(glow::TEXTURE_2D, 0, glow::R32F as i32, n, 1, 0, glow::RED, glow::FLOAT,
                                glow::PixelUnpackData::Slice(Some(bytes)));
                gl.tex_parameter_i32(glow::TEXTURE_2D, glow::TEXTURE_MIN_FILTER, glow::LINEAR as i32);
                gl.tex_parameter_i32(glow::TEXTURE_2D, glow::TEXTURE_MAG_FILTER, glow::LINEAR as i32);
                gl.tex_parameter_i32(glow::TEXTURE_2D, glow::TEXTURE_WRAP_S, glow::CLAMP_TO_EDGE as i32);
                gl.tex_parameter_i32(glow::TEXTURE_2D, glow::TEXTURE_WRAP_T, glow::CLAMP_TO_EDGE as i32);
                self.texture = Some(t);
                self.changed = false;
                t
            }
        }
    }
}

// MARK: - Рисование

const BODY_VERTEX: &str = r#"
#version 120
attribute vec2 a_pos;
uniform vec2 u_size;
varying vec2 v_pos;
void main() {
    v_pos = a_pos;
    gl_Position = vec4(a_pos.x / u_size.x * 2.0 - 1.0, 1.0 - a_pos.y / u_size.y * 2.0, 0.0, 1.0);
}
"#;

const BODY_FRAGMENT: &str = r#"
#version 120
uniform sampler2D u_heights;
uniform sampler2D u_tile;
uniform float u_columns_w;   // ширина всех столбцов, px
uniform float u_base;
uniform float u_textured;
uniform vec3 u_fill;
uniform vec4 u_stroke;
uniform vec3 u_shade;
uniform float u_opacity;
varying vec2 v_pos;
void main() {
    float h = texture2D(u_heights, vec2(v_pos.x / u_columns_w, 0.5)).r;
    if (h <= 0.25) discard;
    float depth = v_pos.y - (u_base - h);           // насколько пиксель ниже поверхности
    float cover = clamp(depth + 0.5, 0.0, 1.0);     // сглаженный край
    if (cover <= 0.0) discard;
    vec3 color = u_fill;
    if (u_textured > 0.5) {
        color = texture2D(u_tile, vec2(v_pos.x, v_pos.y - u_base) / 256.0).rgb;  // узор привязан к земле
    }
    // мягкая тень у основания (объём)
    float shade = 0.34 * clamp(1.0 - (u_base - v_pos.y) / 60.0, 0.0, 1.0);
    color = mix(color, u_shade, shade);
    // контур по верху (у текстурной кучи его закрывают спрайты края)
    float line = (1.0 - u_textured) * u_stroke.a * clamp(1.5 - abs(depth - 0.5), 0.0, 1.0);
    color = mix(color, u_stroke.rgb, line);
    float a = cover * u_opacity;
    gl_FragColor = vec4(color * a, a);
}
"#;

const EDGE_VERTEX: &str = r#"
#version 120
attribute vec4 a_slot;      // x, размер, угол, dy
uniform sampler2D u_heights;
uniform float u_columns_w;
uniform vec2 u_size;
uniform float u_base;
varying float v_angle;
void main() {
    float h = texture2DLod(u_heights, vec2((floor(a_slot.x / 3.0) + 0.5) * 3.0 / u_columns_w, 0.5), 0.0).r;
    float y = u_base - h + a_slot.w;
    v_angle = a_slot.z;
    gl_Position = vec4(a_slot.x / u_size.x * 2.0 - 1.0, 1.0 - y / u_size.y * 2.0, 0.0, 1.0);
    gl_PointSize = h < 1.5 ? 0.0 : a_slot.y * 1.42;
}
"#;

const EDGE_FRAGMENT: &str = r#"
#version 120
uniform sampler2D u_texture;
uniform float u_opacity;
varying float v_angle;
void main() {
    vec2 p = gl_PointCoord - 0.5;
    float c = cos(v_angle);
    float s = sin(v_angle);
    vec2 q = vec2(c * p.x - s * p.y, s * p.x + c * p.y) * 1.42 + 0.5;
    if (q.x < 0.0 || q.x > 1.0 || q.y < 0.0 || q.y > 1.0) discard;
    vec4 t = texture2D(u_texture, q);
    gl_FragColor = t * u_opacity;   // спрайты премультиплицированы
}
"#;

struct EdgeSet {
    texture: glow::Texture,
    buffer: glow::Buffer,
    count: i32,
}

/// Шейдеры и картинки кучи для одного сезона; одна на все мониторы.
pub struct GroundRenderer {
    pub season: String,
    body: glow::Program,
    edge: glow::Program,
    quad: glow::Buffer,
    tile: Option<glow::Texture>,
    edges: Vec<(f32, EdgeSet)>, // для ширины экрана (слоты по краю зависят от ширины)
    sprites: Vec<Image>,
}

fn sprite_small(name: &str, side: u32) -> Image {
    let img = image::open(art_dir().join(format!("{name}.png"))).expect(name).to_rgba8();
    let small = image::imageops::resize(&img, side, side, image::imageops::FilterType::Lanczos3);
    let mut data = small.into_raw();
    for p in data.chunks_exact_mut(4) {
        let a = p[3] as u32;
        for c in &mut p[..3] {
            *c = ((*c as u32 * a + 127) / 255) as u8;
        }
    }
    Image { width: side, height: side, data }
}

/// Бесшовная плитка: фон — цвет тени, сверху 2800 повёрнутых листьев/лепестков (спрайты у края
/// дорисованы с противоположной стороны). Узор одинаковый при каждом запуске.
fn make_tile(sprites: &[Image], under: u32) -> Image {
    let mut tile = Pixmap::new(TILE, TILE).unwrap();
    tile.fill(tiny_skia::Color::from_rgba8((under >> 16) as u8, (under >> 8) as u8, under as u8, 255));
    let pix: Vec<Pixmap> = sprites.iter().map(|s| {
        let mut p = Pixmap::new(s.width, s.height).unwrap();
        p.data_mut().copy_from_slice(&s.data);
        p
    }).collect();
    let mut rng = fastrand::Rng::with_seed(1);
    let t = TILE as f32;
    let paint = PixmapPaint { quality: tiny_skia::FilterQuality::Bilinear, ..PixmapPaint::default() };
    for _ in 0..TILE_SPRITES {
        let p = &pix[rng.usize(..pix.len())];
        let size = SPRITE_SIZES.0 + rng.f32() * (SPRITE_SIZES.1 - SPRITE_SIZES.0);
        let (x, y, angle) = (rng.f32() * t, rng.f32() * t, rng.f32() * 360.0);
        let k = size / p.width() as f32;
        for dx in [-t, 0.0, t] {
            for dy in [-t, 0.0, t] {
                let (cx, cy) = (x + dx, y + dy);
                if cx > -size && cx < t + size && cy > -size && cy < t + size {
                    let tr = Transform::from_translate(cx, cy).pre_rotate(angle).pre_scale(k, k)
                        .pre_translate(-(p.width() as f32) / 2.0, -(p.height() as f32) / 2.0);
                    tile.draw_pixmap(0, 0, p.as_ref(), &paint, tr, None);
                }
            }
        }
    }
    Image { width: TILE, height: TILE, data: tile.take() }
}

impl GroundRenderer {
    pub unsafe fn new(gl: &glow::Context, season: &str) -> GroundRenderer {
        let started = std::time::Instant::now();
        let body = compile(gl, BODY_VERTEX, BODY_FRAGMENT);
        let edge = compile(gl, EDGE_VERTEX, EDGE_FRAGMENT);
        let quad = gl.create_buffer().unwrap();
        let l = look(season);
        let sprites: Vec<Image> = l.sprites.iter().map(|n| sprite_small(n, 32)).collect();
        let tile = (!sprites.is_empty()).then(|| {
            let img = make_tile(&sprites, l.under);
            let t = gfx::upload(gl, img.width, img.height, &img.data, false);
            gl.tex_parameter_i32(glow::TEXTURE_2D, glow::TEXTURE_WRAP_S, glow::REPEAT as i32);
            gl.tex_parameter_i32(glow::TEXTURE_2D, glow::TEXTURE_WRAP_T, glow::REPEAT as i32);
            t.id
        });
        eprintln!("Куча ({season}): подготовка {:.0} мс", started.elapsed().as_secs_f32() * 1000.0);
        GroundRenderer { season: season.into(), body, edge, quad, tile, edges: Vec::new(), sprites }
    }

    /// Каждому месту на краю — свой постоянный спрайт, размер, поворот и смещение (иначе край «кипел» бы).
    unsafe fn edge_sets(&mut self, gl: &glow::Context, width: f32) -> usize {
        if let Some(i) = self.edges.iter().position(|(w, _)| *w == width) {
            return i;
        }
        let mut rng = fastrand::Rng::with_seed(2);
        let count = (width / EDGE_STEP) as usize + 1;
        let sizes = [SPRITE_SIZES.0 + 1.0, (SPRITE_SIZES.0 + SPRITE_SIZES.1) / 2.0, SPRITE_SIZES.1];
        let mut per: Vec<Vec<f32>> = vec![Vec::new(); self.sprites.len()];
        for i in 0..count {
            let frame = rng.usize(..self.sprites.len() * 3 * EDGE_ROTATIONS);
            let (sprite, size, rot) = (frame / (3 * EDGE_ROTATIONS), sizes[(frame / EDGE_ROTATIONS) % 3], frame % EDGE_ROTATIONS);
            let dy = -1.5 + rng.f32() * 4.5;
            let x = i as f32 * EDGE_STEP + EDGE_STEP / 2.0;
            per[sprite].extend_from_slice(&[x, size, rot as f32 * std::f32::consts::TAU / EDGE_ROTATIONS as f32, dy]);
        }
        for (img, data) in self.sprites.iter().zip(per) {
            let texture = gfx::upload(gl, img.width, img.height, &img.data, true).id;
            let buffer = gl.create_buffer().unwrap();
            gl.bind_buffer(glow::ARRAY_BUFFER, Some(buffer));
            let bytes = std::slice::from_raw_parts(data.as_ptr() as *const u8, data.len() * 4);
            gl.buffer_data_u8_slice(glow::ARRAY_BUFFER, bytes, glow::STATIC_DRAW);
            self.edges.push((width, EdgeSet { texture, buffer, count: (data.len() / 4) as i32 }));
        }
        self.edges.iter().position(|(w, _)| *w == width).unwrap()
    }

    pub unsafe fn draw(&mut self, gl: &glow::Context, pile: &mut Pile, width: f32, height: f32, opacity: f32) {
        if pile.is_empty() && pile.texture.is_some() && !pile.changed {
            return;
        }
        let heights = pile.upload(gl);
        let columns_w = pile.heights.len() as f32 * COLUMN;
        let peak = pile.heights.iter().cloned().fold(0.0, f32::max);
        if peak <= 0.25 {
            return;
        }
        let l = look(&self.season);
        gl.enable(glow::BLEND);
        gl.blend_func(glow::ONE, glow::ONE_MINUS_SRC_ALPHA);

        // Тело кучи: прямоугольник от земли до вершины
        let top = pile.base_y - peak - 2.0;
        let quad = [0.0, top, width, top, width, pile.base_y, 0.0, top, width, pile.base_y, 0.0, pile.base_y];
        gl.use_program(Some(self.body));
        let u = |n: &str| gl.get_uniform_location(self.body, n);
        gl.uniform_2_f32(u("u_size").as_ref(), width, height);
        gl.uniform_1_f32(u("u_columns_w").as_ref(), columns_w);
        gl.uniform_1_f32(u("u_base").as_ref(), pile.base_y);
        gl.uniform_1_f32(u("u_textured").as_ref(), if self.tile.is_some() { 1.0 } else { 0.0 });
        let [r, g, b] = rgb(l.fill);
        gl.uniform_3_f32(u("u_fill").as_ref(), r, g, b);
        let [r, g, b] = rgb(l.stroke.0);
        gl.uniform_4_f32(u("u_stroke").as_ref(), r, g, b, l.stroke.1);
        gl.uniform_3_f32(u("u_shade").as_ref(), r, g, b);
        gl.uniform_1_f32(u("u_opacity").as_ref(), opacity);
        gl.uniform_1_i32(u("u_heights").as_ref(), 0);
        gl.uniform_1_i32(u("u_tile").as_ref(), 1);
        gl.active_texture(glow::TEXTURE1);
        gl.bind_texture(glow::TEXTURE_2D, self.tile.or(Some(heights)));
        gl.active_texture(glow::TEXTURE0);
        gl.bind_texture(glow::TEXTURE_2D, Some(heights));
        gl.bind_buffer(glow::ARRAY_BUFFER, Some(self.quad));
        let bytes = std::slice::from_raw_parts(quad.as_ptr() as *const u8, quad.len() * 4);
        gl.buffer_data_u8_slice(glow::ARRAY_BUFFER, bytes, glow::STREAM_DRAW);
        let a = gl.get_attrib_location(self.body, "a_pos").unwrap();
        gl.enable_vertex_attrib_array(a);
        gl.vertex_attrib_pointer_f32(a, 2, glow::FLOAT, false, 8, 0);
        gl.draw_arrays(glow::TRIANGLES, 0, 6);
        gl.disable_vertex_attrib_array(a);

        // Край: листья/лепестки сидят на контуре и наполовину торчат над ним
        if self.sprites.is_empty() {
            return;
        }
        let first = self.edge_sets(gl, width);
        gl.use_program(Some(self.edge));
        let u = |n: &str| gl.get_uniform_location(self.edge, n);
        gl.uniform_2_f32(u("u_size").as_ref(), width, height);
        gl.uniform_1_f32(u("u_columns_w").as_ref(), columns_w);
        gl.uniform_1_f32(u("u_base").as_ref(), pile.base_y);
        gl.uniform_1_f32(u("u_opacity").as_ref(), opacity);
        gl.uniform_1_i32(u("u_heights").as_ref(), 0);
        gl.uniform_1_i32(u("u_texture").as_ref(), 1);
        gl.enable(glow::PROGRAM_POINT_SIZE);
        let a = gl.get_attrib_location(self.edge, "a_slot").unwrap();
        for (_, set) in &self.edges[first..first + self.sprites.len()] {
            gl.active_texture(glow::TEXTURE1);
            gl.bind_texture(glow::TEXTURE_2D, Some(set.texture));
            gl.bind_buffer(glow::ARRAY_BUFFER, Some(set.buffer));
            gl.enable_vertex_attrib_array(a);
            gl.vertex_attrib_pointer_f32(a, 4, glow::FLOAT, false, 16, 0);
            gl.draw_arrays(glow::POINTS, 0, set.count);
            gl.disable_vertex_attrib_array(a);
        }
        gl.active_texture(glow::TEXTURE0);
    }
}
