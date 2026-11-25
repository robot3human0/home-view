//! Протокол HomeView (совместим с HomeViewProtocol/Protocol.swift, версия 4).
//!
//! JSON в текстовых кадрах WebSocket, в формате синтезированного Swift `Codable`
//! для enum с ассоциированными значениями (в serde это externally tagged):
//!
//! ```text
//! именованные поля:    {"hello":{"id":"…","name":"…",…}}   → struct-вариант
//! безымянное значение: {"status":{"_0":"active"}}          → struct-вариант с полем, переименованным в "_0"
//! без значений:        {"jump":{}}                         → пустой struct-вариант `Jump {}`
//! Optional == nil:     ключ отсутствует                    → skip_serializing_if + default
//! ```
//!
//! Источник правды — Swift-файлы. При обновлении HomeView от iOS-команды сверять diff `HomeViewProtocol/`
//! и прогонять `HomeViewLinux/tools/swift_check/run.sh`.

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};
use serde_json::Value;

pub const PROTOCOL_VERSION: i64 = 4;
pub const DEFAULT_PORT: u16 = 47777;
pub const DOWNLOAD_PORT: u16 = 47778;
pub const SERVICE_TYPE: &str = "_homeview._tcp.local.";
pub const MAX_CHAT_LENGTH: usize = 200;

// MARK: - Модели

/// Неизвестное значение (из будущей версии протокола) читаем как «по умолчанию», а не роняем сообщение.
#[derive(Serialize, Deserialize, Clone, Copy, Debug, PartialEq, Eq, Hash, Default)]
#[serde(rename_all = "camelCase")]
pub enum PeerStatus {
    Away,
    Busy,
    Hidden,
    // serde требует, чтобы вариант с #[serde(other)] был последним
    #[default]
    #[serde(other)]
    Active,
}

impl PeerStatus {
    pub const ALL: [PeerStatus; 4] = [PeerStatus::Active, PeerStatus::Away, PeerStatus::Busy, PeerStatus::Hidden];
}

#[derive(Serialize, Deserialize, Clone, Copy, Debug, PartialEq, Eq, Hash, Default)]
#[serde(rename_all = "camelCase")]
pub enum HatStyle {
    Beanie,
    Cap,
    StrawHat,
    #[default]
    #[serde(other)]
    Doppi,
}

impl HatStyle {
    pub const ALL: [HatStyle; 4] = [HatStyle::Beanie, HatStyle::Cap, HatStyle::Doppi, HatStyle::StrawHat];
}

/// Цвета — 0xRRGGBB (в Swift `UInt32`).
#[derive(Serialize, Deserialize, Clone, Copy, Debug, PartialEq, Eq, Hash)]
#[serde(rename_all = "camelCase")]
pub struct AvatarStyle {
    pub hat: HatStyle,
    pub hat_color: u32,
    pub vest_color: u32,
    pub skin_color: u32,
}

impl AvatarStyle {
    pub const STANDARD: AvatarStyle =
        AvatarStyle { hat: HatStyle::Doppi, hat_color: 0x1E3A5F, vest_color: 0x1E88E5, skin_color: 0xE0AC69 };
}

impl Default for AvatarStyle {
    fn default() -> Self {
        AvatarStyle::STANDARD
    }
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct PeerInfo {
    pub id: String,
    pub name: String,
    pub team: String,
    pub avatar: AvatarStyle,
    pub status: PeerStatus,
}

#[derive(Serialize, Deserialize, Clone, Copy, Debug, PartialEq, Eq, Hash)]
#[serde(rename_all = "camelCase")]
pub enum GameKind {
    HotBall,
    Marksman,
    Volleyball,
    Tennis,
    Penalty,
    Basketball,
    TugOfWar,
    ChessBlitz,
    ChessDaily,
    ChessTeam,
    /// Игра из более новой версии протокола — показываем как «🎮 игра», сами не предлагаем.
    #[serde(other)]
    Unknown,
}

impl GameKind {
    /// (эмодзи, название по-русски)
    pub fn title(self) -> (&'static str, &'static str) {
        match self {
            GameKind::HotBall => ("💣", "Ледяной мяч"),
            GameKind::Marksman => ("🎯", "Снайпер"),
            GameKind::Volleyball => ("🏐", "Волейбол"),
            GameKind::Tennis => ("🏓", "Настольный теннис"),
            GameKind::Penalty => ("⚽", "Пенальти"),
            GameKind::Basketball => ("🏀", "Баскетбол"),
            GameKind::TugOfWar => ("🪢", "Перетягивание каната"),
            GameKind::ChessBlitz => ("♟️", "Шахматы · блиц"),
            GameKind::ChessDaily => ("♟️", "Шахматы · по ходу в день"),
            GameKind::ChessTeam => ("♟️", "Шахматы · командные"),
            GameKind::Unknown => ("🎮", "Игра"),
        }
    }

    pub fn max_players(self) -> usize {
        match self {
            GameKind::HotBall => 10,
            GameKind::Marksman | GameKind::Penalty | GameKind::Basketball | GameKind::ChessTeam => 12,
            GameKind::Volleyball => 8,
            GameKind::Tennis => 4,
            GameKind::TugOfWar => 16,
            GameKind::ChessBlitz | GameKind::ChessDaily => 2,
            GameKind::Unknown => 2,
        }
    }
}

#[derive(Serialize, Deserialize, Clone, Copy, Debug, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum RoomPhase {
    Lobby,
    Playing,
    Finished,
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct RoomInfo {
    pub id: String,
    pub game: GameKind,
    #[serde(rename = "hostID")]
    pub host_id: String,
    pub players: Vec<String>,
    pub phase: RoomPhase,
    /// Когда лобби стартует само (Unix, секунды).
    #[serde(rename = "startsAt", default, skip_serializing_if = "Option::is_none")]
    pub starts_at: Option<f64>,
    /// Командные игры: игрок → команда (0 — синие, 1 — красные).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub teams: Option<BTreeMap<String, i64>>,
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct AppRelease {
    pub version: String,
    pub build: i64,
    pub url: String,
    pub notes: String,
}

#[derive(Serialize, Deserialize, Clone, Copy, Debug, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum PingKind {
    Wave,
    Tea,
}

#[derive(Serialize, Deserialize, Clone, Copy, Debug, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum ChessPieceKind {
    King,
    Queen,
    Rook,
    Bishop,
    Knight,
    Pawn,
}

#[derive(Serialize, Deserialize, Clone, Copy, Debug, PartialEq, Eq)]
pub struct ChessMove {
    pub from: i64,
    pub to: i64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub promotion: Option<ChessPieceKind>,
}

#[derive(Serialize, Deserialize, Clone, Copy, Debug, PartialEq)]
#[serde(rename_all = "camelCase")]
pub enum SportAction {
    Jump {},
    Pull {},
    /// Пенальти: куда бьём (0…1 относительно ворот).
    Aim { x: f64, y: f64 },
    /// Пенальти: куда прыгает вратарь (0…1).
    Dive { x: f64 },
    /// Баскетбол: угол (рад) и сила (0…1).
    Shoot { angle: f64, power: f64 },
}

// MARK: - Клиент → сервер

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
#[serde(rename_all = "camelCase")]
pub enum ClientMessage {
    Hello { id: String, name: String, team: String, avatar: AvatarStyle, status: PeerStatus, code: String, version: i64 },
    Status {
        #[serde(rename = "_0")]
        status: PeerStatus,
    },
    Profile { name: String, team: String, avatar: AvatarStyle },
    Ping { to: String, kind: PingKind },
    Projectile { to: String },
    /// `to: None` — всем.
    Chat {
        #[serde(default, skip_serializing_if = "Option::is_none")]
        to: Option<String>,
        text: String,
    },
    Invite { to: String, game: GameKind },
    Respond {
        #[serde(rename = "roomID")]
        room_id: String,
        accept: bool,
    },
    Join {
        #[serde(rename = "roomID")]
        room_id: String,
    },
    Leave {
        #[serde(rename = "roomID")]
        room_id: String,
    },
    Start {
        #[serde(rename = "roomID")]
        room_id: String,
    },
    Pass {
        #[serde(rename = "roomID")]
        room_id: String,
        to: String,
    },
    Hit {
        #[serde(rename = "roomID")]
        room_id: String,
        #[serde(rename = "targetID")]
        target_id: i64,
    },
    SwitchTeam {
        #[serde(rename = "roomID")]
        room_id: String,
    },
    SportMove {
        #[serde(rename = "roomID")]
        room_id: String,
        value: f64,
    },
    SportAction {
        #[serde(rename = "roomID")]
        room_id: String,
        action: SportAction,
    },
    ChessMove {
        #[serde(rename = "gameID")]
        game_id: String,
        #[serde(rename = "move")]
        mv: ChessMove,
    },
    ChessResign {
        #[serde(rename = "gameID")]
        game_id: String,
    },
    ChessDraw {
        #[serde(rename = "gameID")]
        game_id: String,
    },
    ChessWatch {
        #[serde(rename = "gameID")]
        game_id: String,
    },
}

impl ClientMessage {
    pub fn hello(id: &str, name: &str, team: &str, avatar: AvatarStyle, status: PeerStatus, code: &str) -> Self {
        ClientMessage::Hello {
            id: id.into(), name: name.into(), team: team.into(), avatar, status, code: code.into(),
            version: PROTOCOL_VERSION,
        }
    }

    /// Сообщение обрезается до `MAX_CHAT_LENGTH` символов (как на маке).
    pub fn chat(to: Option<&str>, text: &str) -> Self {
        ClientMessage::Chat { to: to.map(Into::into), text: text.chars().take(MAX_CHAT_LENGTH).collect() }
    }

    pub fn encode(&self) -> String {
        serde_json::to_string(self).expect("сообщение клиента всегда кодируется")
    }
}

// MARK: - Сервер → клиент

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
#[serde(rename_all = "camelCase")]
pub enum ServerMessage {
    Welcome { you: String, peers: Vec<PeerInfo>, rooms: Vec<RoomInfo> },
    Rejected { reason: String },
    Notice { text: String },
    PeerJoined {
        #[serde(rename = "_0")]
        peer: PeerInfo,
    },
    PeerUpdated {
        #[serde(rename = "_0")]
        peer: PeerInfo,
    },
    PeerLeft { id: String },
    Ping { from: String, kind: PingKind },
    Projectile { from: String },
    Chat { from: String, text: String, direct: bool },
    Invited {
        #[serde(rename = "roomID")]
        room_id: String,
        from: String,
        game: GameKind,
    },
    Declined {
        #[serde(rename = "roomID")]
        room_id: String,
        by: String,
    },
    Room {
        #[serde(rename = "_0")]
        room: RoomInfo,
    },
    RoomClosed {
        #[serde(rename = "roomID")]
        room_id: String,
    },
    /// События игр разберём, когда дойдём до игр.
    Game {
        #[serde(rename = "roomID")]
        room_id: String,
        event: Value,
    },
    LatestApp {
        #[serde(rename = "_0")]
        release: AppRelease,
    },
    Chess {
        #[serde(rename = "_0")]
        state: Value,
    },
    ChessLive {
        #[serde(rename = "_0")]
        games: Value,
    },
}

impl ServerMessage {
    /// Ошибка — сообщение из более новой версии сервера или битое: его пропускают, соединение не рвут.
    pub fn decode(text: &str) -> Result<ServerMessage, serde_json::Error> {
        serde_json::from_str(text)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn avatar() -> AvatarStyle {
        AvatarStyle { hat: HatStyle::StrawHat, hat_color: 0xC62828, vest_color: 0x1565C0, skin_color: 0xFFDBAC }
    }

    #[test]
    fn swift_codable_shapes() {
        assert_eq!(ClientMessage::Status { status: PeerStatus::Away }.encode(), r#"{"status":{"_0":"away"}}"#);
        assert_eq!(
            ClientMessage::hello("X", "Имя", "", avatar(), PeerStatus::Hidden, "k").encode(),
            r#"{"hello":{"id":"X","name":"Имя","team":"","avatar":{"hat":"strawHat","hatColor":12986408,"vestColor":1402304,"skinColor":16767916},"status":"hidden","code":"k","version":4}}"#
        );
        assert_eq!(ClientMessage::chat(None, "всем").encode(), r#"{"chat":{"text":"всем"}}"#);
        assert_eq!(ClientMessage::chat(Some("P"), "hi").encode(), r#"{"chat":{"to":"P","text":"hi"}}"#);
        assert_eq!(
            ClientMessage::SportAction { room_id: "R".into(), action: SportAction::Jump {} }.encode(),
            r#"{"sportAction":{"roomID":"R","action":{"jump":{}}}}"#
        );
        assert_eq!(
            ClientMessage::ChessMove { game_id: "G".into(), mv: ChessMove { from: 12, to: 28, promotion: None } }.encode(),
            r#"{"chessMove":{"gameID":"G","move":{"from":12,"to":28}}}"#
        );
    }

    #[test]
    fn chat_is_truncated_by_characters() {
        let long = "ж".repeat(300);
        let ClientMessage::Chat { text, .. } = ClientMessage::chat(None, &long) else { unreachable!() };
        assert_eq!(text.chars().count(), MAX_CHAT_LENGTH);
    }

    #[test]
    fn decodes_server_messages() {
        let text = r#"{"welcome":{"you":"ME","peers":[{"id":"P","name":"Жасур","team":"iOS","avatar":{"hat":"beanie","hatColor":8068638,"vestColor":4431943,"skinColor":12993090},"status":"away"}],"rooms":[{"id":"R","game":"volleyball","hostID":"P","players":["P"],"phase":"lobby","startsAt":1800000000.5,"teams":{"P":0}}]}}"#;
        let ServerMessage::Welcome { peers, rooms, .. } = ServerMessage::decode(text).unwrap() else { panic!() };
        assert_eq!(peers[0].status, PeerStatus::Away);
        assert_eq!(peers[0].avatar.hat, HatStyle::Beanie);
        assert_eq!(rooms[0].starts_at, Some(1_800_000_000.5));
        assert_eq!(ServerMessage::decode(r#"{"peerLeft":{"id":"P"}}"#).unwrap(), ServerMessage::PeerLeft { id: "P".into() });
        // Swift пишет "/" как "\/" — читается как обычный слэш
        let ServerMessage::LatestApp { release } =
            ServerMessage::decode(r#"{"latestApp":{"_0":{"version":"1","build":14,"url":"http:\/\/x\/","notes":""}}}"#).unwrap()
        else { panic!() };
        assert_eq!(release.url, "http://x/");
    }

    #[test]
    fn unknown_values_fall_back() {
        let peer: PeerInfo = serde_json::from_str(
            r#"{"id":"P","name":"N","team":"","avatar":{"hat":"crown","hatColor":0,"vestColor":0,"skinColor":0},"status":"dancing"}"#,
        ).unwrap();
        assert_eq!((peer.avatar.hat, peer.status), (HatStyle::Doppi, PeerStatus::Active));
        assert!(ServerMessage::decode(r#"{"fireworks":{}}"#).is_err());
        assert!(matches!(ServerMessage::decode(r#"{"invited":{"roomID":"R","from":"P","game":"curling"}}"#),
                         Ok(ServerMessage::Invited { game: GameKind::Unknown, .. })));
    }
}
