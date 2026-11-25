//! Соединение с офисным сервером (аналог NetworkClient.swift и homeview/net.py).
//!
//! * Адрес задан вручную (`host`, `host:port`, `ws://host:port/`) — подключаемся сразу.
//! * Иначе ищем сервер через mDNS/Bonjour (`_homeview._tcp`).
//! * Разрыв — переподключение через 2, 4, 8 … 30 секунд.
//!
//! Всё сетевое — в отдельном потоке (блокирующий tungstenite с коротким таймаутом чтения),
//! наружу — события через переданную функцию, внутрь — команды через канал.

use std::io::ErrorKind;
use std::net::{IpAddr, TcpStream, ToSocketAddrs};
use std::sync::mpsc::{self, Receiver, RecvTimeoutError, Sender};
use std::thread;
use std::time::{Duration, Instant};

use tungstenite::{Message, WebSocket};

use crate::protocol::{ClientMessage, ServerMessage, DEFAULT_PORT, SERVICE_TYPE};

const DISCOVERY_WARN: Duration = Duration::from_secs(12);
const CONNECT_TIMEOUT: Duration = Duration::from_secs(5);
/// Как часто поток просыпается проверить исходящие сообщения, пока ждёт входящие.
const POLL: Duration = Duration::from_millis(30);
const RETRY_FIRST: u64 = 2;
const RETRY_MAX: u64 = 30;

#[derive(Clone, Debug, PartialEq)]
pub enum NetState {
    Searching,
    Connecting(String),
    /// Подпись сервера: «имя (host:port)» или «host:port».
    Connected(String),
    /// Пояснение для пользователя; переподключение уже запланировано.
    Failed(String),
}

#[derive(Debug)]
pub enum NetEvent {
    State(NetState),
    Message(ServerMessage),
}

enum Command {
    Send(String),
    RetryNow,
    Stop,
}

/// Живёт, пока жив объект: при удалении поток закрывает соединение и завершается сам.
pub struct NetworkClient {
    commands: Sender<Command>,
}

impl NetworkClient {
    /// `hello` вызывается при каждом подключении (имя/статус могли измениться).
    pub fn start<H, E>(address: &str, hello: H, events: E) -> NetworkClient
    where
        H: Fn() -> ClientMessage + Send + 'static,
        E: Fn(NetEvent) + Send + 'static,
    {
        let (tx, rx) = mpsc::channel();
        let address = address.trim().to_string();
        thread::Builder::new()
            .name("homeview-net".into())
            .spawn(move || Worker { commands: rx, hello: Box::new(hello), events: Box::new(events) }.run(&address))
            .expect("сетевой поток");
        NetworkClient { commands: tx }
    }

    /// Пока нет соединения, сообщения отбрасываются (как на маке).
    pub fn send(&self, message: &ClientMessage) {
        let _ = self.commands.send(Command::Send(message.encode()));
    }

    pub fn retry_now(&self) {
        let _ = self.commands.send(Command::RetryNow);
    }
}

impl Drop for NetworkClient {
    fn drop(&mut self) {
        let _ = self.commands.send(Command::Stop);
    }
}

/// `host`, `host:port`, `[v6]:port`, `ws://host:port/` → (host, port).
pub fn parse_address(address: &str) -> (String, u16) {
    let mut a = address.trim();
    for prefix in ["ws://", "http://"] {
        if let Some(rest) = a.strip_prefix(prefix) {
            a = rest;
        }
    }
    let a = a.trim_end_matches('/');
    let port_of = |p: &str| p.parse::<u16>().unwrap_or(DEFAULT_PORT);
    if let Some(rest) = a.strip_prefix('[') {
        let (host, tail) = rest.split_once(']').unwrap_or((rest, ""));
        return (host.to_string(), port_of(tail.trim_start_matches(':')));
    }
    if a.matches(':').count() == 1 {
        let (host, port) = a.split_once(':').unwrap();
        return (host.to_string(), port_of(port));
    }
    (a.to_string(), DEFAULT_PORT)
}

pub fn ws_url(host: &str, port: u16) -> String {
    match host.parse::<IpAddr>() {
        Ok(IpAddr::V6(_)) => format!("ws://[{host}]:{port}/"),
        _ => format!("ws://{host}:{port}/"),
    }
}

/// Почему закончилось ожидание или сессия.
enum Outcome {
    Stop,
    Retry,
    Lost(String),
}

struct Worker {
    commands: Receiver<Command>,
    hello: Box<dyn Fn() -> ClientMessage + Send>,
    events: Box<dyn Fn(NetEvent) + Send>,
}

impl Worker {
    fn state(&self, s: NetState) {
        (self.events)(NetEvent::State(s));
    }

    fn run(self, address: &str) {
        let mut delay = RETRY_FIRST;
        loop {
            let target = if address.is_empty() {
                match self.discover() {
                    Ok(t) => Some(t),
                    Err(Outcome::Stop) => return,
                    Err(Outcome::Retry) => None,
                    Err(Outcome::Lost(detail)) => {
                        self.state(NetState::Failed(detail));
                        None
                    }
                }
            } else {
                let (host, port) = parse_address(address);
                Some((host.clone(), port, format!("{host}:{port}")))
            };
            if let Some((host, port, label)) = target {
                self.state(NetState::Connecting(format!("{host}:{port}")));
                match connect(&host, port) {
                    Ok(ws) => {
                        delay = RETRY_FIRST;
                        self.state(NetState::Connected(label));
                        match self.session(ws) {
                            Outcome::Stop => return,
                            Outcome::Retry => continue,
                            Outcome::Lost(detail) => self.state(NetState::Failed(detail)),
                        }
                    }
                    Err(e) => self.state(NetState::Failed(format!("Сервер не отвечает: {e}"))),
                }
            }
            match self.wait(Duration::from_secs(delay)) {
                Outcome::Stop => return,
                Outcome::Retry => delay = RETRY_FIRST,
                Outcome::Lost(_) => delay = (delay * 2).min(RETRY_MAX),
            }
        }
    }

    /// Пауза перед переподключением; «Lost» здесь значит «время вышло».
    fn wait(&self, delay: Duration) -> Outcome {
        let until = Instant::now() + delay;
        loop {
            let left = until.saturating_duration_since(Instant::now());
            match self.commands.recv_timeout(left) {
                Ok(Command::Stop) | Err(RecvTimeoutError::Disconnected) => return Outcome::Stop,
                Ok(Command::RetryNow) => return Outcome::Retry,
                Ok(Command::Send(_)) => {} // нет связи — сообщение пропадает
                Err(RecvTimeoutError::Timeout) => return Outcome::Lost(String::new()),
            }
        }
    }

    fn discover(&self) -> Result<(String, u16, String), Outcome> {
        self.state(NetState::Searching);
        let fail = |e: mdns_sd::Error| Outcome::Lost(format!("Поиск сервера не работает: {e}. Укажите адрес вручную."));
        let daemon = mdns_sd::ServiceDaemon::new().map_err(fail)?;
        let browser = daemon.browse(SERVICE_TYPE).map_err(fail)?;
        let started = Instant::now();
        let mut warned = false;
        let result = loop {
            match self.commands.try_recv() {
                Ok(Command::Stop) | Err(mpsc::TryRecvError::Disconnected) => break Err(Outcome::Stop),
                Ok(Command::RetryNow) => break Err(Outcome::Retry),
                _ => {}
            }
            if !warned && started.elapsed() > DISCOVERY_WARN {
                warned = true; // поиск продолжается — сервер может появиться позже
                self.state(NetState::Failed("Офисный сервер не найден. Попробуй указать адрес вручную в настройках.".into()));
            }
            if let Ok(mdns_sd::ServiceEvent::ServiceResolved(info)) = browser.recv_timeout(Duration::from_millis(200)) {
                let addresses = info.get_addresses();
                let address = addresses.iter().find(|a| a.is_ipv4()).or_else(|| addresses.iter().next());
                if let (Some(ip), port) = (address, info.get_port()) {
                    if port != 0 {
                        let name = info.get_fullname();
                        let name = name.strip_suffix(&format!(".{SERVICE_TYPE}")).unwrap_or(name);
                        let host = ip.to_string();
                        log::info!("Найден сервер {name} ({host}:{port})");
                        break Ok((host.clone(), port, format!("{name} ({host}:{port})")));
                    }
                }
            }
        };
        let _ = daemon.shutdown();
        result
    }

    fn session(&self, mut ws: WebSocket<TcpStream>) -> Outcome {
        if let Err(e) = ws.send(Message::text((self.hello)().encode())) {
            return lost(e);
        }
        loop {
            loop {
                match self.commands.try_recv() {
                    Ok(Command::Send(text)) => {
                        if let Err(e) = ws.send(Message::text(text)) {
                            return lost(e);
                        }
                    }
                    Ok(Command::RetryNow) => {}
                    Ok(Command::Stop) | Err(mpsc::TryRecvError::Disconnected) => {
                        let _ = ws.close(None);
                        let _ = ws.flush();
                        return Outcome::Stop;
                    }
                    Err(mpsc::TryRecvError::Empty) => break,
                }
            }
            match ws.read() {
                Ok(Message::Text(text)) => match ServerMessage::decode(text.as_str()) {
                    Ok(message) => (self.events)(NetEvent::Message(message)),
                    Err(e) => log::debug!("Непонятное сообщение ({e}): {}", text.as_str().chars().take(200).collect::<String>()),
                },
                Ok(Message::Close(_)) => return Outcome::Lost("Соединение с сервером потеряно".into()),
                Ok(_) => {} // ping/pong/binary — tungstenite отвечает на ping сам
                Err(tungstenite::Error::Io(e)) if matches!(e.kind(), ErrorKind::WouldBlock | ErrorKind::TimedOut) => {
                    let _ = ws.flush(); // отправить накопившиеся pong
                }
                Err(e) => return lost(e),
            }
        }
    }
}

/// Пользователю — простое «потеряно», подробности — в журнал.
fn lost(e: tungstenite::Error) -> Outcome {
    log::info!("Соединение потеряно: {e}");
    Outcome::Lost("Соединение с сервером потеряно".into())
}

fn connect(host: &str, port: u16) -> Result<WebSocket<TcpStream>, String> {
    let addrs: Vec<_> = (host, port).to_socket_addrs().map_err(|e| e.to_string())?.collect();
    let mut last = String::from("адрес не найден");
    for addr in addrs {
        match TcpStream::connect_timeout(&addr, CONNECT_TIMEOUT) {
            Ok(stream) => {
                let _ = stream.set_nodelay(true);
                stream.set_read_timeout(Some(CONNECT_TIMEOUT)).map_err(|e| e.to_string())?;
                let (ws, _) = tungstenite::client(ws_url(host, port), stream).map_err(|e| e.to_string())?;
                ws.get_ref().set_read_timeout(Some(POLL)).map_err(|e| e.to_string())?;
                return Ok(ws);
            }
            Err(e) => last = e.to_string(),
        }
    }
    Err(last)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn addresses() {
        assert_eq!(parse_address("mini.local"), ("mini.local".into(), 47777));
        assert_eq!(parse_address(" 10.0.0.5:9000 "), ("10.0.0.5".into(), 9000));
        assert_eq!(parse_address("ws://10.0.0.5:9000/"), ("10.0.0.5".into(), 9000));
        assert_eq!(parse_address("[fe80::1]:47777"), ("fe80::1".into(), 47777));
        assert_eq!(parse_address("fe80::1"), ("fe80::1".into(), 47777));
        assert_eq!(ws_url("fe80::1", 47777), "ws://[fe80::1]:47777/");
        assert_eq!(ws_url("mini.local", 1), "ws://mini.local:1/");
    }
}
