//! Rust-часть проверки совместимости с настоящим Swift-протоколом (см. tools/swift_check/run.sh).
//!
//!     protocol_check write-client <файл>   — сообщения клиента для Swift JSONDecoder
//!     protocol_check verify-server <файл>  — разобрать сообщения, закодированные Swift JSONEncoder

use homeview::protocol::*;

fn client_messages() -> Vec<ClientMessage> {
    let avatar = AvatarStyle { hat: HatStyle::StrawHat, hat_color: 0xC62828, vest_color: 0x1565C0, skin_color: 0xFFDBAC };
    let room = || "ROOM-1".to_string();
    let mut m = vec![
        ClientMessage::hello("3F2504E0-4F89-11D3-9A0C-0305E82C3301", "Алишер", "Backend", avatar, PeerStatus::Active, ""),
        ClientMessage::hello("X", "Имя", "", AvatarStyle::STANDARD, PeerStatus::Hidden, "qishki2026"),
        ClientMessage::Profile { name: "Алишер И.".into(), team: "Backend".into(), avatar },
        ClientMessage::Ping { to: "PEER-1".into(), kind: PingKind::Wave },
        ClientMessage::Ping { to: "PEER-1".into(), kind: PingKind::Tea },
        ClientMessage::Projectile { to: "PEER-1".into() },
        ClientMessage::chat(Some("PEER-1"), "Привет! 👋 \"кавычки\" и \\ слэш"),
        ClientMessage::chat(None, "Всем привет"),
        ClientMessage::Invite { to: "PEER-1".into(), game: GameKind::Volleyball },
        ClientMessage::Respond { room_id: room(), accept: false },
        ClientMessage::Respond { room_id: room(), accept: true },
        ClientMessage::Join { room_id: room() },
        ClientMessage::Leave { room_id: room() },
        ClientMessage::Start { room_id: room() },
        ClientMessage::Pass { room_id: room(), to: "PEER-1".into() },
        ClientMessage::Hit { room_id: room(), target_id: 7 },
        ClientMessage::SwitchTeam { room_id: room() },
        ClientMessage::SportMove { room_id: room(), value: 0.25 },
        ClientMessage::ChessMove { game_id: "G-1".into(), mv: ChessMove { from: 12, to: 28, promotion: None } },
        ClientMessage::ChessMove { game_id: "G-1".into(), mv: ChessMove { from: 52, to: 60, promotion: Some(ChessPieceKind::Queen) } },
        ClientMessage::ChessResign { game_id: "G-1".into() },
        ClientMessage::ChessDraw { game_id: "G-1".into() },
        ClientMessage::ChessWatch { game_id: "G-1".into() },
    ];
    for action in [SportAction::Jump {}, SportAction::Pull {}, SportAction::Aim { x: 0.2, y: 0.8 },
                   SportAction::Dive { x: 0.5 }, SportAction::Shoot { angle: 0.9, power: 0.6 }] {
        m.push(ClientMessage::SportAction { room_id: room(), action });
    }
    m.extend(PeerStatus::ALL.map(|status| ClientMessage::Status { status }));
    m.extend(HatStyle::ALL.map(|hat| ClientMessage::hello("H", "Шапка", "", AvatarStyle { hat, hat_color: 0xFFFFFF, vest_color: 0, skin_color: 0x123456 }, PeerStatus::Active, "")));
    m
}

fn check(message: &ServerMessage) -> Result<String, String> {
    let ensure = |ok: bool, what: &str| if ok { Ok(()) } else { Err(format!("не совпало: {what}")) };
    let jasur = AvatarStyle { hat: HatStyle::Beanie, hat_color: 0x7B1E1E, vest_color: 0x43A047, skin_color: 0xC68642 };
    Ok(match message {
        ServerMessage::Welcome { you, peers, rooms } => {
            ensure(you == "ME", "you")?;
            ensure(peers[0].name == "Жасур" && peers[0].status == PeerStatus::Away && peers[0].avatar == jasur, "peer")?;
            ensure(rooms[0].starts_at == Some(1_800_000_000.5) && rooms[0].teams.as_ref().and_then(|t| t.get("PEER-1")) == Some(&0), "room 1")?;
            ensure(rooms[1].starts_at.is_none() && rooms[1].teams.is_none() && rooms[1].phase == RoomPhase::Playing, "room 2")?;
            format!("{} коллега, {} комнаты", peers.len(), rooms.len())
        }
        ServerMessage::PeerJoined { peer } | ServerMessage::PeerUpdated { peer } => {
            ensure(peer.name == "Жасур" && peer.team == "iOS" && peer.avatar == jasur, "peer")?;
            format!("{} · {} ({:?})", peer.name, peer.team, peer.status)
        }
        ServerMessage::Room { room } => {
            ensure(room.game == GameKind::Volleyball && room.host_id == "PEER-1" && room.phase == RoomPhase::Lobby, "room")?;
            format!("{:?} {:?}", room.game, room.phase)
        }
        ServerMessage::LatestApp { release } => {
            ensure(release.build == 14 && release.url == "http://x/", "release")?;
            format!("{} (build {})", release.version, release.build)
        }
        ServerMessage::Chat { from, text, direct } => {
            ensure(from == "PEER-1", "from")?;
            format!("{text:?} direct={direct}")
        }
        ServerMessage::Invited { game, .. } => {
            ensure(*game == GameKind::ChessBlitz, "game")?;
            format!("{game:?}")
        }
        other => format!("{other:?}").chars().take(90).collect(),
    })
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match (args.first().map(String::as_str), args.get(1)) {
        (Some("write-client"), Some(path)) => {
            let messages = client_messages();
            let text: String = messages.iter().map(|m| m.encode() + "\n").collect();
            std::fs::write(path, text).expect("запись");
            println!("Записано {} сообщений клиента (Rust)", messages.len());
        }
        (Some("verify-server"), Some(path)) => {
            let text = std::fs::read_to_string(path).expect("чтение");
            let lines: Vec<&str> = text.lines().filter(|l| !l.trim().is_empty()).collect();
            let mut failures = 0;
            for line in &lines {
                match ServerMessage::decode(line).map_err(|e| e.to_string()).and_then(|m| check(&m)) {
                    Ok(detail) => println!("OK   {detail}"),
                    Err(e) => {
                        failures += 1;
                        println!("FAIL {e}\n     {}", &line.chars().take(120).collect::<String>());
                    }
                }
            }
            println!("Разобрано {} из {} сообщений сервера (Rust)", lines.len() - failures, lines.len());
            std::process::exit(if failures == 0 { 0 } else { 1 });
        }
        _ => {
            eprintln!("protocol_check write-client|verify-server <файл>");
            std::process::exit(2);
        }
    }
}
