//! Офис: коллеги, статусы, сообщения сервера и действия (аналог Office.swift / homeview/office.py).
//!
//! Без окон: наружу — события `OfficeEvent` (что показать), внутрь — действия пользователя.
//! Сетевые события приходят из потока `NetworkClient` через канал и разбираются в `poll()`.

use std::collections::BTreeMap;
use std::sync::mpsc::{self, Receiver};
use std::sync::Arc;
use std::time::{Duration, Instant};

use crate::net::{NetEvent, NetState, NetworkClient};
use crate::protocol::*;
use crate::settings::Settings;

pub const AWAY_AFTER: Duration = Duration::from_secs(300);
/// Сервер всё равно не пропускает снаряды чаще раза в 1.2 с.
const PROJECTILE_COOLDOWN: Duration = Duration::from_millis(1300);

pub const TEA_TEXT: &str = "☕ Пойдём на чай?";
pub const TEA_YES: &str = "Иду! ☕";
pub const TEA_LATER: &str = "Сейчас занят, давай позже";
pub const WAVE_TEXT: &str = "👋 Привет!";

#[derive(Clone, Debug, PartialEq)]
pub enum Connection {
    Off,
    NotConfigured,
    Searching,
    Connecting,
    Connected(String),
    Failed(String),
}

#[derive(Clone, Debug, PartialEq)]
pub enum ActionKind {
    Chat { to: String, text: String },
    Respond { room_id: String, accept: bool },
    /// Открыть окно «написать сообщение».
    Compose { to: Option<String> },
    ShowPeer { id: String },
}

#[derive(Clone, Debug, PartialEq)]
pub struct ToastAction {
    pub label: String,
    pub kind: ActionKind,
    pub primary: bool,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Toast {
    pub icon: String,
    pub title: String,
    pub body: String,
    pub actions: Vec<ToastAction>,
    pub auto_dismiss: Duration,
    /// Новое уведомление с тем же ключом заменяет старое.
    pub key: Option<String>,
}

impl Toast {
    fn new(icon: &str, title: impl Into<String>, body: impl Into<String>, seconds: u64) -> Toast {
        Toast { icon: icon.into(), title: title.into(), body: body.into(), actions: Vec::new(),
                auto_dismiss: Duration::from_secs(seconds), key: None }
    }
    fn key(mut self, key: impl Into<String>) -> Toast {
        self.key = Some(key.into());
        self
    }
    fn action(mut self, label: &str, kind: ActionKind, primary: bool) -> Toast {
        self.actions.push(ToastAction { label: label.into(), kind, primary });
        self
    }
}

#[derive(Clone, Debug, PartialEq)]
pub enum OfficeEvent {
    PeersChanged,
    ConnectionChanged,
    Toast(Toast),
    DismissToast(String),
    /// Анимации человечков в мире
    PeerWaves(String),
    PeerSays { id: String, text: String },
    /// Мы что-то сделали этому коллеге — его человечек подпрыгивает
    PeerHops(String),
    /// Коллега кинул снаряд в нас
    IncomingProjectile(String),
}

/// Сервер пишет по-узбекски — переводим то, что знаем.
pub fn translate_server_text(text: &str) -> String {
    match text {
        "Ofis kodi noto‘g‘ri" => return "Неверный код офиса".into(),
        "Ism kiritilmagan" => return "Не указано имя".into(),
        "Bu hamkasb hozir tarmoqda emas" => return "Этого коллеги сейчас нет в сети".into(),
        _ => {}
    }
    if text.starts_with("Ilovangiz eski") {
        return "Сервер требует более новую версию протокола — обнови Linux-клиент".into();
    }
    if let Some(rest) = text.strip_suffix(" keyinroq") {
        if let Some((name, _)) = rest.split_once(" hozir band — ") {
            return format!("{name} сейчас занят(а) — попробуй позже");
        }
    }
    text.into()
}

pub fn status_title(status: PeerStatus) -> &'static str {
    match status {
        PeerStatus::Active => "🟢 Активен",
        PeerStatus::Away => "☕ Отошёл",
        PeerStatus::Busy => "🔕 Занят",
        PeerStatus::Hidden => "👻 Невидимка",
    }
}

struct Running {
    client: NetworkClient,
    events: Receiver<NetEvent>,
    address: String,
    code: String,
    name: String,
}

pub struct Office {
    pub settings: Settings,
    pub peers: BTreeMap<String, PeerInfo>,
    pub rooms: BTreeMap<String, RoomInfo>,
    pub connection: Connection,
    pub auto_away: bool,
    running: Option<Running>,
    server_label: String,
    last_profile: Option<(String, String, AvatarStyle)>,
    last_status: PeerStatus,
    last_projectile: Option<Instant>,
    out: Vec<OfficeEvent>,
    /// Будит главный цикл, когда из сети пришло событие.
    waker: Arc<dyn Fn() + Send + Sync>,
    /// Для тестов: отправленные сообщения (вместо сети).
    #[cfg(test)]
    sent: Vec<ClientMessage>,
}

impl Office {
    pub fn new(settings: Settings, waker: Arc<dyn Fn() + Send + Sync>) -> Office {
        Office {
            settings, peers: BTreeMap::new(), rooms: BTreeMap::new(), connection: Connection::Off, auto_away: false,
            running: None, server_label: String::new(), last_profile: None, last_status: PeerStatus::Active,
            last_projectile: None, out: Vec::new(), waker,
            #[cfg(test)]
            sent: Vec::new(),
        }
    }

    pub fn my_id(&self) -> &str {
        &self.settings.peer_id
    }

    pub fn effective_status(&self) -> PeerStatus {
        match self.settings.my_status {
            PeerStatus::Active if self.auto_away => PeerStatus::Away,
            s => s,
        }
    }

    /// Кого рисовать на экране.
    pub fn visible_peers(&self) -> Vec<&PeerInfo> {
        self.peers.values()
            .filter(|p| p.id != self.settings.peer_id && p.status != PeerStatus::Hidden
                    && !self.settings.hidden_peers.contains(&p.id))
            .collect()
    }

    /// Кто в сети (для меню), по имени.
    pub fn online_peers(&self) -> Vec<&PeerInfo> {
        let mut list: Vec<_> = self.peers.values().filter(|p| p.id != self.settings.peer_id).collect();
        list.sort_by_key(|p| p.name.to_lowercase());
        list
    }

    pub fn name(&self, id: &str) -> String {
        self.peers.get(id).map(|p| p.name.clone()).unwrap_or_else(|| "Коллега".into())
    }

    pub fn status_line(&self) -> String {
        match &self.connection {
            Connection::Connected(_) => format!("● В офисе · коллег в сети: {}", self.online_peers().len()),
            Connection::Off => "○ Офис выключен".into(),
            Connection::NotConfigured => "○ Укажи имя в настройках".into(),
            Connection::Searching => "◌ Ищем офисный сервер…".into(),
            Connection::Connecting => "◌ Подключаемся…".into(),
            Connection::Failed(d) if !d.is_empty() => format!("⚠ {d}"),
            Connection::Failed(_) => "⚠ Нет связи с офисом".into(),
        }
    }

    /// Флажок над человечком: лобби, которое он собирает, или «играет».
    pub fn game_label(&self, peer_id: &str) -> Option<String> {
        self.rooms.values().find_map(|r| {
            let (emoji, title) = r.game.title();
            if r.host_id == peer_id && r.phase == RoomPhase::Lobby {
                Some(format!("{emoji} {title} {}/{}", r.players.len(), r.game.max_players()))
            } else if r.phase == RoomPhase::Playing && r.players.iter().any(|p| p == peer_id) {
                Some(format!("{emoji} играет"))
            } else {
                None
            }
        })
    }

    pub fn take_events(&mut self) -> Vec<OfficeEvent> {
        std::mem::take(&mut self.out)
    }

    fn emit(&mut self, e: OfficeEvent) {
        self.out.push(e);
    }

    fn send(&mut self, m: ClientMessage) {
        #[cfg(test)]
        self.sent.push(m.clone());
        if let Some(r) = &self.running {
            r.client.send(&m);
        }
    }

    // MARK: - Настройки → соединение

    pub fn apply_settings(&mut self, settings: Settings) {
        self.settings = settings;
        let enabled = self.settings.office_enabled;
        if !enabled || self.settings.display_name.trim().is_empty() {
            self.stop();
            self.set_connection(if enabled { Connection::NotConfigured } else { Connection::Off });
            return;
        }
        let s = &self.settings;
        let restart = match &self.running {
            None => true,
            Some(r) => r.address != s.server_address || r.code != s.office_code || r.name != s.display_name,
        };
        if restart {
            self.start();
            return;
        }
        let profile = (s.display_name.clone(), s.team.clone(), s.avatar);
        if self.last_profile.as_ref() != Some(&profile) {
            self.last_profile = Some(profile.clone());
            self.send(ClientMessage::Profile { name: profile.0, team: profile.1, avatar: profile.2 });
        }
        self.send_status_if_changed();
        self.emit(OfficeEvent::PeersChanged);
    }

    fn start(&mut self) {
        self.stop();
        let s = self.settings.clone();
        let status = self.effective_status();
        self.last_status = status;
        self.last_profile = Some((s.display_name.clone(), s.team.clone(), s.avatar));
        let (tx, rx) = mpsc::channel();
        let waker = self.waker.clone();
        // hello собирается при каждом подключении из настроек на момент старта;
        // статус после переподключения досылаем отдельно (send_status_if_changed).
        let hello = ClientMessage::hello(&s.peer_id, s.display_name.trim(), s.team.trim(), s.avatar, status, &s.office_code);
        let client = NetworkClient::start(&s.server_address, move || hello.clone(), move |e| {
            let _ = tx.send(e);
            waker();
        });
        self.running = Some(Running { client, events: rx, address: s.server_address.clone(), code: s.office_code.clone(),
                                      name: s.display_name.clone() });
        self.set_connection(if s.server_address.is_empty() { Connection::Searching } else { Connection::Connecting });
    }

    fn stop(&mut self) {
        if self.running.take().is_some() {
            self.clear();
        }
    }

    pub fn reconnect(&mut self) {
        if let Some(r) = &self.running {
            r.client.retry_now();
        }
    }

    fn set_connection(&mut self, c: Connection) {
        if self.connection != c {
            self.connection = c;
            self.emit(OfficeEvent::ConnectionChanged);
        }
    }

    fn clear(&mut self) {
        if !self.peers.is_empty() || !self.rooms.is_empty() {
            self.peers.clear();
            self.rooms.clear();
            self.emit(OfficeEvent::PeersChanged);
        }
    }

    fn send_status_if_changed(&mut self) {
        let status = self.effective_status();
        if status != self.last_status {
            self.last_status = status;
            self.send(ClientMessage::Status { status });
            self.emit(OfficeEvent::ConnectionChanged);
        }
    }

    /// Раз в ~15 с: сколько пользователь ничего не трогал (XScreenSaver), None — неизвестно.
    pub fn set_idle(&mut self, idle: Option<Duration>) {
        if self.running.is_none() || !self.settings.auto_away {
            if self.auto_away {
                self.auto_away = false;
                self.send_status_if_changed();
            }
            return;
        }
        let Some(idle) = idle else { return };
        self.auto_away = idle > AWAY_AFTER;
        self.send_status_if_changed();
    }

    // MARK: - Сеть

    /// Разобрать накопившиеся сетевые события; затем забрать `take_events()`.
    pub fn poll(&mut self) {
        let Some(r) = &self.running else { return };
        let events: Vec<NetEvent> = r.events.try_iter().collect();
        for e in events {
            match e {
                NetEvent::State(s) => self.on_net_state(s),
                NetEvent::Message(m) => self.handle(m),
            }
        }
    }

    fn on_net_state(&mut self, s: NetState) {
        match s {
            NetState::Searching => self.set_connection(Connection::Searching),
            NetState::Connecting(_) => self.set_connection(Connection::Connecting),
            // «В офисе» — только после welcome; до него сервер может и отказать
            NetState::Connected(label) => self.server_label = label,
            NetState::Failed(detail) => {
                self.set_connection(Connection::Failed(detail));
                self.clear();
                // после переподключения hello уйдёт с текущим статусом
                self.last_status = self.effective_status();
            }
        }
    }

    pub fn handle(&mut self, message: ServerMessage) {
        match message {
            ServerMessage::Welcome { peers, rooms, .. } => {
                let me = self.settings.peer_id.clone();
                self.peers = peers.into_iter().filter(|p| p.id != me).map(|p| (p.id.clone(), p)).collect();
                self.rooms = rooms.into_iter().map(|r| (r.id.clone(), r)).collect();
                log::info!("Сервер принял: в сети {}, комнат {}", self.peers.len(), self.rooms.len());
                self.set_connection(Connection::Connected(self.server_label.clone()));
                self.emit(OfficeEvent::PeersChanged);
                let n = self.peers.len();
                self.emit(OfficeEvent::Toast(Toast::new("👋", "Ты в офисе", format!("Сейчас в сети: {n}"), 4).key("welcome")));
                self.send_status_if_changed();
            }
            ServerMessage::Rejected { reason } => {
                let text = translate_server_text(&reason);
                log::warn!("Сервер отказал: {text} ({reason})");
                self.set_connection(Connection::Failed(text.clone()));
                self.emit(OfficeEvent::Toast(Toast::new("⚠️", "Не удалось подключиться к офису", text, 10).key("rejected")));
            }
            ServerMessage::Notice { text } => {
                self.emit(OfficeEvent::Toast(Toast::new("ℹ️", translate_server_text(&text), "", 4)));
            }
            ServerMessage::PeerJoined { peer } | ServerMessage::PeerUpdated { peer } => {
                if peer.id != self.settings.peer_id {
                    self.peers.insert(peer.id.clone(), peer);
                    self.emit(OfficeEvent::PeersChanged);
                }
            }
            ServerMessage::PeerLeft { id } => {
                if self.peers.remove(&id).is_some() {
                    self.emit(OfficeEvent::PeersChanged);
                }
            }
            ServerMessage::Ping { from, kind: PingKind::Tea } => {
                self.emit(OfficeEvent::PeerSays { id: from.clone(), text: TEA_TEXT.into() });
                let name = self.name(&from);
                self.emit(OfficeEvent::Toast(
                    Toast::new("☕", format!("{name} зовёт на чай"), "Небольшой перерыв?", 30)
                        .action("Иду!", ActionKind::Chat { to: from.clone(), text: TEA_YES.into() }, true)
                        .action("Позже", ActionKind::Chat { to: from, text: TEA_LATER.into() }, false)));
            }
            ServerMessage::Ping { from, kind: PingKind::Wave } => self.emit(OfficeEvent::PeerWaves(from)),
            ServerMessage::Projectile { from } => self.emit(OfficeEvent::IncomingProjectile(from)),
            ServerMessage::Chat { from, text, direct } => {
                self.emit(OfficeEvent::PeerSays { id: from.clone(), text: text.clone() });
                let title = if direct { self.name(&from) } else { format!("{} (всем)", self.name(&from)) };
                self.emit(OfficeEvent::Toast(Toast::new(if direct { "💬" } else { "📣" }, title, text, 12)
                    .action("Ответить", ActionKind::Compose { to: Some(from) }, false)));
            }
            ServerMessage::Invited { room_id, from, game } => {
                let (emoji, title) = game.title();
                let name = self.name(&from);
                self.emit(OfficeEvent::Toast(
                    Toast::new(emoji, format!("{name} зовёт в «{title}»"), "Игры в Linux-версии пока не поддерживаются 🙏", 30)
                        .action("Отказаться", ActionKind::Respond { room_id: room_id.clone(), accept: false }, false)
                        .key(format!("invite-{room_id}"))));
            }
            ServerMessage::Declined { by, .. } => {
                let name = self.name(&by);
                self.emit(OfficeEvent::Toast(Toast::new("🙅", format!("{name} сейчас не может играть"), "", 5)));
            }
            ServerMessage::Room { room } => {
                self.rooms.insert(room.id.clone(), room);
                self.emit(OfficeEvent::PeersChanged);
            }
            ServerMessage::RoomClosed { room_id } => {
                if self.rooms.remove(&room_id).is_some() {
                    self.emit(OfficeEvent::PeersChanged);
                }
                self.emit(OfficeEvent::DismissToast(format!("invite-{room_id}")));
            }
            // Обновления Mac-приложения, шахматы и игры — пока не поддерживаем
            ServerMessage::LatestApp { .. } | ServerMessage::Chess { .. } | ServerMessage::ChessLive { .. }
            | ServerMessage::Game { .. } => {}
        }
    }

    // MARK: - Действия пользователя

    pub fn wave(&mut self, id: &str) {
        self.send(ClientMessage::Ping { to: id.into(), kind: PingKind::Wave });
        self.emit(OfficeEvent::PeerHops(id.into()));
    }

    pub fn tea(&mut self, id: &str) {
        self.send(ClientMessage::Ping { to: id.into(), kind: PingKind::Tea });
        let name = self.name(id);
        self.emit(OfficeEvent::Toast(Toast::new("☕", "Приглашение отправлено", format!("Ждём ответа от {name}"), 4)));
    }

    /// Можно ли кинуть сейчас; после анимации полёта вызвать `projectile_hit`.
    pub fn can_throw(&mut self) -> bool {
        let now = Instant::now();
        if self.last_projectile.is_some_and(|t| now - t < PROJECTILE_COOLDOWN) {
            return false;
        }
        self.last_projectile = Some(now);
        true
    }

    pub fn projectile_hit(&mut self, id: &str) {
        self.send(ClientMessage::Projectile { to: id.into() });
    }

    pub fn chat(&mut self, to: Option<&str>, text: &str) {
        let clean = text.trim();
        if !clean.is_empty() {
            self.send(ClientMessage::chat(to, clean));
            if let Some(id) = to {
                self.emit(OfficeEvent::PeerHops(id.into()));
            }
        }
    }

    pub fn perform(&mut self, action: &ActionKind) {
        match action {
            ActionKind::Chat { to, text } => self.chat(Some(to), text),
            ActionKind::Respond { room_id, accept } => self.send(ClientMessage::Respond { room_id: room_id.clone(), accept: *accept }),
            ActionKind::Compose { .. } | ActionKind::ShowPeer { .. } => {} // это делает интерфейс
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn office() -> Office {
        let ini = crate::settings::Ini::parse("[General]\npeerID=ME\ndisplayName=Я\n");
        Office::new(Settings::from_ini(&ini), Arc::new(|| {}))
    }

    fn peer(id: &str, status: PeerStatus) -> PeerInfo {
        PeerInfo { id: id.into(), name: format!("Имя-{id}"), team: "T".into(), avatar: AvatarStyle::STANDARD, status }
    }

    #[test]
    fn welcome_and_peers() {
        let mut o = office();
        o.handle(ServerMessage::Welcome { you: "ME".into(), peers: vec![peer("ME", PeerStatus::Active),
            peer("A", PeerStatus::Active), peer("H", PeerStatus::Hidden)], rooms: vec![] });
        assert_eq!(o.peers.len(), 2, "себя не показываем");
        assert_eq!(o.visible_peers().len(), 1, "невидимку не рисуем");
        assert!(matches!(o.connection, Connection::Connected(_)));
        o.handle(ServerMessage::PeerLeft { id: "A".into() });
        assert!(o.visible_peers().is_empty());
        assert!(o.take_events().contains(&OfficeEvent::PeersChanged));
    }

    #[test]
    fn rejected_is_translated() {
        let mut o = office();
        o.handle(ServerMessage::Rejected { reason: "Ofis kodi noto‘g‘ri".into() });
        assert_eq!(o.connection, Connection::Failed("Неверный код офиса".into()));
        assert_eq!(translate_server_text("Жасур hozir band — 5 daqiqadan keyinroq"), "Жасур сейчас занят(а) — попробуй позже");
    }

    #[test]
    fn tea_invitation_and_answer() {
        let mut o = office();
        o.handle(ServerMessage::Ping { from: "A".into(), kind: PingKind::Tea });
        let toast = o.take_events().into_iter().find_map(|e| if let OfficeEvent::Toast(t) = e { Some(t) } else { None }).unwrap();
        o.perform(&toast.actions[0].kind);
        assert_eq!(o.sent, vec![ClientMessage::chat(Some("A"), TEA_YES)]);
    }

    #[test]
    fn auto_away_only_when_running() {
        let mut o = office();
        o.set_idle(Some(Duration::from_secs(600)));
        assert!(!o.auto_away, "офис не запущен");
        assert_eq!(o.effective_status(), PeerStatus::Active);
    }

    #[test]
    fn projectile_cooldown() {
        let mut o = office();
        assert!(o.can_throw());
        assert!(!o.can_throw());
    }
}
