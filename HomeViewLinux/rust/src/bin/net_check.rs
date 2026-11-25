//! Проверка сетевой части без окон: подключиться к серверу (mock_server.py или настоящему),
//! вывести события, помахать первому коллеге и написать всем.
//!
//!     net_check [адрес] [секунд]      — без адреса ищет сервер через mDNS

use std::sync::mpsc;
use std::time::{Duration, Instant};

use homeview::net::{NetEvent, NetworkClient};
use homeview::protocol::*;

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let address = args.first().cloned().unwrap_or_default();
    let seconds: u64 = args.get(1).and_then(|s| s.parse().ok()).unwrap_or(15);
    let start = Instant::now();
    let (tx, rx) = mpsc::channel();
    let avatar = AvatarStyle { hat: HatStyle::Beanie, hat_color: 0xC62828, vest_color: 0xF57C00, skin_color: 0xE0AC69 };
    let client = NetworkClient::start(
        &address,
        move || ClientMessage::hello("RUST-NET-CHECK", "Проба Rust", "Linux", avatar, PeerStatus::Active, ""),
        move |e| { let _ = tx.send(e); },
    );
    let mut greeted = false;
    while start.elapsed() < Duration::from_secs(seconds) {
        let Ok(event) = rx.recv_timeout(Duration::from_millis(100)) else { continue };
        let t = start.elapsed().as_secs_f32();
        match event {
            NetEvent::State(s) => println!("{t:6.2} СОСТОЯНИЕ {s:?}"),
            NetEvent::Message(m) => {
                let text = format!("{m:?}");
                println!("{t:6.2} ← {}", text.chars().take(150).collect::<String>());
                if let ServerMessage::Welcome { peers, .. } = &m {
                    if let Some(p) = peers.iter().find(|p| p.id != "RUST-NET-CHECK") {
                        if !greeted {
                            greeted = true;
                            println!("{t:6.2} → машу {} и пишу всем", p.name);
                            client.send(&ClientMessage::Ping { to: p.id.clone(), kind: PingKind::Wave });
                            client.send(&ClientMessage::chat(None, "Привет из Rust 🦀"));
                            client.send(&ClientMessage::Status { status: PeerStatus::Busy });
                        }
                    }
                }
            }
        }
    }
    drop(client);
    std::thread::sleep(Duration::from_millis(200)); // дать потоку закрыть соединение
}
