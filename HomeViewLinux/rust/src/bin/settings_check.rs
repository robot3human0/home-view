//! Показать, как Rust-клиент читает настройки (код офиса скрыт). Файл не меняется.
fn main() {
    let path = homeview::settings::config_path();
    let text = std::fs::read_to_string(&path).unwrap_or_default();
    let mut s = homeview::settings::Settings::from_ini(&homeview::settings::Ini::parse(&text));
    if !s.office_code.is_empty() {
        s.office_code = format!("*** ({} симв.)", s.office_code.chars().count());
    }
    println!("{}\n{s:#?}", path.display());
}
