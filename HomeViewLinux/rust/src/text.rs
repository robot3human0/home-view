//! Таблички и облачка: текст (cosmic-text, системные шрифты, эмодзи) + фигуры (tiny-skia).
//! Рисуются один раз при смене текста в картинку — как render_pill/render_bubble в avatar.py.

use cosmic_text::{Align, Attrs, Buffer, Color, Family, FontSystem, Metrics, Shaping, SwashCache, Weight};
use tiny_skia::{FillRule, Paint, PathBuilder, Pixmap, Rect, Stroke, Transform};

use crate::gfx::Image;

pub const TAG_FONT_PX: f32 = 11.0;
pub const BUBBLE_FONT_PX: f32 = 12.0;
pub const BUBBLE_MAX_WIDTH: f32 = 220.0;

pub struct Text {
    fonts: FontSystem,
    cache: SwashCache,
    family: String,
    emoji_family: String,
}

impl Text {
    pub fn new() -> Text {
        let started = std::time::Instant::now();
        let mut fonts = FontSystem::new();
        // Тот же шрифт, что выбирает Qt: системный sans-serif по fontconfig
        let family = std::process::Command::new("fc-match").args(["-f", "%{family[0]}", "sans-serif"]).output()
            .ok().and_then(|o| String::from_utf8(o.stdout).ok()).filter(|s| !s.is_empty())
            .unwrap_or_else(|| "DejaVu Sans".into());
        fonts.db_mut().set_sans_serif_family(family.clone());
        let emoji_family = std::process::Command::new("fc-match").args(["-f", "%{family[0]}", "emoji"]).output()
            .ok().and_then(|o| String::from_utf8(o.stdout).ok()).filter(|s| !s.is_empty())
            .unwrap_or_else(|| "Noto Color Emoji".into());
        eprintln!("Шрифты: {} начертаний, sans-serif = {family}, эмодзи = {emoji_family}, загрузка {:.0} мс",
                  fonts.db().faces().count(), started.elapsed().as_secs_f32() * 1000.0);
        Text { fonts, cache: SwashCache::new(), family, emoji_family }
    }

    fn layout(&mut self, text: &str, px: f32, weight: Weight, wrap: Option<f32>) -> (Buffer, f32, f32) {
        let text = &emoji_presentation(text);
        let metrics = Metrics::new(px, (px * 1.2).ceil());
        let mut buffer = Buffer::new(&mut self.fonts, metrics);
        buffer.set_size(&mut self.fonts, wrap, None);
        let attrs = Attrs::new().family(Family::Name(&self.family)).weight(weight);
        // Эмодзи — явно шрифтом эмодзи: иначе ☕ ❄ ☀ берутся из обычного шрифта (мелкие и одноцветные)
        let emoji = Attrs::new().family(Family::Name(&self.emoji_family)).weight(weight);
        let spans = split_emoji(text).into_iter().map(|(t, e)| (t, if e { emoji } else { attrs }));
        buffer.set_rich_text(&mut self.fonts, spans, attrs, Shaping::Advanced);
        if wrap.is_some() {
            for line in buffer.lines.iter_mut() {
                line.set_align(Some(Align::Center));
            }
        }
        buffer.shape_until_scroll(&mut self.fonts, false);
        let mut width: f32 = 0.0;
        let mut lines = 0;
        for run in buffer.layout_runs() {
            width = width.max(run.line_w);
            lines += 1;
        }
        let height = lines.max(1) as f32 * metrics.line_height;
        (buffer, width, height)
    }

    fn draw_text(&mut self, pixmap: &mut Pixmap, buffer: &mut Buffer, dx: f32, dy: f32, color: Color) {
        let mut paint = Paint::default();
        buffer.draw(&mut self.fonts, &mut self.cache, color, |x, y, w, h, c| {
            if c.a() == 0 {
                return;
            }
            paint.set_color_rgba8(c.r(), c.g(), c.b(), c.a());
            if let Some(rect) = Rect::from_xywh(x as f32 + dx, y as f32 + dy, w as f32, h as f32) {
                pixmap.fill_rect(rect, &paint, Transform::identity(), None);
            }
        });
    }

    /// Ширина и высота строки (без переноса).
    pub fn measure_line(&mut self, text: &str, px: f32, weight: Weight) -> (f32, f32) {
        let (_, w, h) = self.layout(text, px, weight, None);
        (w, h)
    }

    /// Нарисовать строку в картинку: (x, y) — левый верхний угол строки.
    pub fn draw_line(&mut self, pixmap: &mut Pixmap, text: &str, px: f32, weight: Weight, x: f32, y: f32, color: Color) {
        let (mut buffer, _, _) = self.layout(text, px, weight, None);
        self.draw_text(pixmap, &mut buffer, x.round(), y.round(), color);
    }

    /// Табличка-«пилюля» «Имя · Команда».
    pub fn pill(&mut self, text: &str, background: [u8; 4], scale: f32) -> Image {
        let (mut buffer, text_w, line_h) = self.layout(text, TAG_FONT_PX * scale, Weight::SEMIBOLD, None);
        let width = (text_w + 14.0 * scale).ceil();
        let height = (17.0 * scale).ceil();
        let mut pixmap = Pixmap::new(width as u32, height as u32).unwrap();
        let path = rounded_rect(0.5, 0.5, width - 1.0, height - 1.0, height / 2.0, None);
        let mut paint = Paint::default();
        paint.anti_alias = true;
        paint.set_color_rgba8(background[0], background[1], background[2], background[3]);
        pixmap.fill_path(&path, &paint, FillRule::Winding, Transform::identity(), None);
        paint.set_color_rgba8(255, 255, 255, 64);
        pixmap.stroke_path(&path, &paint, &Stroke { width: 0.8 * scale, ..Stroke::default() }, Transform::identity(), None);
        self.draw_text(&mut pixmap, &mut buffer, ((width - text_w) / 2.0).round(), ((height - line_h) / 2.0).round(),
                       Color::rgb(255, 255, 255));
        to_image(pixmap)
    }

    /// Облачко с репликой и хвостиком вниз.
    pub fn bubble(&mut self, text: &str, scale: f32) -> Image {
        let max_w = BUBBLE_MAX_WIDTH * scale;
        let (mut buffer, text_w, text_h) = self.layout(text, BUBBLE_FONT_PX * scale, Weight::MEDIUM, Some(max_w));
        let (pad_x, pad_y, tail) = (10.0 * scale, 6.0 * scale, 7.0 * scale);
        let width = (text_w + pad_x * 2.0).ceil();
        let height = (text_h + pad_y * 2.0).ceil();
        let mut pixmap = Pixmap::new((width + 2.0) as u32, (height + tail + 2.0) as u32).unwrap();
        let path = rounded_rect(1.0, 1.0, width, height, 9.0 * scale, Some((6.0 * scale, tail)));
        let mut paint = Paint::default();
        paint.anti_alias = true;
        paint.set_color_rgba8(255, 255, 255, 245);
        pixmap.fill_path(&path, &paint, FillRule::Winding, Transform::identity(), None);
        paint.set_color_rgba8(15, 27, 45, 70);
        pixmap.stroke_path(&path, &paint, &Stroke { width: 1.0, ..Stroke::default() }, Transform::identity(), None);
        // строки выровнены по центру внутри max_w — сдвигаем к центру облачка
        let dx = 1.0 + (width - max_w) / 2.0;
        self.draw_text(&mut pixmap, &mut buffer, dx.round(), (1.0 + pad_y).round(), Color::rgb(0x1A, 0x23, 0x33));
        to_image(pixmap)
    }
}

fn is_emoji(c: char) -> bool {
    matches!(c, '\u{1F000}'..='\u{1FAFF}' | '\u{2600}'..='\u{27BF}' | '\u{2B00}'..='\u{2BFF}' | '\u{FE0F}' | '\u{200D}'
             | '\u{2190}'..='\u{21FF}' | 'ℹ' | '\u{E0020}'..='\u{E007F}')
}

/// Текст → куски (кусок, это эмодзи?).
fn split_emoji(text: &str) -> Vec<(&str, bool)> {
    let mut out = Vec::new();
    let mut start = 0;
    let mut current: Option<bool> = None;
    for (i, c) in text.char_indices() {
        let e = is_emoji(c);
        if current.is_some_and(|k| k != e) {
            out.push((&text[start..i], current.unwrap()));
            start = i;
        }
        current = Some(e);
    }
    if let Some(k) = current {
        out.push((&text[start..], k));
    }
    out
}

/// Символы, которые шрифты по умолчанию рисуют как текст (мелко, одним цветом), — просим цветной эмодзи (U+FE0F).
fn emoji_presentation(text: &str) -> std::borrow::Cow<'_, str> {
    const TEXT_DEFAULT: [char; 6] = ['☕', '☀', '❄', '♟', '⚠', 'ℹ'];
    if !text.chars().any(|c| TEXT_DEFAULT.contains(&c)) {
        return text.into();
    }
    let mut out = String::with_capacity(text.len() + 8);
    let mut chars = text.chars().peekable();
    while let Some(c) = chars.next() {
        out.push(c);
        if TEXT_DEFAULT.contains(&c) && chars.peek() != Some(&'\u{FE0F}') {
            out.push('\u{FE0F}');
        }
    }
    out.into()
}

pub fn to_image(pixmap: Pixmap) -> Image {
    Image { width: pixmap.width(), height: pixmap.height(), data: pixmap.take() }
}

/// Скруглённый прямоугольник; `tail` = (полуширина, длина) — хвостик посередине нижней стороны.
pub fn rounded_rect(x: f32, y: f32, w: f32, h: f32, r: f32, tail: Option<(f32, f32)>) -> tiny_skia::Path {
    let r = r.min(w / 2.0).min(h / 2.0);
    let k = 0.552_284_8 * r;
    let (x1, y1) = (x + w, y + h);
    let mut p = PathBuilder::new();
    p.move_to(x + r, y);
    p.line_to(x1 - r, y);
    p.cubic_to(x1 - r + k, y, x1, y + r - k, x1, y + r);
    p.line_to(x1, y1 - r);
    p.cubic_to(x1, y1 - r + k, x1 - r + k, y1, x1 - r, y1);
    if let Some((half, len)) = tail {
        let cx = x + w / 2.0;
        p.line_to(cx + half, y1);
        p.line_to(cx, y1 + len);
        p.line_to(cx - half, y1);
    }
    p.line_to(x + r, y1);
    p.cubic_to(x + r - k, y1, x, y1 - r + k, x, y1 - r);
    p.line_to(x, y + r);
    p.cubic_to(x, y + r - k, x + r - k, y, x + r, y);
    p.close();
    p.finish().unwrap()
}
