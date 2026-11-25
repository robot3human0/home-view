//! Карточки-уведомления в правом верхнем углу основного монитора (аналог Toasts.swift / toasts.py).
//! Рисуются в оверлее; картинка карточки готовится на CPU и перерисовывается только при смене подсветки.

use std::time::{Duration, Instant};

use cosmic_text::{Color, Weight};
use homeview::office::{ActionKind, Toast};
use tiny_skia::{FillRule, Paint, Pixmap, Stroke, Transform};

use crate::gfx::{self, Affine, SpriteBatch, Texture};
use crate::text::{rounded_rect, to_image, Text};

const WIDTH: f32 = 340.0;
const MARGIN: f32 = 14.0;
const GAP: f32 = 10.0;
const MAX_VISIBLE: usize = 5;
const FADE: f32 = 0.2;

#[derive(Clone, Copy, PartialEq, Debug)]
enum Hot {
    Button(usize),
    Close,
}

/// Прямоугольник внутри карточки.
#[derive(Clone, Copy, Debug)]
struct Rect { x: f32, y: f32, w: f32, h: f32 }

impl Rect {
    fn contains(&self, x: f32, y: f32) -> bool {
        x >= self.x && x < self.x + self.w && y >= self.y && y < self.y + self.h
    }
}

struct Card {
    toast: Toast,
    w: f32,
    h: f32,
    buttons: Vec<Rect>,
    close: Rect,
    hot: Option<Hot>,
    texture: Option<Texture>,
    dirty: bool,
    /// Текущая и целевая вертикаль (плавный сдвиг стопки).
    y: f32,
    target_y: f32,
    born: Instant,
    /// Сколько ещё показывать (таймер стоит, пока курсор над карточкой).
    left: Duration,
    closing: Option<Instant>,
}

pub enum Click {
    /// Нажата кнопка карточки — выполнить действие.
    Action(ActionKind),
    /// Попали в карточку (✕ или просто по ней) — больше ничего не делать.
    Handled,
}

pub struct Toasts {
    cards: Vec<Card>,
    scale: f32,
    hovered: Option<usize>,
}

struct Metrics { k: f32 }

impl Metrics {
    fn px(&self, v: f32) -> f32 { (v * self.k).round().max(1.0) }
}

impl Toasts {
    pub fn new(scale: f32) -> Toasts {
        Toasts { cards: Vec::new(), scale, hovered: None }
    }

    pub fn post(&mut self, text: &mut Text, toast: Toast) {
        if let Some(key) = &toast.key {
            for c in &mut self.cards {
                if c.toast.key.as_ref() == Some(key) && c.closing.is_none() {
                    c.closing = Some(Instant::now());
                }
            }
        }
        let card = self.layout(text, toast);
        self.cards.insert(0, card);
        let open: Vec<usize> = (0..self.cards.len()).filter(|&i| self.cards[i].closing.is_none()).collect();
        for &i in open.iter().skip(MAX_VISIBLE) {
            self.cards[i].closing = Some(Instant::now());
        }
        self.restack();
    }

    pub fn dismiss_key(&mut self, key: &str) {
        for c in &mut self.cards {
            if c.toast.key.as_deref() == Some(key) && c.closing.is_none() {
                c.closing = Some(Instant::now());
            }
        }
        self.restack();
    }

    /// Размеры и места кнопок — как в _Card из toasts.py.
    fn layout(&self, text: &mut Text, toast: Toast) -> Card {
        let m = Metrics { k: self.scale };
        let w = m.px(WIDTH);
        let (icon_w, _) = text.measure_line(&toast.icon, m.px(22.0), Weight::NORMAL);
        let (close_w, close_h) = text.measure_line("✕", m.px(14.0), Weight::NORMAL);
        let left = m.px(14.0) + icon_w + m.px(10.0);
        let column = w - left - m.px(10.0) - close_w - m.px(10.0);
        let mut y = m.px(12.0);
        let (_, th) = text.measure_wrapped(&toast.title, m.px(13.0), Weight::SEMIBOLD, column);
        y += th;
        if !toast.body.is_empty() {
            let (_, bh) = text.measure_wrapped(&toast.body, m.px(12.0), Weight::NORMAL, column);
            y += m.px(4.0) + bh;
        }
        let mut buttons = Vec::new();
        if !toast.actions.is_empty() {
            y += m.px(10.0);
            let mut x = left;
            let mut row_h: f32 = 0.0;
            for a in &toast.actions {
                let (tw, tl) = text.measure_line(&a.label, m.px(12.0), Weight::NORMAL);
                let r = Rect { x, y, w: tw + m.px(24.0), h: tl + m.px(10.0) };
                x += r.w + m.px(8.0);
                row_h = row_h.max(r.h);
                buttons.push(r);
            }
            y += row_h;
        }
        let h = (y + m.px(12.0)).max(m.px(22.0) * 1.3 + m.px(24.0)).ceil();
        let close = Rect { x: w - m.px(10.0) - close_w - m.px(6.0), y: m.px(6.0), w: close_w + m.px(12.0), h: close_h + m.px(12.0) };
        let left_time = toast.auto_dismiss;
        Card { toast, w, h, buttons, close, hot: None, texture: None, dirty: true, y: 0.0, target_y: 0.0,
               born: Instant::now(), left: left_time, closing: None }
    }

    fn restack(&mut self) {
        let m = Metrics { k: self.scale };
        let mut y = m.px(MARGIN);
        for c in &mut self.cards {
            if c.closing.is_some() {
                continue;
            }
            let fresh = c.texture.is_none() && c.target_y == 0.0 && c.y == 0.0;
            c.target_y = y;
            if fresh {
                c.y = y - m.px(16.0); // въезжает сверху
            }
            y += c.h + m.px(GAP);
        }
    }

    fn origin_x(&self, screen_w: f32, c: &Card) -> f32 {
        screen_w - c.w - (MARGIN * self.scale).round()
    }

    fn card_at(&self, screen_w: f32, x: f32, y: f32) -> Option<usize> {
        self.cards.iter().position(|c| c.closing.is_none() && {
            let ox = self.origin_x(screen_w, c);
            x >= ox && x < ox + c.w && y >= c.y && y < c.y + c.h
        })
    }

    /// Прямоугольники карточек — для области кликов окна (x, y, w, h).
    pub fn rects(&self, screen_w: f32) -> Vec<(f32, f32, f32, f32)> {
        self.cards.iter().filter(|c| c.closing.is_none())
            .map(|c| (self.origin_x(screen_w, c), c.y, c.w, c.h)).collect()
    }

    /// Курсор сдвинулся; возвращает «над кнопкой» (для курсора-руки) или None — не над карточкой.
    pub fn hover(&mut self, screen_w: f32, x: f32, y: f32) -> Option<bool> {
        let idx = self.card_at(screen_w, x, y);
        let mut over_button = None;
        for i in 0..self.cards.len() {
            let ox = self.origin_x(screen_w, &self.cards[i]);
            let c = &mut self.cards[i];
            let hot = if Some(i) == idx {
                let (lx, ly) = (x - ox, y - c.y);
                if c.close.contains(lx, ly) {
                    Some(Hot::Close)
                } else {
                    c.buttons.iter().position(|b| b.contains(lx, ly)).map(Hot::Button)
                }
            } else {
                None
            };
            if hot != c.hot {
                c.hot = hot;
                c.dirty = true;
            }
            if Some(i) == idx {
                over_button = Some(hot.is_some());
            }
        }
        self.hovered = idx;
        over_button
    }

    pub fn click(&mut self, screen_w: f32, x: f32, y: f32) -> Option<Click> {
        let i = self.card_at(screen_w, x, y)?;
        let ox = self.origin_x(screen_w, &self.cards[i]);
        let c = &mut self.cards[i];
        let (lx, ly) = (x - ox, y - c.y);
        let result = if c.close.contains(lx, ly) {
            c.closing = Some(Instant::now());
            Click::Handled
        } else if let Some(b) = c.buttons.iter().position(|b| b.contains(lx, ly)) {
            c.closing = Some(Instant::now());
            Click::Action(c.toast.actions[b].kind.clone())
        } else {
            Click::Handled
        };
        self.restack();
        Some(result)
    }

    pub fn tick(&mut self, dt: f32) {
        let now = Instant::now();
        let mut changed = false;
        for (i, c) in self.cards.iter_mut().enumerate() {
            if c.closing.is_none() && self.hovered != Some(i) {
                c.left = c.left.saturating_sub(Duration::from_secs_f32(dt));
                if c.left.is_zero() {
                    c.closing = Some(now);
                    changed = true;
                }
            }
            c.y += (c.target_y - c.y) * (1.0 - (-dt * 14.0).exp());
        }
        if changed {
            self.restack();
        }
    }

    /// Снять закрытые карточки (после затухания) — освободить текстуры.
    pub unsafe fn sweep(&mut self, gl: &glow::Context) {
        use glow::HasContext;
        let now = Instant::now();
        self.cards.retain(|c| {
            let gone = c.closing.is_some_and(|t| (now - t).as_secs_f32() > FADE);
            if gone {
                if let Some(t) = c.texture {
                    gl.delete_texture(t.id);
                }
            }
            !gone
        });
        if self.hovered.is_some_and(|i| i >= self.cards.len()) {
            self.hovered = None;
        }
    }

    fn render(&self, text: &mut Text, c: &Card) -> crate::gfx::Image {
        let m = Metrics { k: self.scale };
        let mut pixmap = Pixmap::new(c.w as u32, c.h as u32).unwrap();
        let mut paint = Paint::default();
        paint.anti_alias = true;
        let outline = rounded_rect(0.5, 0.5, c.w - 1.0, c.h - 1.0, m.px(14.0), None);
        paint.set_color_rgba8(18, 28, 44, 236);
        pixmap.fill_path(&outline, &paint, FillRule::Winding, Transform::identity(), None);
        paint.set_color_rgba8(255, 255, 255, 40);
        pixmap.stroke_path(&outline, &paint, &Stroke { width: 1.0, ..Stroke::default() }, Transform::identity(), None);

        let (icon_w, _) = text.measure_line(&c.toast.icon, m.px(22.0), Weight::NORMAL);
        text.draw_line(&mut pixmap, &c.toast.icon, m.px(22.0), Weight::NORMAL, m.px(14.0), m.px(10.0), Color::rgb(255, 255, 255));
        let left = m.px(14.0) + icon_w + m.px(10.0);
        let column = c.w - left - m.px(10.0) - c.close.w;
        let mut y = m.px(12.0);
        let (_, th) = text.measure_wrapped(&c.toast.title, m.px(13.0), Weight::SEMIBOLD, column);
        text.draw_wrapped(&mut pixmap, &c.toast.title, m.px(13.0), Weight::SEMIBOLD, column, left, y, Color::rgb(0xF4, 0xF7, 0xFB));
        y += th;
        if !c.toast.body.is_empty() {
            y += m.px(4.0);
            text.draw_wrapped(&mut pixmap, &c.toast.body, m.px(12.0), Weight::NORMAL, column, left, y, Color::rgb(0xC9, 0xD3, 0xE0));
        }
        for (i, (b, a)) in c.buttons.iter().zip(&c.toast.actions).enumerate() {
            let hot = c.hot == Some(Hot::Button(i));
            let r = rounded_rect(b.x, b.y, b.w, b.h, m.px(8.0), None);
            match (a.primary, hot) {
                (true, false) => paint.set_color_rgba8(0x2F, 0x7F, 0xE0, 255),
                (true, true) => paint.set_color_rgba8(0x3C, 0x8A, 0xEB, 255),
                (false, false) => paint.set_color_rgba8(255, 255, 255, 31),
                (false, true) => paint.set_color_rgba8(255, 255, 255, 51),
            }
            pixmap.fill_path(&r, &paint, FillRule::Winding, Transform::identity(), None);
            if a.primary {
                paint.set_color_rgba8(0x4C, 0x93, 0xEA, 255);
            } else {
                paint.set_color_rgba8(255, 255, 255, 46);
            }
            pixmap.stroke_path(&r, &paint, &Stroke { width: 1.0, ..Stroke::default() }, Transform::identity(), None);
            text.draw_line(&mut pixmap, &a.label, m.px(12.0), Weight::NORMAL, b.x + m.px(12.0), b.y + m.px(5.0),
                           Color::rgb(0xF4, 0xF7, 0xFB));
        }
        let close_color = if c.hot == Some(Hot::Close) { Color::rgb(255, 255, 255) } else { Color::rgb(0x9F, 0xB0, 0xC6) };
        text.draw_line(&mut pixmap, "✕", m.px(14.0), Weight::NORMAL, c.close.x + m.px(6.0), c.close.y + m.px(6.0), close_color);
        to_image(pixmap)
    }

    pub unsafe fn draw(&mut self, gl: &glow::Context, batch: &mut SpriteBatch, text: &mut Text, screen_w: f32) {
        use glow::HasContext;
        let now = Instant::now();
        for i in 0..self.cards.len() {
            if self.cards[i].dirty || self.cards[i].texture.is_none() {
                let img = self.render(text, &self.cards[i]);
                let c = &mut self.cards[i];
                if let Some(t) = c.texture.take() {
                    gl.delete_texture(t.id);
                }
                c.texture = Some(gfx::upload(gl, img.width, img.height, &img.data, false));
                c.dirty = false;
            }
            let c = &self.cards[i];
            let appear = ((now - c.born).as_secs_f32() / FADE).min(1.0);
            let vanish = c.closing.map_or(1.0, |t| 1.0 - ((now - t).as_secs_f32() / FADE).min(1.0));
            let tex = c.texture.unwrap();
            let x = self.origin_x(screen_w, c);
            batch.quad(gl, tex, &Affine::IDENTITY, x, c.y.round(), tex.width as f32, tex.height as f32,
                       [1.0, 1.0, 1.0], appear * vanish);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use homeview::office::ToastAction;

    /// `TOAST_PREVIEW=/путь/toast.png cargo test --release --bin homeview toast_preview -- --ignored`
    #[test]
    #[ignore]
    fn toast_preview() {
        let mut text = Text::new();
        let t = Toasts::new(1.73);
        let toast = Toast { icon: "☕".into(), title: "Жасур зовёт на чай".into(), body: "Небольшой перерыв?".into(),
            actions: vec![ToastAction { label: "Иду!".into(), kind: ActionKind::Compose { to: None }, primary: true },
                          ToastAction { label: "Позже".into(), kind: ActionKind::Compose { to: None }, primary: false }],
            auto_dismiss: Duration::from_secs(30), key: None };
        let mut card = t.layout(&mut text, toast);
        card.hot = Some(Hot::Button(1));
        let img = t.render(&mut text, &card);
        let mut out = image::RgbaImage::from_pixel(img.width + 40, img.height + 40, image::Rgba([60, 70, 80, 255]));
        for (i, px) in img.data.chunks(4).enumerate() {
            let (xx, yy) = (i as u32 % img.width + 20, i as u32 / img.width + 20);
            let a = px[3] as u32;
            let bg = out.get_pixel(xx, yy).0;
            let c = |k: usize| (px[k] as u32 + bg[k] as u32 * (255 - a) / 255).min(255) as u8;
            out.put_pixel(xx, yy, image::Rgba([c(0), c(1), c(2), 255]));
        }
        out.save(std::env::var("TOAST_PREVIEW").unwrap()).unwrap();
    }
}
