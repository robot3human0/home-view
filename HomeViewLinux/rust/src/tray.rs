//! Значок в трее (аналог ❄-меню в строке меню macOS и tray.py) — через системную
//! libayatana-appindicator (крейт tray-icon: меню GTK, в панель его отдаёт libdbusmenu).
//!
//! Почему не своя реализация StatusNotifierItem (ksni): расширение панели Zorin (zorin-appindicator)
//! первые десятки секунд рисовало её меню кусками, хотя D-Bus-ответы были полными и мгновенными.
//! С libappindicator (как getlantern/systray в Go) и с Qt такого нет.
//!
//! GTK живёт в своём потоке со своим циклом событий. Главный цикл шлёт туда снимок `TrayState`,
//! только если тот изменился (каждая пересборка уходит в панель по D-Bus); выбор пункта приходит
//! обратно командой `TrayCommand`.

use std::sync::mpsc::{self, Sender};
use std::time::Duration;

use homeview::protocol::PeerStatus;
use tray_icon::menu::{CheckMenuItem, Menu, MenuEvent, MenuItem, PredefinedMenuItem, Submenu};
use tray_icon::{Icon, TrayIconBuilder};

use crate::menu::Command;

#[derive(Clone, Debug, PartialEq)]
pub enum TrayCommand {
    Peer(Command),
    /// Открыть меню коллеги у курсора (наше, в оверлее).
    PeerMenu(String),
    SetStatus(PeerStatus),
    Reconnect,
    /// auto | winter | spring | summer | autumn
    SetSeason(String),
    SetEffects(bool),
    ClearSnow,
    Settings,
    Quit,
}

pub struct Peer {
    pub id: String,
    pub label: String,
}

#[derive(Default)]
pub struct TrayState {
    pub status_line: String,
    pub failed: bool,
    pub connected: bool,
    /// Выбранный статус и тот, что видят коллеги (может быть «Отошёл» по бездействию).
    pub my_status: PeerStatus,
    pub effective_status: PeerStatus,
    pub peers: Vec<Peer>,
    pub season_setting: String,
    /// «🍂 Осень»
    pub season_title: String,
    /// «листья»
    pub particle_title: String,
    pub effects: bool,
    /// Значок: RGBA (без премультипликации), квадрат `icon_size`.
    pub icon: Vec<u8>,
    pub icon_size: u32,
    /// Какой эмодзи на значке (менять картинку, только когда он сменился).
    pub icon_key: String,
}

/// Всё, от чего зависит меню, — строкой: сравнить снимки дешевле, чем пересобирать меню в панели.
pub fn signature(s: &TrayState) -> String {
    let peers: Vec<String> = s.peers.iter().map(|p| format!("{}={}", p.id, p.label)).collect();
    format!("{}|{}|{}|{:?}|{:?}|{}|{}|{}|{}|{}|{}", s.status_line, s.failed, s.connected, s.my_status,
            s.effective_status, peers.join(";"), s.season_setting, s.season_title, s.particle_title, s.effects,
            s.icon_key)
}

const STATUSES: [(PeerStatus, &str, &str); 4] = [
    (PeerStatus::Active, "active", "🟢 Активен"),
    (PeerStatus::Away, "away", "☕ Отошёл"),
    (PeerStatus::Busy, "busy", "🔕 Занят"),
    (PeerStatus::Hidden, "hidden", "👻 Невидимка"),
];

const SEASONS: [(&str, &str); 5] = [
    ("auto", "Автоматически"),
    ("winter", "❄️ Зима"),
    ("spring", "🌸 Весна"),
    ("summer", "☀️ Лето"),
    ("autumn", "🍂 Осень"),
];

/// Пункт меню → команда (id пункта несёт всё нужное).
fn command_for(id: &str) -> Option<TrayCommand> {
    let (kind, arg) = id.split_once(':').unwrap_or((id, ""));
    Some(match kind {
        "status" => TrayCommand::SetStatus(STATUSES.iter().find(|(_, k, _)| *k == arg)?.0),
        "season" => TrayCommand::SetSeason(arg.into()),
        "effects" => TrayCommand::SetEffects(arg == "on"),
        "peer" => TrayCommand::PeerMenu(arg.into()),
        "broadcast" => TrayCommand::Peer(Command::Compose(None)),
        "reconnect" => TrayCommand::Reconnect,
        "clear" => TrayCommand::ClearSnow,
        "settings" => TrayCommand::Settings,
        "quit" => TrayCommand::Quit,
        _ => return None,
    })
}

fn build_menu(s: &TrayState) -> Menu {
    let menu = Menu::new();
    let add = |item: &dyn tray_icon::menu::IsMenuItem| {
        let _ = menu.append(item);
    };
    add(&MenuItem::new(&s.status_line, false, None));
    if s.failed {
        add(&MenuItem::with_id("reconnect", "🔄  Переподключиться", true, None));
    }
    add(&PredefinedMenuItem::separator());

    let current = STATUSES.iter().find(|(k, _, _)| *k == s.effective_status).map_or("", |(_, _, t)| t);
    let status = Submenu::new(format!("Мой статус: {current}"), true);
    for (value, key, title) in STATUSES {
        let _ = status.append(&CheckMenuItem::with_id(format!("status:{key}"), title, true, s.my_status == value, None));
    }
    add(&status);

    let people = Submenu::new(format!("👥  Коллеги ({})", s.peers.len()), true);
    if s.peers.is_empty() {
        let _ = people.append(&MenuItem::new("Сейчас никого нет в сети", false, None));
    }
    for p in &s.peers {
        let _ = people.append(&MenuItem::with_id(format!("peer:{}", p.id), &p.label, true, None));
    }
    add(&people);
    add(&MenuItem::with_id("broadcast", "📣  Написать всем…", s.connected, None));
    add(&PredefinedMenuItem::separator());

    let season = Submenu::new(format!("Сезон: {}", s.season_title), true);
    for (key, title) in SEASONS {
        let _ = season.append(&CheckMenuItem::with_id(format!("season:{key}"), title, true, s.season_setting == key, None));
    }
    add(&season);
    // id несёт новое значение: пункт переключает осадки
    let effects_id = if s.effects { "effects:off" } else { "effects:on" };
    add(&CheckMenuItem::with_id(effects_id, format!("Осадки ({})", s.particle_title), true, s.effects, None));
    add(&MenuItem::with_id("clear", "🧹  Убрать снег", true, None));
    add(&PredefinedMenuItem::separator());
    add(&MenuItem::with_id("settings", "⚙  Настройки…", true, None));
    add(&MenuItem::with_id("quit", "Выход", true, None));
    menu
}

/// Поток трея; `update` отправляет новый снимок (берётся последний из накопившихся).
pub struct TrayHandle {
    states: Sender<TrayState>,
}

impl TrayHandle {
    pub fn spawn(initial: TrayState, commands: Sender<TrayCommand>, wake: Box<dyn Fn() + Send + Sync>)
        -> Result<TrayHandle, String> {
        MenuEvent::set_event_handler(Some(move |e: MenuEvent| {
            if let Some(c) = command_for(&e.id.0) {
                let _ = commands.send(c);
                wake();
            }
        }));
        let (tx, rx) = mpsc::channel::<TrayState>();
        let (ready_tx, ready_rx) = mpsc::channel::<Result<(), String>>();
        std::thread::Builder::new().name("homeview-tray".into()).spawn(move || {
            if let Err(e) = gtk::init() {
                let _ = ready_tx.send(Err(format!("GTK: {e}")));
                return;
            }
            let icon = |s: &TrayState| Icon::from_rgba(s.icon.clone(), s.icon_size, s.icon_size).ok();
            let built = TrayIconBuilder::new()
                .with_id("homeview-linux")
                .with_menu(Box::new(build_menu(&initial)))
                .with_icon(icon(&initial).unwrap_or_else(|| Icon::from_rgba(vec![0; 4], 1, 1).unwrap()))
                .build();
            let tray = match built {
                Ok(t) => t,
                Err(e) => {
                    let _ = ready_tx.send(Err(e.to_string()));
                    return;
                }
            };
            let _ = ready_tx.send(Ok(()));
            let mut icon_key = initial.icon_key.clone();
            gtk::glib::timeout_add_local(Duration::from_millis(100), move || {
                if let Some(s) = rx.try_iter().last() {
                    tray.set_menu(Some(Box::new(build_menu(&s))));
                    if s.icon_key != icon_key {
                        icon_key = s.icon_key.clone();
                        let _ = tray.set_icon(icon(&s));
                    }
                }
                gtk::glib::ControlFlow::Continue
            });
            gtk::main();
        }).map_err(|e| e.to_string())?;
        ready_rx.recv_timeout(Duration::from_secs(5)).map_err(|e| e.to_string())??;
        Ok(TrayHandle { states: tx })
    }

    pub fn update(&self, state: TrayState) {
        let _ = self.states.send(state);
    }
}

/// Эмодзи → значок RGBA (без премультипликации).
pub fn emoji_icon(text: &mut crate::text::Text, emoji: &str, size: u32) -> Vec<u8> {
    let mut pixmap = tiny_skia::Pixmap::new(size, size).unwrap();
    let px = (size as f32 * 0.8).round();
    let (w, h) = text.measure_line(emoji, px, cosmic_text::Weight::NORMAL);
    text.draw_line(&mut pixmap, emoji, px, cosmic_text::Weight::NORMAL, (size as f32 - w) / 2.0,
                   (size as f32 - h) / 2.0, cosmic_text::Color::rgb(255, 255, 255));
    pixmap.pixels().iter().flat_map(|p| {
        let c = p.demultiply();
        [c.red(), c.green(), c.blue(), c.alpha()]
    }).collect()
}
