//! Короткие эффекты (порт effects.py): летящий снаряд, клякса на экране, брызги.
//! Картинки снаряда и клякс рисуются один раз (tiny-skia) по цветам сезона, как art.ball / art.splat.

use std::f32::consts::PI;

use tiny_skia::{Color, FillRule, GradientStop, Paint, PathBuilder, Pixmap, Point, RadialGradient, SpreadMode,
                Stroke, Transform};

use crate::gfx::{self, Affine, SpriteBatch, Texture};
use crate::text::to_image;

/// (верх, середина, край) снаряда
fn ball_colors(season: &str) -> (u32, u32, u32) {
    match season {
        "spring" => (0xFFEEF5, 0xF59ABD, 0xD96699),
        "summer" => (0xE3F4FF, 0x6EC3F2, 0x2F86C6),
        "autumn" => (0xFFE0A3, 0xF08A24, 0xB5541A),
        _ => (0xFFFFFF, 0xC9D6EA, 0x8FA3C2),
    }
}

/// (заливка, её прозрачность, контур) кляксы
fn splat_colors(season: &str) -> (u32, f32, u32) {
    match season {
        "spring" => (0xFCE4EC, 0.95, 0xF48FB1),
        "summer" => (0xBFE6FF, 0.70, 0x4FA8E0),
        "autumn" => (0xF3B35B, 0.95, 0xB5651D),
        _ => (0xFFFFFF, 0.96, 0xA9B9CF),
    }
}

fn color(hex: u32, alpha: f32) -> Color {
    Color::from_rgba8((hex >> 16) as u8, (hex >> 8) as u8, hex as u8, (alpha * 255.0).round() as u8)
}

pub fn rgb(hex: u32) -> [f32; 3] {
    [((hex >> 16) & 0xFF) as f32 / 255.0, ((hex >> 8) & 0xFF) as f32 / 255.0, (hex & 0xFF) as f32 / 255.0]
}

fn circle(cx: f32, cy: f32, rx: f32, ry: f32) -> tiny_skia::Path {
    PathBuilder::from_oval(tiny_skia::Rect::from_xywh(cx - rx, cy - ry, rx * 2.0, ry * 2.0).unwrap()).unwrap()
}

fn ball_image(season: &str, size: u32) -> crate::gfx::Image {
    let (top, middle, rim) = ball_colors(season);
    let s = size as f32;
    let mut pixmap = Pixmap::new(size, size).unwrap();
    let radius = s / 2.0 - 1.0;
    let gradient = RadialGradient::new(Point::from_xy(s * 0.38, s * 0.34), Point::from_xy(s * 0.38, s * 0.34),
        radius * 1.2, vec![GradientStop::new(0.0, color(top, 1.0)), GradientStop::new(0.6, color(middle, 1.0)),
                           GradientStop::new(1.0, color(rim, 1.0))], SpreadMode::Pad, Transform::identity()).unwrap();
    let mut paint = Paint { shader: gradient, anti_alias: true, ..Paint::default() };
    pixmap.fill_path(&circle(s / 2.0, s / 2.0, radius, radius), &paint, FillRule::Winding, Transform::identity(), None);
    paint = Paint { anti_alias: true, ..Paint::default() };
    paint.set_color_rgba8(255, 255, 255, 150);
    pixmap.fill_path(&circle(s * 0.36, s * 0.32, radius * 0.22, radius * 0.16), &paint, FillRule::Winding,
                     Transform::identity(), None);
    to_image(pixmap)
}

/// Неровное пятно с брызгами вокруг (art.splat).
fn splat_image(season: &str, rng: &mut fastrand::Rng, size: u32) -> crate::gfx::Image {
    let (fill, alpha, rim) = splat_colors(season);
    let s = size as f32;
    let c = s / 2.0;
    let mut pixmap = Pixmap::new(size, size).unwrap();
    let points = 14;
    let base = s * 0.26;
    let radii: Vec<f32> = (0..points).map(|_| base * (0.75 + rng.f32() * 0.5)).collect();
    let mut pb = PathBuilder::new();
    for i in 0..=points {
        let angle = 2.0 * PI * i as f32 / points as f32;
        let r = radii[i % points]; // последняя точка = первая: контур замыкается без ровного среза
        let (px, py) = (c + angle.cos() * r, c + angle.sin() * r);
        if i == 0 {
            pb.move_to(px, py);
        } else {
            let mid = angle - PI / points as f32;
            pb.quad_to(c + mid.cos() * base * 1.35, c + mid.sin() * base * 1.35, px, py);
        }
    }
    pb.close();
    let blob = pb.finish().unwrap();
    let mut paint = Paint { anti_alias: true, ..Paint::default() };
    paint.set_color(color(fill, alpha));
    let mut stroke_paint = Paint { anti_alias: true, ..Paint::default() };
    stroke_paint.set_color(color(rim, 0.6));
    let stroke = Stroke { width: 1.0, ..Stroke::default() };
    pixmap.fill_path(&blob, &paint, FillRule::Winding, Transform::identity(), None);
    pixmap.stroke_path(&blob, &stroke_paint, &stroke, Transform::identity(), None);
    for _ in 0..9 {
        let angle = rng.f32() * 2.0 * PI;
        let distance = base * 1.25 + rng.f32() * (s * 0.46 - base * 1.25);
        let r = 2.0 + rng.f32() * (s * 0.05 - 2.0);
        let dot = circle(c + angle.cos() * distance, c + angle.sin() * distance, r, r);
        pixmap.fill_path(&dot, &paint, FillRule::Winding, Transform::identity(), None);
        pixmap.stroke_path(&dot, &stroke_paint, &stroke, Transform::identity(), None);
    }
    paint.set_color_rgba8(255, 255, 255, 110);
    pixmap.fill_path(&circle(c - base * 0.3, c - base * 0.35, base * 0.35, base * 0.22), &paint, FillRule::Winding,
                     Transform::identity(), None);
    to_image(pixmap)
}

/// Картинки эффектов текущего сезона.
pub struct EffectArt {
    pub season: String,
    ball: Texture,
    splats: Vec<Texture>,
    dot: Texture,
}

impl EffectArt {
    pub unsafe fn new(gl: &glow::Context, season: &str) -> EffectArt {
        let up = |img: crate::gfx::Image| gfx::upload(gl, img.width, img.height, &img.data, true);
        let mut rng = fastrand::Rng::new();
        let splats = (0..6).map(|_| up(splat_image(season, &mut rng, 160))).collect();
        // Белый кружок для брызг (перекрашивается при рисовании)
        let mut pixmap = Pixmap::new(32, 32).unwrap();
        let mut paint = Paint { anti_alias: true, ..Paint::default() };
        paint.set_color_rgba8(255, 255, 255, 255);
        pixmap.fill_path(&circle(16.0, 16.0, 15.0, 15.0), &paint, FillRule::Winding, Transform::identity(), None);
        EffectArt { season: season.into(), ball: up(ball_image(season, 96)), splats, dot: up(to_image(pixmap)) }
    }

    pub fn burst_colors(&self) -> [[f32; 3]; 2] {
        let (top, middle, _) = ball_colors(&self.season);
        [rgb(top), rgb(middle)]
    }
}

/// Что сделать, когда снаряд долетел.
#[derive(Clone, Debug)]
pub enum Landed {
    /// В нас: клякса на экране.
    Splat { x: f32, y: f32 },
    /// Мы попали в коллегу: брызги, он вздрагивает, сообщаем серверу.
    Hit { peer_id: String },
}

pub enum Effect {
    Flying {
        start: (f32, f32),
        end: (f32, f32),
        control: (f32, f32),
        duration: f32,
        from_scale: f32,
        to_scale: f32,
        size: f32,
        ease_in: bool,
        elapsed: f32,
        spin: f32,
        landed: Option<Landed>,
    },
    Splat { x: f32, y: f32, size: f32, hold: f32, fade: f32, elapsed: f32, rotation: f32, variant: usize },
    Burst { items: Vec<[f32; 5]>, colors: [[f32; 3]; 2], gravity: f32, lifetime: f32, elapsed: f32 },
}

impl Effect {
    /// Снаряд по квадратичной кривой Безье с изменением размера (иллюзия глубины).
    #[allow(clippy::too_many_arguments)]
    pub fn flying(start: (f32, f32), end: (f32, f32), control: (f32, f32), duration: f32, from_scale: f32,
                  to_scale: f32, size: f32, ease_in: bool, delay: f32, landed: Landed) -> Effect {
        Effect::Flying { start, end, control, duration, from_scale, to_scale, size, ease_in, elapsed: -delay,
                         spin: fastrand::f32() * 12.0 - 6.0, landed: Some(landed) }
    }

    pub fn splat(x: f32, y: f32, size: f32) -> Effect {
        Effect::Splat { x, y, size, hold: 6.0, fade: 2.0, elapsed: 0.0, rotation: fastrand::f32() * 2.0 * PI,
                        variant: fastrand::usize(..6) }
    }

    /// Брызги: точки разлетаются вверх и в стороны и падают.
    pub fn burst(x: f32, y: f32, colors: [[f32; 3]; 2], count: usize) -> Effect {
        let items = (0..count).map(|_| {
            let angle = -PI * fastrand::f32();
            let v = 160.0 * (0.5 + fastrand::f32() * 0.7);
            [x, y, angle.cos() * v, angle.sin() * v, 1.5 + fastrand::f32() * 1.7]
        }).collect();
        Effect::Burst { items, colors, gravity: 520.0, lifetime: 0.9, elapsed: 0.0 }
    }

    /// false — эффект закончился. Долетевший снаряд отдаёт `Landed`.
    pub fn tick(&mut self, dt: f32, landed: &mut Vec<Landed>) -> bool {
        match self {
            Effect::Flying { elapsed, duration, landed: l, .. } => {
                *elapsed += dt;
                if *elapsed >= *duration {
                    if let Some(x) = l.take() {
                        landed.push(x);
                    }
                    return false;
                }
                true
            }
            Effect::Splat { elapsed, hold, fade, .. } => {
                *elapsed += dt;
                *elapsed < *hold + *fade
            }
            Effect::Burst { items, gravity, lifetime, elapsed, .. } => {
                *elapsed += dt;
                for p in items.iter_mut() {
                    p[0] += p[2] * dt;
                    p[1] += p[3] * dt;
                    p[3] += *gravity * dt;
                }
                *elapsed < *lifetime
            }
        }
    }

    pub unsafe fn draw(&self, gl: &glow::Context, batch: &mut SpriteBatch, art: &EffectArt) {
        let white = [1.0, 1.0, 1.0];
        match self {
            Effect::Flying { start, end, control, duration, from_scale, to_scale, size, ease_in, elapsed, spin, .. } => {
                if *elapsed < 0.0 {
                    return;
                }
                let t = (elapsed / duration).min(1.0);
                let t = if *ease_in { t * t } else { 1.0 - (1.0 - t) * (1.0 - t) };
                let u = 1.0 - t;
                let x = u * u * start.0 + 2.0 * u * t * control.0 + t * t * end.0;
                let y = u * u * start.1 + 2.0 * u * t * control.1 + t * t * end.1;
                let side = size * (from_scale + (to_scale - from_scale) * t);
                let m = Affine::IDENTITY.translate(x, y).rotate(spin * elapsed);
                batch.quad(gl, art.ball, &m, -side / 2.0, -side / 2.0, side, side, white, 1.0);
            }
            Effect::Splat { x, y, size, hold, fade, elapsed, rotation, variant } => {
                let appear = (elapsed / 0.12).min(1.0);
                let (mut opacity, mut slide) = (1.0, 0.0);
                if elapsed > hold {
                    let k = (elapsed - hold) / fade;
                    opacity = (1.0 - k).max(0.0);
                    slide = 18.0 * k; // стекает вниз и тает
                }
                let side = size * (0.6 + 0.4 * appear);
                let m = Affine::IDENTITY.translate(*x, y + slide).rotate(*rotation);
                batch.quad(gl, art.splats[*variant], &m, -side / 2.0, -side / 2.0, side, side, white, opacity);
            }
            Effect::Burst { items, colors, lifetime, elapsed, .. } => {
                let alpha = (1.0 - elapsed / lifetime).max(0.0);
                for (i, p) in items.iter().enumerate() {
                    let r = p[4];
                    batch.quad(gl, art.dot, &Affine::IDENTITY, p[0] - r, p[1] - r, r * 2.0, r * 2.0, colors[i % 2], alpha);
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// `EFFECTS_PREVIEW=/путь/fx.png cargo test --release --bin homeview effects_preview -- --ignored`
    #[test]
    #[ignore]
    fn effects_preview() {
        let mut out = image::RgbaImage::from_pixel(4 * 180, 280, image::Rgba([60, 70, 80, 255]));
        let mut rng = fastrand::Rng::with_seed(7);
        for (i, season) in ["winter", "spring", "summer", "autumn"].iter().enumerate() {
            for (img, ox, oy) in [(ball_image(season, 96), 40, 10), (splat_image(season, &mut rng, 160), 10, 115)] {
                for (k, px) in img.data.chunks(4).enumerate() {
                    let (x, y) = (i as u32 * 180 + ox + k as u32 % img.width, oy + k as u32 / img.width);
                    let a = px[3] as u32;
                    let bg = out.get_pixel(x, y).0;
                    let c = |j: usize| (px[j] as u32 + bg[j] as u32 * (255 - a) / 255).min(255) as u8;
                    out.put_pixel(x, y, image::Rgba([c(0), c(1), c(2), 255]));
                }
            }
        }
        out.save(std::env::var("EFFECTS_PREVIEW").unwrap()).unwrap();
    }
}
