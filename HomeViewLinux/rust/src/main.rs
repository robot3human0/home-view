//! HomeView — Linux-клиент на Rust.
//!
//! Прозрачный оверлей на каждом мониторе (GLX с альфой), осадки целиком в шейдере, человечки коллег
//! из сети (спрайты HomeView/Art с перекраской), таблички и облачка. Мышь ловится только над
//! человечками и открытым меню (XShape input region), остальное — насквозь.
//!
//! Запуск: `homeview [--small] [--seconds N] [--season winter|spring|summer|autumn] [--fps N] [--density X]`
//! Клик по человечку — меню коллеги. С mock-сервером: `run-mock.sh`.

mod effects;
mod figure;
mod gfx;
mod menu;
mod particles;
mod text;
mod toasts;

use std::num::NonZeroU32;
use std::time::{Duration, Instant};

use glow::HasContext;
use glutin::config::{Config, ConfigTemplateBuilder, GlConfig};
use glutin::context::{ContextApi, ContextAttributesBuilder, GlProfile, PossiblyCurrentContext, Version};
use glutin::display::{GetGlDisplay, GlDisplay};
use glutin::platform::x11::X11GlConfigExt;
use glutin::prelude::*;
use glutin::surface::{Surface, SwapInterval, WindowSurface};
use glutin_winit::GlWindow;
use raw_window_handle::{HasWindowHandle, RawWindowHandle};
use winit::application::ApplicationHandler;
use winit::dpi::{PhysicalPosition, PhysicalSize};
use winit::event::{ElementState, MouseButton, WindowEvent};
use winit::event_loop::{ActiveEventLoop, ControlFlow, EventLoop};
use winit::platform::x11::{WindowAttributesExtX11, WindowType};
use winit::window::{CursorIcon, Window, WindowAttributes, WindowId, WindowLevel};
use x11rb::connection::Connection;
use x11rb::protocol::shape::{self, ConnectionExt as _};
use x11rb::protocol::xproto::{ClipOrdering, ConnectionExt as _, Rectangle};

use std::sync::Arc;

use homeview::office::{Office, OfficeEvent, WAVE_TEXT};
use homeview::protocol::PeerInfo;
use homeview::settings::Store;
use winit::event_loop::EventLoopProxy;
use x11rb::protocol::screensaver::ConnectionExt as _;

use std::sync::mpsc::{self, Receiver, Sender};

use effects::{Effect, EffectArt, Landed};
use figure::{Art, Peer};
use homeview::office::{ActionKind, Toast};
use menu::{Command, Item, Menu};
use toasts::{Click, Toasts};
use gfx::SpriteBatch;
use particles::{GpuLayer, ParticleRenderer};
use text::Text;

const IDLE_CHECK: Duration = Duration::from_secs(15);
const THROW_TAUNTS: [&str; 4] = ["Лови!", "Держи!", "На тебе!", "Привет!"];
const HIT_REACTIONS: [&str; 4] = ["Ой!", "Эй!", "Ну, держись!", "Ай!"];

/// (эмодзи, чем кидаемся) — как в season.py
fn season_projectile(season: &str) -> (&'static str, &'static str) {
    match season {
        "spring" => ("🌸", "цветочный шарик"),
        "summer" => ("☀️", "водяной шарик"),
        "autumn" => ("🍂", "листяной шарик"),
        _ => ("❄️", "снежок"),
    }
}

#[allow(dead_code)] // window держим живым
struct Overlay {
    window: Window,
    /// Левый верхний угол монитора на общем экране X.
    pos: (f32, f32),
    xid: u32,
    surface: Surface<WindowSurface>,
    layers: Vec<GpuLayer>,
    width: f32,
    height: f32,
    peers: Vec<Peer>,
    cursor: (f32, f32),
    hovering: bool,
    input_rects: Option<Vec<(i16, i16, u16, u16)>>,
    menu: Option<Menu>,
    menu_dirty: bool,
    effects: Vec<Effect>,
}

/// Нажали на человечка: ещё не ясно — клик (меню) или перетаскивание.
struct Press {
    /// Окно, в котором нажали: X шлёт ему все движения мыши, пока кнопка не отпущена.
    overlay: usize,
    /// Монитор, на котором человечек сейчас (его можно перетащить на другой).
    peer_overlay: usize,
    peer_id: String,
    start: (f32, f32),
    /// Курсор относительно ступней — чтобы фигура не прыгала под курсор.
    grab: (f32, f32),
    dragging: bool,
}

/// Сдвиг мыши, после которого нажатие считается перетаскиванием.
const DRAG_THRESHOLD: f32 = 6.0;

struct Options {
    small: bool,
    seconds: f32,
    season: String,
    fps: f32,
    density: f32,
}

#[derive(Default)]
struct Stats {
    last: Option<Instant>,
    frames: u32,
    max_gap: Duration,
    janks: u32,
    window_start: Option<Instant>,
    total_frames: u64,
    total_janks: u64,
    worst_gap: Duration,
    worst_cpu_frame: Duration,
    shape_updates: u32,
    cpu_at_window: f32,
    steady_from: Option<(Instant, f32)>,
}

struct App {
    opts: Options,
    start: Instant,
    overlays: Vec<Overlay>,
    context: Option<PossiblyCurrentContext>,
    particles: Option<ParticleRenderer>,
    batch: Option<SpriteBatch>,
    text: Option<Text>,
    x11: Option<x11rb::rust_connection::RustConnection>,
    root: u32,
    store: Store,
    office: Office,
    art: Art,
    last_idle_check: Option<Instant>,
    proxy: EventLoopProxy<()>,
    /// Текст из диалога «Написать…» (zenity в отдельном потоке): кому, что.
    compose_tx: Sender<(Option<String>, String)>,
    compose_rx: Receiver<(Option<String>, String)>,
    press: Option<Press>,
    /// Уведомления — в углу основного монитора (overlays[0]).
    toasts: Toasts,
    effect_art: Option<EffectArt>,
    stats: Stats,
    frame: Duration,
    next_frame: Instant,
    last_tick: Instant,
}

fn attributes(pos: PhysicalPosition<i32>, size: PhysicalSize<u32>) -> WindowAttributes {
    Window::default_attributes()
        .with_title("HomeView")
        .with_decorations(false)
        .with_transparent(true)
        .with_resizable(false)
        .with_active(false)
        .with_window_level(WindowLevel::AlwaysOnTop)
        .with_position(pos)
        .with_inner_size(size)
        .with_override_redirect(true) // как Qt::X11BypassWindowManagerHint в Python-версии
        .with_x11_window_type(vec![WindowType::Utility])
}

fn pick_config(configs: Box<dyn Iterator<Item = Config> + '_>) -> Config {
    let mut all: Vec<Config> = configs.collect();
    // Только с альфой и X-visual глубины 32 — иначе вместо прозрачности чёрный экран.
    all.retain(|c| c.alpha_size() >= 8 && c.x11_visual().map_or(false, |v| v.supports_transparency()));
    all.sort_by_key(|c| c.num_samples());
    match all.into_iter().next() {
        Some(c) => c,
        None => {
            eprintln!("ОШИБКА: нет GLX-конфига с альфа-каналом и прозрачным visual — выходим, окно не создаём");
            std::process::exit(3);
        }
    }
}

/// Человечек коллеги на любом из мониторов.
fn find_peer<'a>(overlays: &'a mut [Overlay], id: &str) -> Option<&'a mut Peer> {
    overlays.iter_mut().flat_map(|o| o.peers.iter_mut()).find(|p| p.info.id == id)
}

fn xid(window: &Window) -> u32 {
    match window.window_handle().unwrap().as_raw() {
        RawWindowHandle::Xlib(h) => h.window as u32,
        RawWindowHandle::Xcb(h) => h.window.get(),
        other => panic!("не X11-окно: {other:?}"),
    }
}

impl App {
    fn create(&mut self, event_loop: &ActiveEventLoop) {
        let template = ConfigTemplateBuilder::new().with_alpha_size(8).with_transparency(true);
        let (_, config) = glutin_winit::DisplayBuilder::new()
            .with_window_attributes(None)
            .build(event_loop, template, pick_config)
            .expect("GLX недоступен");
        eprintln!("Конфиг: alpha={} samples={}", config.alpha_size(), config.num_samples());
        let (conn, screen) = x11rb::connect(None).expect("X11");
        self.root = conn.setup().roots[screen].root;
        let shape_version = conn.shape_query_version().unwrap().reply().unwrap();
        eprintln!("XShape {}.{}", shape_version.major_version, shape_version.minor_version);

        let mut rects: Vec<(PhysicalPosition<i32>, PhysicalSize<u32>, String)> = Vec::new();
        if self.opts.small {
            rects.push((PhysicalPosition::new(300, 300), PhysicalSize::new(900, 360), "small".into()));
        } else {
            for m in event_loop.available_monitors() {
                rects.push((m.position(), m.size(), m.name().unwrap_or_default()));
            }
        }
        // Первым — основной монитор: на нём человечки, его vsync задаёт темп.
        if let Some(primary) = event_loop.primary_monitor() {
            if let Some(i) = rects.iter().position(|r| r.0 == primary.position()) {
                let r = rects.remove(i);
                rects.insert(0, r);
            }
        }

        let display = config.display();
        let mut context: Option<PossiblyCurrentContext> = None;
        for (pos, size, name) in rects {
            let window = glutin_winit::finalize_window(event_loop, attributes(pos, size), &config).expect("окно");
            let attrs = window.build_surface_attributes(Default::default()).expect("surface attrs");
            let surface = unsafe { display.create_window_surface(&config, &attrs).expect("surface") };
            let ctx = match context.take() {
                None => {
                    let raw = window.window_handle().ok().map(|h| h.as_raw());
                    let attrs = ContextAttributesBuilder::new().with_profile(GlProfile::Compatibility)
                        .with_context_api(ContextApi::OpenGl(Some(Version::new(2, 1)))).build(raw);
                    let nc = unsafe { display.create_context(&config, &attrs).expect("context") };
                    nc.make_current(&surface).expect("make_current")
                }
                Some(c) => {
                    c.make_current(&surface).expect("make_current");
                    c
                }
            };
            let interval = if self.overlays.is_empty() { SwapInterval::Wait(NonZeroU32::new(1).unwrap()) } else { SwapInterval::DontWait };
            let _ = surface.set_swap_interval(&ctx, interval);
            if self.particles.is_none() {
                let gl = unsafe { glow::Context::from_loader_function_cstr(|s| display.get_proc_address(s) as *const _) };
                unsafe {
                    eprintln!("GL: {} / {}", gl.get_parameter_string(glow::VERSION), gl.get_parameter_string(glow::RENDERER));
                    self.batch = Some(SpriteBatch::new(&gl));
                    self.effect_art = Some(EffectArt::new(&gl, &self.opts.season));
                    self.particles = Some(ParticleRenderer::new(gl));
                }
            }
            let (w, h) = (size.width as f32, size.height as f32);
            let renderer = self.particles.as_mut().unwrap();
            let layers = unsafe { renderer.prepare(&self.opts.season, w, h, self.opts.density) };

            let peers = Vec::new();
            if self.overlays.is_empty() {
                self.text.get_or_insert_with(Text::new);
            }
            let id = xid(&window);
            eprintln!("Окно {name}: {}x{} +{}+{} xid=0x{id:x}", size.width, size.height, pos.x, pos.y);
            self.overlays.push(Overlay { window, pos: (pos.x as f32, pos.y as f32), xid: id, surface, layers, width: w, height: h, peers,
                                         cursor: (-1.0, -1.0), hovering: false, input_rects: None,
                                         menu: None, menu_dirty: false, effects: Vec::new() });
            context = Some(ctx);
        }
        self.context = context;
        self.x11 = Some(conn);
        self.update_input_regions();
        let settings = self.store.settings.clone();
        eprintln!("Офис: {} · {}, сервер {}", settings.display_name, settings.team,
                  if settings.server_address.is_empty() { "ищем через mDNS" } else { settings.server_address.as_str() });
        self.office.apply_settings(settings);
        self.office_tick();
    }

    /// Сетевые события офиса → человечки и облачка; раз в 15 с — проверка бездействия.
    fn office_tick(&mut self) {
        let now = Instant::now();
        if self.last_idle_check.is_none_or(|t| now - t >= IDLE_CHECK) {
            self.last_idle_check = Some(now);
            let idle = self.x11.as_ref().and_then(|c| c.screensaver_query_info(self.root).ok()?.reply().ok())
                .map(|r| Duration::from_millis(r.ms_since_user_input as u64));
            self.office.set_idle(idle);
        }
        while let Ok((to, message)) = self.compose_rx.try_recv() {
            self.office.chat(to.as_deref(), &message);
        }
        self.office.poll();
        let events = self.office.take_events();
        if events.is_empty() {
            return;
        }
        let (Some(renderer), Some(text)) = (&self.particles, &mut self.text) else { return };
        let gl = &renderer.gl;
        if self.overlays.is_empty() {
            return;
        }
        let overlays = &mut self.overlays;
        for e in events {
            match e {
                OfficeEvent::PeersChanged => {
                    let wanted: Vec<PeerInfo> = self.office.visible_peers().into_iter().cloned().collect();
                    // Человечек может жить на любом мониторе (его туда перетащили)
                    for o in overlays.iter_mut() {
                        o.peers.retain_mut(|p| {
                            let keep = wanted.iter().any(|w| w.id == p.info.id);
                            if !keep {
                                unsafe { p.delete(gl) };
                            }
                            keep
                        });
                    }
                    for info in &wanted {
                        match find_peer(overlays, &info.id) {
                            Some(p) => unsafe { p.update_info(gl, &mut self.art, text, info) },
                            None => {
                                // Новый коллега появляется у края основного монитора и уходит внутрь
                                let primary = &mut overlays[0];
                                let x = if fastrand::bool() { 0.0 } else { primary.width };
                                let s = &self.store.settings;
                                let mut p = unsafe { Peer::new(gl, &mut self.art, text, info, x, s.avatar_scale, s.text_scale) };
                                p.ground_y = primary.height;
                                p.clamp_x(primary.width);
                                primary.peers.push(p);
                            }
                        }
                    }
                }
                OfficeEvent::ConnectionChanged => eprintln!("Офис: {}", self.office.status_line()),
                OfficeEvent::Toast(t) => {
                    eprintln!("УВЕДОМЛЕНИЕ {} {} — {}", t.icon, t.title, t.body);
                    self.toasts.post(text, t);
                }
                OfficeEvent::DismissToast(key) => self.toasts.dismiss_key(&key),
                OfficeEvent::PeerWaves(id) => if let Some(p) = find_peer(overlays, &id) {
                    p.wave();
                    unsafe { p.say(gl, text, WAVE_TEXT, 2.5) };
                },
                OfficeEvent::PeerSays { id, text: message } => if let Some(p) = find_peer(overlays, &id) {
                    unsafe { p.say(gl, text, &message, 5.0) };
                },
                OfficeEvent::PeerHops(id) => if let Some(p) = find_peer(overlays, &id) {
                    p.hop();
                },
                OfficeEvent::IncomingProjectile(id) => {
                    // Коллега кинул в нас: его человечек замахивается, снаряд летит «в экран» и прилипает
                    let index = overlays.iter().position(|o| o.peers.iter().any(|p| p.info.id == id)).unwrap_or(0);
                    let o = &mut overlays[index];
                    let (start, delay) = match o.peers.iter_mut().find(|p| p.info.id == id) {
                        Some(p) => {
                            p.throw_motion();
                            let taunt = THROW_TAUNTS[fastrand::usize(..THROW_TAUNTS.len())];
                            unsafe { p.say(gl, text, taunt, 2.0) };
                            (p.hand_point(), 0.3)
                        }
                        None => ((60.0 + fastrand::f32() * (o.width - 120.0), o.height + 40.0), 0.0),
                    };
                    // Целимся рядом с курсором, если он на этом мониторе
                    let pointer = self.x11.as_ref().and_then(|c| c.query_pointer(self.root).ok()?.reply().ok())
                        .map(|r| (r.root_x as f32 - o.pos.0, r.root_y as f32 - o.pos.1))
                        .filter(|&(x, y)| x >= 0.0 && y >= 0.0 && x < o.width && y < o.height);
                    let (tx, ty) = match pointer {
                        Some((x, y)) => (x + fastrand::f32() * 120.0 - 60.0, y + fastrand::f32() * 100.0 - 50.0),
                        None => (o.width * (0.25 + fastrand::f32() * 0.5), o.height * (0.3 + fastrand::f32() * 0.35)),
                    };
                    let target = (tx.clamp(90.0, o.width - 90.0), ty.clamp(90.0, o.height - 90.0));
                    let control = ((start.0 + target.0) / 2.0, start.1.min(target.1) - 160.0);
                    o.effects.push(Effect::flying(start, target, control, 0.8, 0.35, 3.4, 28.0, true, delay,
                                                  Landed::Splat { x: target.0, y: target.1 }));
                }
            }
        }
    }

    /// Мышь ловим только над человечками; без человечков окно целиком «прозрачно» для кликов.
    fn update_input_regions(&mut self) {
        let Some(conn) = &self.x11 else { return };
        let first_pos = self.overlays.first().map(|o| o.pos).unwrap_or_default();
        for o in &mut self.overlays {
            // Открыто меню — ловим клики по всему окну: клик мимо меню просто закрывает его
            let rects: Vec<Rectangle> = if o.menu.is_some() {
                vec![Rectangle { x: 0, y: 0, width: o.width as u16, height: o.height as u16 }]
            } else {
                let cards = if o.pos == first_pos { self.toasts.rects(o.width) } else { Vec::new() };
                o.peers.iter().flat_map(|p| p.hit_rects()).chain(cards).map(|(x, y, w, h)| {
                    Rectangle { x: x.floor() as i16, y: y.floor() as i16, width: w.ceil() as u16, height: h.ceil() as u16 }
                }).collect()
            };
            let key: Vec<_> = rects.iter().map(|r| (r.x, r.y, r.width, r.height)).collect();
            if o.input_rects.as_ref() != Some(&key) {
                conn.shape_rectangles(shape::SO::SET, shape::SK::INPUT, ClipOrdering::UNSORTED, o.xid, 0, 0, &rects).unwrap();
                o.input_rects = Some(key);
                self.stats.shape_updates += 1;
            }
        }
        conn.flush().unwrap();
    }

    fn render(&mut self) {
        let (Some(ctx), Some(renderer), Some(batch), Some(text)) = (&self.context, &self.particles, &mut self.batch, &mut self.text)
            else { return };
        let gl = &renderer.gl;
        let now = Instant::now();
        let dt = (now - self.last_tick).as_secs_f32().min(0.1);
        self.last_tick = now;
        let time = self.start.elapsed().as_secs_f32();
        let cpu_started = Instant::now();
        // Сначала второстепенные (без ожидания vsync), последним — основной, его swap ждёт кадр.
        let toasts = &mut self.toasts;
        toasts.tick(dt);
        let effect_art = self.effect_art.as_ref();
        let mut landed: Vec<(usize, Landed)> = Vec::new();
        for (index, overlay) in self.overlays.iter_mut().enumerate().rev() {
            ctx.make_current(&overlay.surface).unwrap();
            unsafe {
                gl.viewport(0, 0, overlay.width as i32, overlay.height as i32);
                gl.clear_color(0.0, 0.0, 0.0, 0.0);
                gl.clear(glow::COLOR_BUFFER_BIT);
                renderer.draw(&overlay.layers, overlay.width, overlay.height, overlay.height, time);
                gl.bind_vertex_array(Some(renderer.vao));
                batch.begin(gl, overlay.width, overlay.height);
                for p in &mut overlay.peers {
                    p.tick(dt, overlay.width);
                    p.draw(gl, batch, now);
                }
                let mut done = Vec::new();
                overlay.effects.retain_mut(|e| e.tick(dt, &mut done));
                landed.extend(done.into_iter().map(|l| (index, l)));
                if let Some(art) = effect_art {
                    for e in &overlay.effects {
                        e.draw(gl, batch, art);
                    }
                }
                if index == 0 {
                    toasts.draw(gl, batch, text, overlay.width);
                }
                if let Some(menu) = &mut overlay.menu {
                    let tex = menu.texture(gl, text, overlay.menu_dirty);
                    overlay.menu_dirty = false;
                    batch.quad(gl, tex, &gfx::Affine::IDENTITY, menu.x, menu.y, tex.width as f32, tex.height as f32,
                               [1.0, 1.0, 1.0], 1.0);
                }
                batch.end(gl);
            }
            overlay.surface.swap_buffers(ctx).unwrap();
        }
        unsafe { self.toasts.sweep(gl) };
        for (index, l) in landed {
            self.on_landed(index, l);
        }
        let cpu = cpu_started.elapsed();
        self.update_input_regions();

        let now = Instant::now();
        let s = &mut self.stats;
        s.worst_cpu_frame = s.worst_cpu_frame.max(cpu);
        if let Some(last) = s.last {
            let gap = now - last;
            s.max_gap = s.max_gap.max(gap);
            s.worst_gap = s.worst_gap.max(gap);
            if gap > self.frame.mul_f32(1.5) {
                s.janks += 1;
                s.total_janks += 1;
            }
        }
        s.last = Some(now);
        s.frames += 1;
        s.total_frames += 1;
        let ws = *s.window_start.get_or_insert_with(|| { s.cpu_at_window = cpu_seconds(); now });
        if now - ws >= Duration::from_secs(5) {
            let secs = (now - ws).as_secs_f32();
            eprintln!("{:5.1} с: {:.1} кадр/с, макс. пауза {:.1} мс, рывков {}, CPU {:.1}% ядра, XShape {}/5с",
                      time, s.frames as f32 / secs, s.max_gap.as_secs_f32() * 1000.0, s.janks,
                      (cpu_seconds() - s.cpu_at_window) / secs * 100.0, s.shape_updates);
            s.cpu_at_window = cpu_seconds();
            // Итог считаем после первого 5-секундного окна (без загрузки шрифтов и текстур)
            if s.steady_from.is_none() {
                s.steady_from = Some((now, s.cpu_at_window));
                s.total_frames = 0;
                s.total_janks = 0;
                s.worst_gap = Duration::ZERO;
                s.worst_cpu_frame = Duration::ZERO;
            }
            s.frames = 0;
            s.janks = 0;
            s.shape_updates = 0;
            s.max_gap = Duration::ZERO;
            s.window_start = Some(now);
        }
    }

    fn mouse_press(&mut self, id: WindowId) {
        let Some(index) = self.overlays.iter().position(|o| o.window.id() == id) else { return };
        let (cx, cy) = self.overlays[index].cursor;
        // Открытое меню: пункт — выполнить, мимо — просто закрыть
        if self.overlays[index].menu.is_some() {
            let command = self.overlays[index].menu.as_ref().and_then(|m| m.command_at(cx, cy));
            self.close_menu(index);
            if let Some(c) = command {
                self.run(c);
            }
            return;
        }
        if index == 0 {
            match self.toasts.click(self.overlays[0].width, cx, cy) {
                Some(Click::Action(action)) => {
                    self.perform(action);
                    return;
                }
                Some(Click::Handled) => return,
                None => {}
            }
        }
        let Some(p) = self.overlays[index].peers.iter().rev().find(|p| p.contains(cx, cy)) else {
            eprintln!("Клик мимо человечка в ({cx:.0}, {cy:.0}) — не должен был дойти до окна");
            return;
        };
        let (fx, fy) = p.feet();
        self.press = Some(Press { overlay: index, peer_overlay: index, peer_id: p.info.id.clone(), start: (cx, cy), grab: (cx - fx, cy - fy),
                                  dragging: false });
    }

    /// Пока кнопка нажата, X присылает движение мыши этому окну, даже вне области кликов
    /// и даже над другим монитором (координаты — относительно этого окна).
    fn mouse_drag(&mut self, index: usize) {
        let Some(press) = &mut self.press else { return };
        if press.overlay != index {
            return;
        }
        let (lx, ly) = self.overlays[index].cursor;
        if !press.dragging {
            if (lx - press.start.0).hypot(ly - press.start.1) < DRAG_THRESHOLD {
                return;
            }
            press.dragging = true;
            let o = &mut self.overlays[press.peer_overlay];
            if let Some(p) = o.peers.iter_mut().find(|p| p.info.id == press.peer_id) {
                p.start_drag();
            }
            self.overlays[index].window.set_cursor(CursorIcon::Grabbing);
        }
        // Где курсор на общем экране и над каким он монитором
        let origin = self.overlays[index].pos;
        let (gx, gy) = (origin.0 + lx, origin.1 + ly);
        let target = self.overlays.iter()
            .position(|o| gx >= o.pos.0 && gx < o.pos.0 + o.width && gy >= o.pos.1 && gy < o.pos.1 + o.height)
            .unwrap_or(press.peer_overlay);
        if target != press.peer_overlay {
            // Переезд на другой монитор: тот же человечек (текстуры общие — один GL-контекст)
            let from = &mut self.overlays[press.peer_overlay].peers;
            if let Some(i) = from.iter().position(|p| p.info.id == press.peer_id) {
                let mut p = from.remove(i);
                p.ground_y = self.overlays[target].height;
                self.overlays[target].peers.push(p);
                press.peer_overlay = target;
            }
        }
        let o = &mut self.overlays[press.peer_overlay];
        let (x, y) = (gx - o.pos.0, gy - o.pos.1);
        if let Some(p) = o.peers.iter_mut().find(|p| p.info.id == press.peer_id) {
            p.drag_to(x - press.grab.0, y - press.grab.1, o.width);
        }
    }

    fn mouse_release(&mut self, id: WindowId) {
        let Some(press) = self.press.take() else { return };
        let Some(index) = self.overlays.iter().position(|o| o.window.id() == id) else { return };
        if press.overlay != index {
            return;
        }
        if press.dragging {
            if let Some(p) = self.overlays[press.peer_overlay].peers.iter_mut().find(|p| p.info.id == press.peer_id) {
                p.drop_down();
            }
            let o = &mut self.overlays[index];
            o.hovering = false;
            o.window.set_cursor(CursorIcon::Default);
            return;
        }
        // Клик без перетаскивания — меню коллеги
        let o = &self.overlays[index];
        let (cx, cy) = o.cursor;
        let items = self.peer_menu(&press.peer_id);
        let (Some(text), w, h) = (&mut self.text, o.width, o.height) else { return };
        let menu = Menu::new(text, items, (cx, cy), (w, h), self.store.settings.toast_scale);
        let o = &mut self.overlays[index];
        o.menu = Some(menu);
        o.menu_dirty = true;
        o.window.set_cursor(CursorIcon::Default);
        self.update_input_regions();
    }

    fn close_menu(&mut self, index: usize) {
        let gl = self.particles.as_ref().map(|r| &r.gl);
        let o = &mut self.overlays[index];
        if let (Some(mut m), Some(gl)) = (o.menu.take(), gl) {
            unsafe { m.delete(gl) };
        }
        o.hovering = false;
        self.update_input_regions();
    }

    /// Меню коллеги — как fill_peer_menu в office.py.
    fn peer_menu(&self, id: &str) -> Vec<Item> {
        let Some(info) = self.office.peers.get(id) else { return vec![Item::Info("Коллега ушёл".into())] };
        let mut items = vec![
            Item::Info(if info.team.is_empty() { info.name.clone() } else { format!("{} · {}", info.name, info.team) }),
            Item::Info(homeview::office::status_title(info.status).into()),
            Item::Separator,
        ];
        if let Some(room) = self.office.rooms.values()
            .find(|r| r.host_id == id && r.phase == homeview::protocol::RoomPhase::Lobby) {
            let (emoji, title) = room.game.title();
            items.push(Item::Info(format!("{emoji} Лобби «{title}» — игры пока только на Mac")));
            items.push(Item::Separator);
        }
        let (emoji, projectile) = season_projectile(&self.opts.season);
        items.extend([
            Item::Action("👋  Помахать".into(), Command::Wave(id.into())),
            Item::Action(format!("{emoji}  Кинуть {projectile}"), Command::Throw(id.into())),
            Item::Action("💬  Написать…".into(), Command::Compose(Some(id.into()))),
            Item::Action("☕  Позвать на чай".into(), Command::Tea(id.into())),
            Item::Separator,
        ]);
        if self.store.settings.hidden_peers.contains(id) {
            items.push(Item::Action("👀  Показывать на экране".into(), Command::Show(id.into())));
        } else {
            items.push(Item::Action("🙈  Убрать с моего экрана".into(), Command::Hide(id.into())));
        }
        items
    }

    fn run(&mut self, command: Command) {
        match command {
            Command::Wave(id) => self.office.wave(&id),
            Command::Tea(id) => self.office.tea(&id),
            Command::Throw(id) => {
                if self.office.can_throw() {
                    // Мы кидаем: снаряд летит из-под края экрана в человечка; сервер узнаёт о броске при попадании
                    let found = self.overlays.iter_mut()
                        .find_map(|o| o.peers.iter().find(|p| p.info.id == id).map(|p| p.chest_point()).map(|c| (o, c)));
                    match found {
                        Some((o, point)) => {
                            let start = (point.0 + if point.0 < o.width / 2.0 { 140.0 } else { -140.0 }, o.height + 60.0);
                            let control = ((start.0 + point.0) / 2.0, point.1.min(start.1) - 140.0);
                            o.effects.push(Effect::flying(start, point, control, 0.5, 3.0, 0.8, 30.0, false, 0.0,
                                                          Landed::Hit { peer_id: id.clone() }));
                        }
                        None => self.office.projectile_hit(&id),
                    }
                }
            }
            Command::Compose(to) => self.compose(to),
            Command::Hide(id) => {
                self.set_shown(&id, false);
                let name = self.office.name(&id);
                if let Some(text) = &mut self.text {
                    self.toasts.post(text, Toast {
                        icon: "🙈".into(), title: format!("{name} убран(а) с экрана"),
                        body: "Писать и звать на чай по-прежнему можно. Вернуть: меню в трее → Коллеги.".into(),
                        actions: vec![homeview::office::ToastAction { label: "Вернуть".into(),
                                      kind: ActionKind::ShowPeer { id: id.clone() }, primary: false }],
                        auto_dismiss: Duration::from_secs(8), key: Some(format!("hidden-{id}")),
                    });
                }
            }
            Command::Show(id) => self.set_shown(&id, true),
        }
        self.office_tick();
    }

    fn on_landed(&mut self, index: usize, landed: Landed) {
        match landed {
            Landed::Splat { x, y } => self.overlays[index].effects.push(Effect::splat(x, y, 130.0)),
            Landed::Hit { peer_id } => {
                self.office.projectile_hit(&peer_id);
                let (Some(renderer), Some(text), Some(art)) = (&self.particles, &mut self.text, &self.effect_art) else { return };
                // Человечка могли за это время утащить на другой монитор
                let colors = art.burst_colors();
                for o in &mut self.overlays {
                    if let Some(p) = o.peers.iter_mut().find(|p| p.info.id == peer_id) {
                        let (x, y) = p.chest_point();
                        p.flinch();
                        let reaction = HIT_REACTIONS[fastrand::usize(..HIT_REACTIONS.len())];
                        unsafe { p.say(&renderer.gl, text, reaction, 2.0) };
                        o.effects.push(Effect::burst(x, y, colors, 14));
                        break;
                    }
                }
            }
        }
    }

    fn set_shown(&mut self, id: &str, shown: bool) {
        let mut s = self.store.settings.clone();
        if shown {
            s.hidden_peers.remove(id);
        } else {
            s.hidden_peers.insert(id.to_string());
        }
        self.store.save(s.clone());
        self.office.apply_settings(s);
    }

    /// Кнопка в уведомлении.
    fn perform(&mut self, action: ActionKind) {
        match action {
            ActionKind::Compose { to } => self.compose(to),
            ActionKind::ShowPeer { id } => self.set_shown(&id, true),
            other => self.office.perform(&other),
        }
        self.office_tick();
    }

    /// Диалог GNOME (zenity) в отдельном потоке — главный цикл и анимация не ждут.
    fn compose(&self, to: Option<String>) {
        let title = match &to {
            Some(id) => format!("Сообщение для {}", self.office.name(id)),
            None => "Сообщение всем в офисе".into(),
        };
        let tx = self.compose_tx.clone();
        let proxy = self.proxy.clone();
        std::thread::spawn(move || {
            let out = std::process::Command::new("zenity")
                .args(["--entry", "--title", &title, "--text", "Текст (до 200 символов):", "--width", "460"])
                .output();
            match out {
                Ok(o) if o.status.success() => {
                    let message = String::from_utf8_lossy(&o.stdout).trim().to_string();
                    if !message.is_empty() {
                        let _ = tx.send((to, message));
                        let _ = proxy.send_event(());
                    }
                }
                Ok(_) => {} // «Отмена»
                Err(e) => eprintln!("zenity не запустился: {e}"),
            }
        });
    }
}

/// Секунды процессорного времени процесса: utime+stime из /proc/self/stat (тики по 10 мс).
fn cpu_seconds() -> f32 {
    let stat = std::fs::read_to_string("/proc/self/stat").unwrap_or_default();
    let rest = stat.rsplit_once(')').map(|(_, r)| r).unwrap_or("");
    let f: Vec<&str> = rest.split_whitespace().collect();
    let ticks: f32 = f.get(11).and_then(|v| v.parse().ok()).unwrap_or(0.0) + f.get(12).and_then(|v| v.parse().ok()).unwrap_or(0.0);
    ticks / 100.0
}

impl ApplicationHandler<()> for App {
    fn resumed(&mut self, event_loop: &ActiveEventLoop) {
        if self.overlays.is_empty() {
            self.create(event_loop);
            self.next_frame = Instant::now();
            self.last_tick = Instant::now();
        }
    }

    /// Сетевой поток будит цикл: разобрать события офиса сразу, не дожидаясь кадра.
    fn user_event(&mut self, _: &ActiveEventLoop, _: ()) {
        self.office_tick();
    }

    fn window_event(&mut self, event_loop: &ActiveEventLoop, id: WindowId, event: WindowEvent) {
        match event {
            WindowEvent::CloseRequested => event_loop.exit(),
            WindowEvent::CursorMoved { position, .. } => {
                if let Some(index) = self.overlays.iter().position(|o| o.window.id() == id) {
                    self.overlays[index].cursor = (position.x as f32, position.y as f32);
                    if self.press.is_some() {
                        self.mouse_drag(index);
                        return;
                    }
                    let o = &mut self.overlays[index];
                    if index == 0 && o.menu.is_none() {
                        if let Some(over_button) = self.toasts.hover(o.width, o.cursor.0, o.cursor.1) {
                            if over_button != o.hovering {
                                o.hovering = over_button;
                                o.window.set_cursor(if over_button { CursorIcon::Pointer } else { CursorIcon::Default });
                            }
                            return;
                        }
                    }
                    if let Some(menu) = &mut o.menu {
                        if menu.hover(o.cursor.0, o.cursor.1) {
                            o.menu_dirty = true;
                        }
                        let over = menu.command_at(o.cursor.0, o.cursor.1).is_some();
                        if over != o.hovering {
                            o.hovering = over;
                            o.window.set_cursor(if over { CursorIcon::Pointer } else { CursorIcon::Default });
                        }
                        return;
                    }
                    let over = o.peers.iter().any(|p| p.contains(o.cursor.0, o.cursor.1));
                    if over != o.hovering {
                        o.hovering = over;
                        o.window.set_cursor(if over { CursorIcon::Pointer } else { CursorIcon::Default });
                    }
                }
            }
            WindowEvent::MouseInput { state: ElementState::Pressed, button: MouseButton::Left | MouseButton::Right, .. } => {
                self.mouse_press(id)
            }
            WindowEvent::MouseInput { state: ElementState::Released, .. } => self.mouse_release(id),
            _ => {}
        }
    }

    fn about_to_wait(&mut self, event_loop: &ActiveEventLoop) {
        if self.opts.seconds > 0.0 && self.start.elapsed().as_secs_f32() >= self.opts.seconds {
            let s = &self.stats;
            let (from, cpu0) = s.steady_from.unwrap_or((self.start, 0.0));
            let el = from.elapsed().as_secs_f32();
            eprintln!("ИТОГ (без первых 5 с): {} кадров за {el:.1} с ({:.1} кадр/с), рывков {}, худшая пауза {:.1} мс, \
                       самый долгий кадр на CPU {:.2} мс, CPU {:.1}% ядра",
                      s.total_frames, s.total_frames as f32 / el, s.total_janks, s.worst_gap.as_secs_f32() * 1000.0,
                      s.worst_cpu_frame.as_secs_f32() * 1000.0, (cpu_seconds() - cpu0) / el * 100.0);
            event_loop.exit();
            return;
        }
        if Instant::now() >= self.next_frame {
            self.office_tick();
            self.render();
            // Ограничитель: следующий кадр не раньше чем через 1/fps (vsync сверху выравнивает).
            self.next_frame = (self.next_frame + self.frame).max(Instant::now() + self.frame / 2);
        }
        event_loop.set_control_flow(ControlFlow::WaitUntil(self.next_frame));
    }
}

fn main() {
    let store = Store::load();
    let st = store.settings.clone();
    let st_scale = st.toast_scale;
    let season = if st.season == "auto" { particles::season_for_today().to_string() } else { st.season.clone() };
    let mut opts = Options { small: false, seconds: 0.0, season, fps: st.fps as f32, density: st.density };
    let args: Vec<String> = std::env::args().skip(1).collect();
    let mut i = 0;
    while i < args.len() {
        let next = |i: usize| args.get(i + 1).cloned().unwrap_or_default();
        match args[i].as_str() {
            "--small" => opts.small = true,
            "--seconds" => { opts.seconds = next(i).parse().unwrap_or(0.0); i += 1; }
            "--season" => { opts.season = next(i); i += 1; }
            "--fps" => { opts.fps = next(i).parse().unwrap_or(60.0); i += 1; }
            "--density" => { opts.density = next(i).parse().unwrap_or(0.7); i += 1; }
            other => { eprintln!("неизвестный параметр {other}"); std::process::exit(2); }
        }
        i += 1;
    }
    eprintln!("Настройки: {}", homeview::settings::config_path().display());
    eprintln!("Сезон: {}, плотность {}, {}", opts.season, opts.density,
              if opts.seconds > 0.0 { format!("выход через {} с", opts.seconds) } else { "без ограничения времени".into() });
    let frame = Duration::from_secs_f32(1.0 / opts.fps);
    let now = Instant::now();
    let event_loop = EventLoop::<()>::with_user_event().build().expect("event loop");
    let proxy: EventLoopProxy<()> = event_loop.create_proxy();
    let waker = proxy.clone();
    let office = Office::new(st, Arc::new(move || { let _ = waker.send_event(()); }));
    let (compose_tx, compose_rx) = mpsc::channel();
    let toasts = Toasts::new(st_scale);
    let mut app = App {
        opts, start: now, overlays: Vec::new(), context: None, particles: None, batch: None, text: None, x11: None,
        root: 0, store, office, art: Art::new(), last_idle_check: None, proxy, compose_tx, compose_rx, press: None, toasts, effect_art: None,
        stats: Stats::default(), frame, next_frame: now, last_tick: now,
    };
    event_loop.run_app(&mut app).expect("run");
}
