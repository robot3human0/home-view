//! Настройки — тот же файл, что у Python-клиента (QSettings, INI):
//! `$XDG_CONFIG_HOME/HomeView/HomeViewLinux.conf`. Поэтому ID, имя, шапка и код офиса общие:
//! у коллег это один и тот же человечек, какой бы клиент ни был запущен (но не оба сразу).
//!
//! Формат QSettings: секция `[General]`, строки с особыми символами — в кавычках с `\`-экранированием,
//! список строк — через «, », пустой список — `@Invalid()`. Незнакомые ключи сохраняются как есть.

use std::collections::BTreeSet;
use std::path::PathBuf;

use crate::protocol::{AvatarStyle, HatStyle, PeerStatus};

pub fn config_path() -> PathBuf {
    let base = std::env::var_os("XDG_CONFIG_HOME").map(PathBuf::from).filter(|p| p.is_absolute())
        .unwrap_or_else(|| PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(".config"));
    base.join("HomeView").join("HomeViewLinux.conf")
}

/// Строки INI-файла как есть + разобранные пары ключ=значение секции [General].
#[derive(Clone, Debug, Default)]
pub struct Ini {
    lines: Vec<String>,
}

impl Ini {
    pub fn parse(text: &str) -> Ini {
        Ini { lines: text.lines().map(str::to_string).collect() }
    }

    fn general_range(&self) -> Option<(usize, usize)> {
        let start = self.lines.iter().position(|l| l.trim() == "[General]")?;
        let end = self.lines[start + 1..].iter().position(|l| l.trim_start().starts_with('['))
            .map(|i| start + 1 + i).unwrap_or(self.lines.len());
        Some((start + 1, end))
    }

    pub fn raw(&self, key: &str) -> Option<&str> {
        let (a, b) = self.general_range()?;
        self.lines[a..b].iter().find_map(|l| {
            let (k, v) = l.split_once('=')?;
            (k.trim() == key).then(|| v.trim())
        })
    }

    pub fn set_raw(&mut self, key: &str, value: String) {
        let line = format!("{key}={value}");
        let (a, b) = match self.general_range() {
            Some(r) => r,
            None => {
                self.lines.insert(0, "[General]".into());
                (1, 1 + self.lines[1..].iter().position(|l| l.trim_start().starts_with('[')).unwrap_or(self.lines.len() - 1))
            }
        };
        if let Some(i) = (a..b).find(|&i| self.lines[i].split_once('=').is_some_and(|(k, _)| k.trim() == key)) {
            self.lines[i] = line;
        } else {
            // QSettings держит ключи по алфавиту — вставляем туда же (не обязательно, но diff аккуратнее)
            let at = (a..b).find(|&i| self.lines[i].split_once('=').is_some_and(|(k, _)| k.trim() > key)).unwrap_or(b);
            self.lines.insert(at, line);
        }
    }

    pub fn to_text(&self) -> String {
        let mut s = self.lines.join("\n");
        s.push('\n');
        s
    }

    pub fn string(&self, key: &str) -> Option<String> {
        self.raw(key).map(|v| unquote(v).0)
    }

    pub fn list(&self, key: &str) -> Vec<String> {
        let Some(v) = self.raw(key) else { return Vec::new() };
        if v.is_empty() || v == "@Invalid()" {
            return Vec::new();
        }
        let mut out = Vec::new();
        let mut rest = v;
        loop {
            let (item, tail) = unquote(rest);
            out.push(item);
            match tail.trim_start().strip_prefix(',') {
                Some(t) => rest = t.trim_start(),
                None => break,
            }
        }
        out
    }
}

/// Значение QSettings → строка; возвращает и остаток после значения (для списков).
fn unquote(v: &str) -> (String, &str) {
    let Some(body) = v.strip_prefix('"') else {
        let end = v.find(',').unwrap_or(v.len());
        return (v[..end].trim().to_string(), &v[end..]);
    };
    let mut out = String::new();
    let mut chars = body.char_indices();
    while let Some((i, c)) = chars.next() {
        match c {
            '"' => return (out, &body[i + 1..]),
            '\\' => match chars.next().map(|(_, c)| c) {
                Some('n') => out.push('\n'),
                Some('t') => out.push('\t'),
                Some('r') => out.push('\r'),
                Some('x') => {
                    let hex: String = chars.clone().take_while(|(_, c)| c.is_ascii_hexdigit()).map(|(_, c)| c).take(4).collect();
                    for _ in 0..hex.len() {
                        chars.next();
                    }
                    if let Some(ch) = u32::from_str_radix(&hex, 16).ok().and_then(char::from_u32) {
                        out.push(ch);
                    }
                }
                Some(other) => out.push(other),
                None => {}
            },
            c => out.push(c),
        }
    }
    (out, "")
}

fn quote(s: &str) -> String {
    let special = s.starts_with(' ') || s.ends_with(' ') || s.starts_with('@')
        || s.contains([',', '"', ';', '=', '\\', '\n', '\t', '\r']);
    if !special {
        return s.to_string();
    }
    let mut out = String::from("\"");
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\t' => out.push_str("\\t"),
            '\r' => out.push_str("\\r"),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

fn new_peer_id() -> String {
    // UUID v4 в верхнем регистре — как в Mac-версии
    let mut b = [0u8; 16];
    b.iter_mut().for_each(|x| *x = fastrand::u8(..));
    b[6] = (b[6] & 0x0F) | 0x40;
    b[8] = (b[8] & 0x3F) | 0x80;
    let h: String = b.iter().map(|x| format!("{x:02X}")).collect();
    format!("{}-{}-{}-{}-{}", &h[0..8], &h[8..12], &h[12..16], &h[16..20], &h[20..32])
}

fn default_name() -> String {
    // Как в Python: полное имя из passwd (GECOS), иначе логин
    let user = std::env::var("USER").unwrap_or_default();
    std::fs::read_to_string("/etc/passwd").ok()
        .and_then(|p| p.lines().find(|l| l.starts_with(&format!("{user}:"))).map(str::to_string))
        .and_then(|l| l.split(':').nth(4).map(|g| g.split(',').next().unwrap_or("").trim().to_string()))
        .filter(|g| !g.is_empty())
        .unwrap_or(user)
}

#[derive(Clone, Debug, PartialEq)]
pub struct Settings {
    pub peer_id: String,
    pub display_name: String,
    pub team: String,
    pub avatar: AvatarStyle,
    pub my_status: PeerStatus,
    pub office_enabled: bool,
    pub office_code: String,
    pub server_address: String,
    pub auto_away: bool,
    pub hidden_peers: BTreeSet<String>,
    pub effects_enabled: bool,
    /// auto | winter | spring | summer | autumn
    pub season: String,
    pub density: f32,
    pub avatar_scale: f32,
    pub text_scale: f32,
    pub toast_scale: f32,
    pub fps: u32,
}

impl Settings {
    pub fn from_ini(ini: &Ini) -> Settings {
        let s = |k: &str, d: &str| ini.string(k).unwrap_or_else(|| d.to_string());
        let b = |k: &str, d: bool| ini.string(k).map(|v| matches!(v.to_lowercase().as_str(), "true" | "1" | "yes")).unwrap_or(d);
        let f = |k: &str, d: f32, lo: f32, hi: f32| ini.string(k).and_then(|v| v.parse().ok()).unwrap_or(d).clamp(lo, hi);
        let i = |k: &str, d: u32| ini.string(k).and_then(|v| v.parse::<i64>().ok()).map(|v| v as u32).unwrap_or(d);
        let std = AvatarStyle::STANDARD;
        let hat = match s("avatarHat", "doppi").as_str() {
            "beanie" => HatStyle::Beanie,
            "cap" => HatStyle::Cap,
            "strawHat" => HatStyle::StrawHat,
            _ => HatStyle::Doppi,
        };
        let status = match s("myStatus", "active").as_str() {
            "away" => PeerStatus::Away,
            "busy" => PeerStatus::Busy,
            "hidden" => PeerStatus::Hidden,
            _ => PeerStatus::Active,
        };
        let season = s("season", "auto");
        Settings {
            peer_id: ini.string("peerID").filter(|v| !v.is_empty()).unwrap_or_default(),
            display_name: s("displayName", &default_name()),
            team: s("team", ""),
            avatar: AvatarStyle {
                hat,
                hat_color: i("avatarHatColor", std.hat_color) & 0xFFFFFF,
                vest_color: i("avatarVestColor", std.vest_color) & 0xFFFFFF,
                skin_color: i("avatarSkinColor", std.skin_color) & 0xFFFFFF,
            },
            my_status: status,
            office_enabled: b("officeEnabled", true),
            office_code: s("officeCode", "").trim().to_string(),
            server_address: s("serverAddress", "").trim().to_string(),
            auto_away: b("autoAway", true),
            hidden_peers: ini.list("hiddenPeers").into_iter().filter(|p| !p.is_empty()).collect(),
            effects_enabled: b("effectsEnabled", true),
            season: if ["auto", "winter", "spring", "summer", "autumn"].contains(&season.as_str()) { season } else { "auto".into() },
            density: f("density", 0.7, 0.1, 2.0),
            avatar_scale: f("avatarScale", 2.0, 0.6, 4.0),
            text_scale: f("textScale", 2.5, 1.0, 4.0),
            toast_scale: f("toastScale", 1.5, 1.0, 3.0),
            fps: i("fps", 60).clamp(15, 240),
        }
    }

    pub fn write_to(&self, ini: &mut Ini) {
        let hat = match self.avatar.hat {
            HatStyle::Beanie => "beanie",
            HatStyle::Cap => "cap",
            HatStyle::Doppi => "doppi",
            HatStyle::StrawHat => "strawHat",
        };
        let status = match self.my_status {
            PeerStatus::Active => "active",
            PeerStatus::Away => "away",
            PeerStatus::Busy => "busy",
            PeerStatus::Hidden => "hidden",
        };
        let pairs: Vec<(&str, String)> = vec![
            ("peerID", quote(&self.peer_id)),
            ("displayName", quote(&self.display_name)),
            ("team", quote(&self.team)),
            ("avatarHat", hat.into()),
            ("avatarHatColor", self.avatar.hat_color.to_string()),
            ("avatarVestColor", self.avatar.vest_color.to_string()),
            ("avatarSkinColor", self.avatar.skin_color.to_string()),
            ("myStatus", status.into()),
            ("officeEnabled", self.office_enabled.to_string()),
            ("officeCode", quote(&self.office_code)),
            ("serverAddress", quote(&self.server_address)),
            ("autoAway", self.auto_away.to_string()),
            ("hiddenPeers", if self.hidden_peers.is_empty() { "@Invalid()".into() }
                            else { self.hidden_peers.iter().map(|p| quote(p)).collect::<Vec<_>>().join(", ") }),
            ("effectsEnabled", self.effects_enabled.to_string()),
            ("season", self.season.clone()),
            ("density", self.density.to_string()),
            ("avatarScale", self.avatar_scale.to_string()),
            ("textScale", self.text_scale.to_string()),
            ("toastScale", self.toast_scale.to_string()),
            ("fps", self.fps.to_string()),
        ];
        for (k, v) in pairs {
            if ini.raw(k) != Some(v.as_str()) {
                ini.set_raw(k, v);
            }
        }
    }
}

/// Настройки на диске. Перечитывать при каждом открытии окна настроек: Python-клиент мог их поменять.
pub struct Store {
    path: PathBuf,
    ini: Ini,
    pub settings: Settings,
}

impl Store {
    pub fn load() -> Store {
        Store::load_from(config_path())
    }

    pub fn load_from(path: PathBuf) -> Store {
        let ini = Ini::parse(&std::fs::read_to_string(&path).unwrap_or_default());
        let mut settings = Settings::from_ini(&ini);
        let mut store = Store { path, ini, settings: settings.clone() };
        if settings.peer_id.is_empty() {
            settings.peer_id = new_peer_id();
            store.save(settings);
        }
        store
    }

    pub fn save(&mut self, settings: Settings) {
        settings.write_to(&mut self.ini);
        self.settings = settings;
        if let Some(dir) = self.path.parent() {
            let _ = std::fs::create_dir_all(dir);
        }
        let tmp = self.path.with_extension("conf.tmp");
        if std::fs::write(&tmp, self.ini.to_text()).and_then(|_| std::fs::rename(&tmp, &self.path)).is_err() {
            log::warn!("Не удалось сохранить настройки в {}", self.path.display());
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const QT: &str = "[General]\nautoAway=true\navatarHat=cap\navatarHatColor=16184820\ndisplayName=\"Иван, \\\"Ваня\\\"\"\n\
                      hiddenPeers=A-1, \"B, 2\"\nofficeCode=secret\npeerID=00000000-1111-4222-8333-444444444444\n\
                      team=BackDev Team\nunknownKey=@Variant(\\0\\0)\n";

    #[test]
    fn reads_qsettings() {
        let s = Settings::from_ini(&Ini::parse(QT));
        assert_eq!(s.display_name, "Иван, \"Ваня\"");
        assert_eq!(s.avatar.hat, HatStyle::Cap);
        assert_eq!(s.avatar.hat_color, 16184820);
        assert_eq!(s.team, "BackDev Team");
        assert_eq!(s.hidden_peers.iter().cloned().collect::<Vec<_>>(), vec!["A-1".to_string(), "B, 2".to_string()]);
        assert_eq!(s.peer_id, "00000000-1111-4222-8333-444444444444");
        assert_eq!(Settings::from_ini(&Ini::parse("[General]\nhiddenPeers=@Invalid()\n")).hidden_peers.len(), 0);
    }

    #[test]
    fn round_trip_keeps_unknown_keys() {
        let mut ini = Ini::parse(QT);
        let mut s = Settings::from_ini(&ini);
        s.my_status = PeerStatus::Busy;
        s.write_to(&mut ini);
        let text = ini.to_text();
        assert!(text.contains("unknownKey=@Variant(\\0\\0)"));
        assert!(text.contains("myStatus=busy"));
        assert!(text.contains("displayName=\"Иван, \\\"Ваня\\\"\""));
        assert_eq!(Settings::from_ini(&Ini::parse(&text)), s);
    }

    #[test]
    fn peer_id_format() {
        let id = new_peer_id();
        assert_eq!(id.len(), 36);
        assert_eq!(&id[14..15], "4");
        assert_eq!(id, id.to_uppercase());
    }
}
