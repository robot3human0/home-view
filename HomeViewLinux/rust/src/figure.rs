//! Человечек коллеги (порт avatar.py / art.person_parts): спрайты 8 px/pt, перекраска, походка,
//! «Отошёл» сидит, «Занят» полупрозрачный, табличка с именем и облачко.

use std::collections::HashMap;
use std::f32::consts::PI;
use std::time::Instant;

use glow::HasContext;

use crate::gfx::{self, Affine, Image, SpriteBatch, Texture};
use crate::particles::art_dir;
use crate::text::Text;

use homeview::protocol::{AvatarStyle as Style, HatStyle as Hat, PeerInfo, PeerStatus as Status};

/// Прямоугольник в точках, ось Y вверх: (x, y) — левый нижний угол.
#[derive(Clone, Copy)]
struct BoxPt { x: f32, y: f32, w: f32, h: f32 }

const LEG_BOX: BoxPt = BoxPt { x: -2.6, y: -11.2, w: 6.4, h: 11.4 };
const ARM_BOX: BoxPt = BoxPt { x: -2.4, y: -12.4, w: 4.8, h: 12.6 };
const BODY_BOX: BoxPt = BoxPt { x: -9.8, y: 9.6, w: 20.6, h: 33.4 };
const LEG_LEFT_AT: (f32, f32) = (-2.6, 11.0);
const LEG_RIGHT_AT: (f32, f32) = (2.6, 11.0);
const ARM_BACK_AT: (f32, f32) = (-4.0, 22.0);
const ARM_FRONT_AT: (f32, f32) = (3.0, 22.0);
const FIGURE_HEIGHT: f32 = 46.0;

pub struct Art {
    images: HashMap<&'static str, Image>,
}

impl Art {
    pub fn new() -> Art {
        Art { images: HashMap::new() }
    }
    fn image(&mut self, name: &'static str) -> &Image {
        self.images.entry(name).or_insert_with(|| Image::load_png(&art_dir().join(format!("{name}.png"))))
    }
    fn composed(&mut self, layers: &[(&'static str, Option<u32>)]) -> Image {
        let first = self.image(layers[0].0);
        let mut out = Image::empty(first.width, first.height);
        for &(name, tint) in layers {
            let src = self.image(name).clone();
            out.draw_over(&src, tint);
        }
        out
    }
}

fn blend(a: u32, b: u32, t: f32) -> u32 {
    let mut out = 0;
    for shift in [16, 8, 0] {
        let ca = ((a >> shift) & 0xFF) as f32;
        let cb = ((b >> shift) & 0xFF) as f32;
        out |= ((ca * (1.0 - t) + cb * t).round() as u32) << shift;
    }
    out
}

pub struct Parts {
    leg: Texture,
    arm_back: Texture,
    arm_front: Texture,
    body: Texture,
}

impl Parts {
    unsafe fn delete(&self, gl: &glow::Context) {
        for t in [self.leg, self.arm_back, self.arm_front, self.body] {
            gl.delete_texture(t.id);
        }
    }

    pub unsafe fn build(gl: &glow::Context, art: &mut Art, style: Style) -> Parts {
        let hand = ("hv_person_hand", Some(style.skin_color));
        let hat: Vec<(&'static str, Option<u32>)> = match style.hat {
            Hat::Beanie => vec![("hv_hat_beanie", Some(style.hat_color)), ("hv_hat_beanie_pom", None)],
            Hat::Cap => vec![("hv_hat_cap", Some(style.hat_color))],
            Hat::Doppi => vec![("hv_hat_doppi", None)],
            Hat::StrawHat => vec![("hv_hat_straw", None), ("hv_hat_straw_band", Some(style.hat_color))],
        };
        let mut body = vec![("hv_person_torso", Some(style.vest_color)), ("hv_person_jacket", None),
                            ("hv_person_head", Some(style.skin_color)), ("hv_person_face", None)];
        body.extend(hat);
        let up = |img: &Image| gfx::upload(gl, img.width, img.height, &img.data, true);
        Parts {
            leg: up(&art.composed(&[("hv_person_leg", None)])),
            arm_back: up(&art.composed(&[("hv_person_sleeve", Some(blend(style.vest_color, 0, 0.15))), hand])),
            arm_front: up(&art.composed(&[("hv_person_sleeve", Some(style.vest_color)), hand])),
            body: up(&art.composed(&body)),
        }
    }
}

struct Clip { values: &'static [f32], times: &'static [f32], duration: f32, start: Instant }

impl Clip {
    fn value(&self, now: Instant) -> Option<f32> {
        let t = (now - self.start).as_secs_f32() / self.duration;
        if t >= 1.0 {
            return None;
        }
        let (v, k) = (self.values, self.times);
        for i in 1..k.len() {
            if t <= k[i] {
                let span = k[i] - k[i - 1];
                let local = if span > 0.0 { (t - k[i - 1]) / span } else { 1.0 };
                return Some(v[i - 1] + (v[i] - v[i - 1]) * local);
            }
        }
        v.last().copied()
    }
}

pub struct Label { texture: Texture }

pub struct Peer {
    pub info: PeerInfo,
    pub status: Status,
    style: Style,
    parts: Parts,
    pub x: f32,
    pub ground_y: f32,
    scale: f32,
    text_scale: f32,
    facing: f32,
    target_x: f32,
    pause: f32,
    walking: bool,
    walk_time: f32,
    wave: Option<Clip>,
    hop: Option<Clip>,
    throw: Option<Clip>,
    flinch: Option<Clip>,
    tag: Label,
    bubble: Option<(Label, Instant, Instant)>,
    /// Высота ступней над землёй (тащат мышью или падает после этого).
    air: f32,
    fall_speed: f32,
    dragged: bool,
    drag_time: f32,
    /// Ширина окна — чтобы облачко не вылезало за край.
    screen_w: f32,
}

pub fn rgba(hex: u32, alpha: u8) -> [u8; 4] {
    [(hex >> 16) as u8, (hex >> 8) as u8, hex as u8, alpha]
}

unsafe fn label(gl: &glow::Context, img: &Image) -> Label {
    Label { texture: gfx::upload(gl, img.width, img.height, &img.data, false) }
}

impl Peer {
    pub unsafe fn new(gl: &glow::Context, art: &mut Art, text: &mut Text, info: &PeerInfo,
                      x: f32, scale: f32, text_scale: f32) -> Peer {
        let tag = Self::make_tag(gl, text, info, text_scale);
        Peer {
            info: info.clone(), status: info.status, style: info.avatar, parts: Parts::build(gl, art, info.avatar),
            x, ground_y: 0.0, scale, text_scale,
            facing: 1.0, target_x: x, pause: 1.0 + fastrand::f32() * 3.0, walking: false, walk_time: 0.0,
            wave: None, hop: None, throw: None, flinch: None, tag, bubble: None, air: 0.0, fall_speed: 0.0, dragged: false, drag_time: 0.0,
            screen_w: f32::MAX,
        }
    }

    unsafe fn make_tag(gl: &glow::Context, text: &mut Text, info: &PeerInfo, text_scale: f32) -> Label {
        let mut tag = info.name.clone();
        if !info.team.is_empty() {
            tag = format!("{tag} · {}", info.team);
        }
        match info.status {
            Status::Away => tag = format!("☕ {tag}"),
            Status::Busy => tag = format!("🔕 {tag}"),
            _ => {}
        }
        label(gl, &text.pill(&tag, rgba(0x0F1B2D, 199), text_scale))
    }

    /// Коллега сменил имя, шапку или статус.
    pub unsafe fn update_info(&mut self, gl: &glow::Context, art: &mut Art, text: &mut Text, info: &PeerInfo) {
        if *info == self.info {
            return;
        }
        if info.avatar != self.style {
            self.parts.delete(gl);
            self.parts = Parts::build(gl, art, info.avatar);
            self.style = info.avatar;
        }
        if info.status == Status::Away && self.status != Status::Away {
            self.walking = false;
        }
        gl.delete_texture(self.tag.texture.id);
        self.tag = Self::make_tag(gl, text, info, self.text_scale);
        self.status = info.status;
        self.info = info.clone();
    }

    pub unsafe fn delete(&mut self, gl: &glow::Context) {
        self.parts.delete(gl);
        gl.delete_texture(self.tag.texture.id);
        if let Some((b, _, _)) = self.bubble.take() {
            gl.delete_texture(b.texture.id);
        }
    }

    fn top_y(&self) -> f32 {
        self.ground_y - self.air - FIGURE_HEIGHT * self.scale
    }

    /// Ступни (экранные координаты).
    pub fn feet(&self) -> (f32, f32) {
        (self.x, self.ground_y - self.air)
    }

    /// Насколько центр может подойти к краю экрана: фигура видна целиком
    /// (табличка и облачко у края сами сдвигаются внутрь — см. label_x).
    fn margin(&self) -> f32 {
        11.0 * self.scale + 4.0
    }

    /// Левый край надписи шириной `w` над человечком; у края экрана — сдвинута внутрь.
    fn label_x(&self, w: f32) -> f32 {
        (self.x - w / 2.0).min(self.screen_w - w - 2.0).max(2.0).round()
    }

    pub fn clamp_x(&mut self, width: f32) {
        self.screen_w = width;
        let m = self.margin().min(width / 2.0);
        self.x = self.x.clamp(m, width - m);
        self.target_x = self.target_x.clamp(m, width - m);
    }

    // MARK: - Перетаскивание мышью

    pub fn start_drag(&mut self) {
        self.dragged = true;
        self.drag_time = 0.0;
        self.walking = false;
    }

    /// Ступни — в точку (x, y) экрана; ниже земли не опускаем.
    pub fn drag_to(&mut self, x: f32, feet_y: f32, width: f32) {
        self.x = x;
        self.air = (self.ground_y - feet_y).max(0.0);
        self.clamp_x(width);
    }

    /// Отпустили: падает на землю и какое-то время стоит на новом месте.
    pub fn drop_down(&mut self) {
        self.dragged = false;
        self.fall_speed = 0.0;
        self.target_x = self.x;
        self.pause = 4.0 + fastrand::f32() * 4.0;
    }


    /// Где человечек ловит мышь (экранные координаты, Y вниз): отдельно фигура и табличка —
    /// одна общая рамка была бы шириной с табличку и ловила клики рядом с фигурой.
    pub fn hit_rects(&self) -> [(f32, f32, f32, f32); 2] {
        let s = self.scale;
        let figure = (self.x - 11.0 * s, self.top_y(), 22.0 * s, FIGURE_HEIGHT * s + 2.0);
        let (tw, th) = (self.tag.texture.width as f32, self.tag.texture.height as f32);
        let tag = (self.label_x(tw), (self.top_y() - 10.0 * self.text_scale - th / 2.0).round(), tw, th);
        [figure, tag]
    }

    pub fn contains(&self, x: f32, y: f32) -> bool {
        self.hit_rects().iter().any(|&(rx, ry, rw, rh)| x >= rx && x < rx + rw && y >= ry && y < ry + rh)
    }

    pub fn wave(&mut self) {
        if self.wave.is_none() {
            self.wave = Some(Clip { values: &[-0.4, -2.7, -2.2, -2.7, -2.2, -0.4], times: &[0.0, 0.2, 0.4, 0.6, 0.8, 1.0],
                                    duration: 1.0, start: Instant::now() });
        }
    }

    /// Замах передней рукой (бросок снаряда).
    pub fn throw_motion(&mut self) {
        self.throw = Some(Clip { values: &[0.15, -2.6, 0.9, 0.15], times: &[0.0, 0.45, 0.64, 1.0], duration: 0.55,
                                 start: Instant::now() });
    }

    /// Вздрагивает от попадания.
    pub fn flinch(&mut self) {
        self.flinch = Some(Clip { values: &[0.0, -0.25, 0.18, 0.0], times: &[0.0, 1.0 / 3.0, 2.0 / 3.0, 1.0],
                                  duration: 0.3, start: Instant::now() });
    }

    /// Откуда летит брошенный им снаряд (экранные координаты).
    pub fn hand_point(&self) -> (f32, f32) {
        (self.x + self.facing * 5.0 * self.scale, self.ground_y - self.air - 34.0 * self.scale)
    }

    /// Куда попадает снаряд.
    pub fn chest_point(&self) -> (f32, f32) {
        (self.x, self.ground_y - self.air - 26.0 * self.scale)
    }

    pub fn hop(&mut self) {
        self.hop = Some(Clip { values: &[0.0, 14.0, 0.0], times: &[0.0, 0.5, 1.0], duration: 0.34, start: Instant::now() });
    }

    pub unsafe fn say(&mut self, gl: &glow::Context, text: &mut Text, message: &str, seconds: f32) {
        let now = Instant::now();
        let img = text.bubble(message, self.text_scale);
        if let Some((old, _, _)) = self.bubble.take() {
            gl.delete_texture(old.texture.id);
        }
        self.bubble = Some((label(gl, &img), now, now + std::time::Duration::from_secs_f32(seconds)));
    }

    pub fn tick(&mut self, dt: f32, width: f32) {
        self.clamp_x(width);
        if self.dragged {
            self.drag_time += dt;
            return;
        }
        if self.air > 0.0 {
            self.fall_speed += 2400.0 * dt;
            self.air = (self.air - self.fall_speed * dt).max(0.0);
            if self.air == 0.0 && self.fall_speed > 300.0 {
                self.hop = Some(Clip { values: &[0.0, 5.0, 0.0], times: &[0.0, 0.5, 1.0], duration: 0.2, start: Instant::now() });
            }
            return;
        }
        if self.status != Status::Away {
            if self.pause > 0.0 {
                self.pause -= dt;
                if self.pause <= 0.0 {
                    let m = self.margin().min(width / 2.0);
                    self.target_x = (self.x + (fastrand::f32() * 640.0 - 320.0)).clamp(m, width - m);
                    self.facing = if self.target_x >= self.x { 1.0 } else { -1.0 };
                    self.walking = true;
                }
            } else {
                let dx = self.target_x - self.x;
                let speed = if self.status == Status::Busy { 22.0 } else { 42.0 } * self.scale.sqrt();
                let step = speed * dt;
                if dx.abs() <= step {
                    self.x = self.target_x;
                    self.walking = false;
                    self.pause = 2.5 + fastrand::f32() * 5.5;
                } else {
                    self.x += step * dx.signum();
                }
            }
        }
        if self.walking {
            self.walk_time += dt;
        }
    }

    pub unsafe fn draw(&mut self, gl: &glow::Context, batch: &mut SpriteBatch, now: Instant) {
        let s = self.scale;
        let busy = self.status == Status::Busy;
        let (mut leg_l, mut leg_r, mut arm_back, mut arm_front, mut dy, mut lift) = (0.0, 0.0, 0.0, 0.15, 0.0, 0.0);
        if self.dragged || self.air > 0.0 {
            // Висит в воздухе: болтает ногами, руки вверх
            let swing = (self.drag_time * 7.0).sin();
            (leg_l, leg_r, arm_back) = (0.35 * swing, -0.3 * swing, -2.5);
        } else if self.status == Status::Away {
            (leg_l, leg_r, dy) = (1.35, 1.2, -8.0);
        } else if self.walking {
            let swing = (2.0 * PI * self.walk_time / 0.44).sin();
            (leg_l, leg_r, arm_back) = (0.45 * swing, -0.45 * swing, -0.35 * swing);
            lift = 1.1 * (PI * self.walk_time / 0.44).sin().abs();
        }
        if let Some(v) = self.wave.as_ref().and_then(|c| c.value(now)) { arm_back = v } else { self.wave = None }
        if let Some(v) = self.hop.as_ref().and_then(|c| c.value(now)) { lift += v } else { self.hop = None }
        if let Some(v) = self.throw.as_ref().and_then(|c| c.value(now)) { arm_front = v } else { self.throw = None }
        let rot = match self.flinch.as_ref().and_then(|c| c.value(now)) {
            Some(v) => v,
            None => {
                self.flinch = None;
                0.0
            }
        };

        let alpha = if busy { 0.55 } else { 1.0 };
        let m = Affine::IDENTITY.translate(self.x, self.ground_y - self.air).scale(self.facing * s, -s).translate(0.0, lift + dy).rotate(rot);
        let white = [1.0, 1.0, 1.0];
        let part = |batch: &mut SpriteBatch, tex: Texture, at: (f32, f32), angle: f32, b: BoxPt| {
            let mm = m.translate(at.0, at.1).rotate(angle);
            batch.quad(gl, tex, &mm, b.x, b.y + b.h, b.w, -b.h, white, alpha);
        };
        part(batch, self.parts.leg, LEG_LEFT_AT, leg_l, LEG_BOX);
        part(batch, self.parts.leg, LEG_RIGHT_AT, leg_r, LEG_BOX);
        part(batch, self.parts.arm_back, ARM_BACK_AT, arm_back, ARM_BOX);
        part(batch, self.parts.body, (0.0, 0.0), 0.0, BODY_BOX);
        part(batch, self.parts.arm_front, ARM_FRONT_AT, arm_front, ARM_BOX);

        // Подписи — в экранных пикселях, по целым координатам (чёткий текст)
        let k = self.text_scale;
        let top = self.top_y();
        let tag = self.tag.texture;
        self.centered(gl, batch, tag, top - 10.0 * k, if busy { 0.7 } else { 1.0 });
        if let Some((b, born, until)) = &self.bubble {
            if now >= *until {
                gl.delete_texture(b.texture.id);
                self.bubble = None;
            } else {
                let fade = ((now - *born).as_secs_f32() / 0.15).min((*until - now).as_secs_f32() / 0.3).min(1.0);
                let tex = b.texture;
                let y = top - 30.0 * k - tex.height as f32 / 2.0 + 8.0 * k;
                self.centered(gl, batch, tex, y, fade.max(0.0));
            }
        }
    }

    unsafe fn centered(&self, gl: &glow::Context, batch: &mut SpriteBatch, tex: Texture, center_y: f32, alpha: f32) {
        let (w, h) = (tex.width as f32, tex.height as f32);
        let (x, y) = (self.label_x(w), (center_y - h / 2.0).round());
        batch.quad(gl, tex, &Affine::IDENTITY, x, y, w, h, [1.0, 1.0, 1.0], alpha);
    }
}
