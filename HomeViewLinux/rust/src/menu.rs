//! Всплывающее меню, нарисованное в самом оверлее (вместо QMenu Python-версии).
//! Картинка меню готовится на CPU (tiny-skia + cosmic-text) и перерисовывается только при смене подсветки.

use cosmic_text::{Color, Weight};
use tiny_skia::{FillRule, Paint, Pixmap, Stroke, Transform};

use crate::gfx::{self, Image, Texture};
use crate::text::{rounded_rect, to_image, Text};

#[derive(Clone, Debug, PartialEq)]
pub enum Command {
    Wave(String),
    Throw(String),
    Compose(Option<String>),
    Tea(String),
    Hide(String),
    Show(String),
}

/// Ширина колонки значка, в размерах шрифта.
const ICON_COLUMN: f32 = 1.9;

/// «👋  Помахать» → ("👋", "Помахать"): значок отделён двумя пробелами.
fn split_icon(t: &str) -> Option<(&str, &str)> {
    t.split_once("  ").filter(|(icon, _)| icon.chars().count() <= 3)
}

pub enum Item {
    /// Заголовок или пояснение — серым, не нажимается.
    Info(String),
    Action(String, Command),
    Separator,
}

pub struct Menu {
    items: Vec<Item>,
    /// Левый верхний угол в координатах окна.
    pub x: f32,
    pub y: f32,
    pub w: f32,
    pub h: f32,
    rows: Vec<(f32, f32)>, // верх и высота каждой строки внутри меню
    px: f32,
    pad: f32,
    hover: Option<usize>,
    texture: Option<Texture>,
}

impl Menu {
    /// `at` — где кликнули; меню не вылезает за край окна (`bounds`).
    pub fn new(text: &mut Text, items: Vec<Item>, at: (f32, f32), bounds: (f32, f32), scale: f32) -> Menu {
        let px = (14.0 * scale).round();
        let pad = (6.0 * scale).round();
        let row_h = (px * 1.9).round();
        let sep_h = (9.0 * scale).round();
        let mut width: f32 = 0.0;
        let mut rows = Vec::new();
        let mut y = pad;
        for item in &items {
            let h = match item {
                Item::Separator => sep_h,
                Item::Info(t) | Item::Action(t, _) => {
                    let w = match split_icon(t) {
                        Some((_, label)) => px * ICON_COLUMN + text.measure_line(label, px, Weight::NORMAL).0,
                        None => text.measure_line(t, px, Weight::NORMAL).0,
                    };
                    width = width.max(w);
                    row_h
                }
            };
            rows.push((y, h));
            y += h;
        }
        let w = (width + px * 2.4 + pad * 2.0).ceil();
        let h = (y + pad).ceil();
        // Как у обычных меню: вниз-вправо от курсора, а у края — в другую сторону
        let x = if at.0 + w > bounds.0 { (at.0 - w).max(0.0) } else { at.0 };
        let y = if at.1 + h > bounds.1 { (at.1 - h).max(0.0) } else { at.1 };
        Menu { items, x: x.round(), y: y.round(), w, h, rows, px, pad, hover: None, texture: None }
    }

    pub fn contains(&self, x: f32, y: f32) -> bool {
        x >= self.x && x < self.x + self.w && y >= self.y && y < self.y + self.h
    }

    fn row_at(&self, x: f32, y: f32) -> Option<usize> {
        if !self.contains(x, y) {
            return None;
        }
        let ly = y - self.y;
        self.rows.iter().position(|&(top, h)| ly >= top && ly < top + h)
            .filter(|&i| matches!(self.items[i], Item::Action(..)))
    }

    /// Курсор сдвинулся; true — подсветка поменялась (картинку надо перерисовать).
    pub fn hover(&mut self, x: f32, y: f32) -> bool {
        let row = self.row_at(x, y);
        if row != self.hover {
            self.hover = row;
            return true;
        }
        false
    }

    pub fn command_at(&self, x: f32, y: f32) -> Option<Command> {
        match self.row_at(x, y).map(|i| &self.items[i]) {
            Some(Item::Action(_, c)) => Some(c.clone()),
            _ => None,
        }
    }

    fn render(&self, text: &mut Text) -> Image {
        let mut pixmap = Pixmap::new(self.w as u32, self.h as u32).unwrap();
        let mut paint = Paint::default();
        paint.anti_alias = true;
        let outline = rounded_rect(0.5, 0.5, self.w - 1.0, self.h - 1.0, self.pad * 1.6, None);
        paint.set_color_rgba8(0x0F, 0x1B, 0x2D, 240);
        pixmap.fill_path(&outline, &paint, FillRule::Winding, Transform::identity(), None);
        paint.set_color_rgba8(255, 255, 255, 50);
        pixmap.stroke_path(&outline, &paint, &Stroke { width: 1.0, ..Stroke::default() }, Transform::identity(), None);
        for (i, (item, &(top, h))) in self.items.iter().zip(&self.rows).enumerate() {
            let text_y = top + (h - (self.px * 1.2).ceil()) / 2.0;
            let left = self.pad + self.px * 0.7;
            match item {
                Item::Separator => {
                    paint.set_color_rgba8(255, 255, 255, 40);
                    if let Some(r) = tiny_skia::Rect::from_xywh(self.pad * 2.0, top + h / 2.0, self.w - self.pad * 4.0, 1.0) {
                        pixmap.fill_rect(r, &paint, Transform::identity(), None);
                    }
                }
                Item::Info(t) | Item::Action(t, _) => {
                    let color = if let Item::Action(..) = item {
                        if self.hover == Some(i) {
                            let r = rounded_rect(self.pad, top, self.w - self.pad * 2.0, h, self.pad, None);
                            paint.set_color_rgba8(0x1E, 0x88, 0xE5, 220);
                            pixmap.fill_path(&r, &paint, FillRule::Winding, Transform::identity(), None);
                        }
                        Color::rgb(255, 255, 255)
                    } else {
                        Color::rgba(255, 255, 255, 150)
                    };
                    // «значок  текст»: значок и текст — в своих колонках, чтобы подписи стояли ровно
                    match split_icon(t) {
                        Some((icon, label)) => {
                            text.draw_line(&mut pixmap, icon, self.px, Weight::NORMAL, left, text_y, color);
                            text.draw_line(&mut pixmap, label, self.px, Weight::NORMAL, left + self.px * ICON_COLUMN, text_y, color);
                        }
                        None => text.draw_line(&mut pixmap, t, self.px, Weight::NORMAL, left, text_y, color),
                    }
                }
            }
        }
        to_image(pixmap)
    }

    /// Текстура меню (перерисовывается после смены подсветки).
    pub unsafe fn texture(&mut self, gl: &glow::Context, text: &mut Text, dirty: bool) -> Texture {
        if dirty || self.texture.is_none() {
            self.delete(gl);
            let img = self.render(text);
            self.texture = Some(gfx::upload(gl, img.width, img.height, &img.data, false));
        }
        self.texture.unwrap()
    }

    pub unsafe fn delete(&mut self, gl: &glow::Context) {
        use glow::HasContext;
        if let Some(t) = self.texture.take() {
            gl.delete_texture(t.id);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// `MENU_PREVIEW=/путь/menu.png cargo test --release --bin homeview menu_preview -- --ignored`
    #[test]
    #[ignore]
    fn menu_preview() {
        let mut text = Text::new();
        let items = vec![
            Item::Info("Жасур · iOS".into()), Item::Info("🔕 Занят".into()), Item::Separator,
            Item::Action("👋  Помахать".into(), Command::Wave("A".into())),
            Item::Action("🍂  Кинуть листяной шарик".into(), Command::Throw("A".into())),
            Item::Action("💬  Написать…".into(), Command::Compose(None)),
            Item::Action("☕  Позвать на чай".into(), Command::Tea("A".into())), Item::Separator,
            Item::Action("🙈  Убрать с моего экрана".into(), Command::Hide("A".into())),
        ];
        let mut menu = Menu::new(&mut text, items, (0.0, 0.0), (2000.0, 2000.0), 1.73);
        let (x, y) = (menu.x + 40.0, menu.y + menu.rows[4].0 + 5.0);
        menu.hover(x, y);
        let img = menu.render(&mut text);
        // премультиплицированную альфу — на тёмный фон, чтобы было видно как на экране
        let mut out = image::RgbaImage::new(img.width + 40, img.height + 40);
        for p in out.pixels_mut() { *p = image::Rgba([60, 70, 80, 255]); }
        for (i, px) in img.data.chunks(4).enumerate() {
            let (xx, yy) = (i as u32 % img.width + 20, i as u32 / img.width + 20);
            let a = px[3] as u32;
            let bg = out.get_pixel(xx, yy).0;
            let c = |k: usize| (px[k] as u32 + bg[k] as u32 * (255 - a) / 255).min(255) as u8;
            out.put_pixel(xx, yy, image::Rgba([c(0), c(1), c(2), 255]));
        }
        out.save(std::env::var("MENU_PREVIEW").unwrap()).unwrap();
    }
}
