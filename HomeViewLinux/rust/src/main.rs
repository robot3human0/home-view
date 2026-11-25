//! Проба Rust-стека для HomeView.
//!
//! 1. Прозрачный оверлей на каждом мониторе (GLX с альфой), осадки целиком в шейдере.
//! 2. Человечки из спрайтов HomeView/Art с перекраской, таблички (кириллица, эмодзи), облачка;
//!    мышь ловится только над человечками (XShape input region), остальное — насквозь.
//!
//! Запуск: `cargo run --release -- [--small] [--seconds N] [--season winter|spring|summer|autumn] [--fps N]`
//! ЛКМ по человечку — машет и здоровается, ПКМ — подпрыгивает.

mod figure;
mod gfx;
mod particles;
mod text;

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
use x11rb::protocol::xproto::{ClipOrdering, Rectangle};

use figure::{Art, Hat, Peer, Status, Style};
use gfx::SpriteBatch;
use particles::{GpuLayer, ParticleRenderer};
use text::Text;

const AVATAR_SCALE: f32 = 2.0; // настройки Python-версии по умолчанию
const TEXT_SCALE: f32 = 2.5;

#[allow(dead_code)] // window держим живым
struct Overlay {
    window: Window,
    xid: u32,
    surface: Surface<WindowSurface>,
    layers: Vec<GpuLayer>,
    width: f32,
    height: f32,
    peers: Vec<Peer>,
    cursor: (f32, f32),
    hovering: bool,
    input_rects: Option<Vec<(i16, i16, u16, u16)>>,
}

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
    stats: Stats,
    frame: Duration,
    next_frame: Instant,
    last_tick: Instant,
}

fn attributes(pos: PhysicalPosition<i32>, size: PhysicalSize<u32>) -> WindowAttributes {
    Window::default_attributes()
        .with_title("HomeView probe")
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

fn xid(window: &Window) -> u32 {
    match window.window_handle().unwrap().as_raw() {
        RawWindowHandle::Xlib(h) => h.window as u32,
        RawWindowHandle::Xcb(h) => h.window.get(),
        other => panic!("не X11-окно: {other:?}"),
    }
}

fn demo_peers() -> Vec<(&'static str, &'static str, Status, Style)> {
    vec![
        ("Алишер", "Backend", Status::Active, Style { hat: Hat::Beanie, hat_color: 0xC62828, vest_color: 0xF57C00, skin_color: 0xE0AC69 }),
        ("Nodira", "iOS", Status::Active, Style { hat: Hat::Cap, hat_color: 0x1E3A5F, vest_color: 0x43A047, skin_color: 0xF1C27D }),
        ("Тимур", "QA", Status::Away, Style { hat: Hat::Doppi, hat_color: 0x1E3A5F, vest_color: 0x1E88E5, skin_color: 0xC68642 }),
        ("Kamola", "Design", Status::Busy, Style { hat: Hat::StrawHat, hat_color: 0x8E24AA, vest_color: 0xD81B60, skin_color: 0xFFDBAC }),
    ]
}

impl App {
    fn create(&mut self, event_loop: &ActiveEventLoop) {
        let template = ConfigTemplateBuilder::new().with_alpha_size(8).with_transparency(true);
        let (_, config) = glutin_winit::DisplayBuilder::new()
            .with_window_attributes(None)
            .build(event_loop, template, pick_config)
            .expect("GLX недоступен");
        eprintln!("Конфиг: alpha={} samples={}", config.alpha_size(), config.num_samples());
        let (conn, _) = x11rb::connect(None).expect("X11");
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
                    self.particles = Some(ParticleRenderer::new(gl));
                }
            }
            let (w, h) = (size.width as f32, size.height as f32);
            let renderer = self.particles.as_mut().unwrap();
            let layers = unsafe { renderer.prepare(&self.opts.season, w, h, self.opts.density) };

            let mut peers = Vec::new();
            if self.overlays.is_empty() {
                let started = Instant::now();
                let text = self.text.get_or_insert_with(Text::new);
                let mut art = Art::new();
                let list = demo_peers();
                let n = list.len() as f32;
                for (i, (pname, team, status, style)) in list.into_iter().enumerate() {
                    let x = w * (i as f32 + 0.5) / n;
                    let mut p = unsafe { Peer::new(&renderer.gl, &mut art, text, pname, team, status, style, x, AVATAR_SCALE, TEXT_SCALE) };
                    p.ground_y = h;
                    peers.push(p);
                }
                eprintln!("Человечки: {} шт., подготовка {:.0} мс", peers.len(), started.elapsed().as_secs_f32() * 1000.0);
            }
            let id = xid(&window);
            eprintln!("Окно {name}: {}x{} +{}+{} xid=0x{id:x}", size.width, size.height, pos.x, pos.y);
            self.overlays.push(Overlay { window, xid: id, surface, layers, width: w, height: h, peers,
                                         cursor: (-1.0, -1.0), hovering: false, input_rects: None });
            context = Some(ctx);
        }
        self.context = context;
        self.x11 = Some(conn);
        self.update_input_regions();
    }

    /// Мышь ловим только над человечками; без человечков окно целиком «прозрачно» для кликов.
    fn update_input_regions(&mut self) {
        let Some(conn) = &self.x11 else { return };
        for o in &mut self.overlays {
            let rects: Vec<Rectangle> = o.peers.iter().flat_map(|p| p.hit_rects()).map(|(x, y, w, h)| {
                Rectangle { x: x.floor() as i16, y: y.floor() as i16, width: w.ceil() as u16, height: h.ceil() as u16 }
            }).collect();
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
        let (Some(ctx), Some(renderer), Some(batch)) = (&self.context, &self.particles, &mut self.batch) else { return };
        let gl = &renderer.gl;
        let now = Instant::now();
        let dt = (now - self.last_tick).as_secs_f32().min(0.1);
        self.last_tick = now;
        let time = self.start.elapsed().as_secs_f32();
        let cpu_started = Instant::now();
        // Сначала второстепенные (без ожидания vsync), последним — основной, его swap ждёт кадр.
        for overlay in self.overlays.iter_mut().rev() {
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
                batch.end(gl);
            }
            overlay.surface.swap_buffers(ctx).unwrap();
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

    fn mouse(&mut self, id: WindowId, button: MouseButton) {
        let (Some(text), Some(renderer)) = (&mut self.text, &self.particles) else { return };
        let Some(o) = self.overlays.iter_mut().find(|o| o.window.id() == id) else { return };
        let (cx, cy) = o.cursor;
        let Some(p) = o.peers.iter_mut().rev().find(|p| p.contains(cx, cy)) else {
            eprintln!("Клик мимо человечка в ({cx:.0}, {cy:.0}) — не должен был дойти до окна");
            return;
        };
        eprintln!("Клик по «{}» ({button:?})", p.name);
        unsafe {
            match button {
                MouseButton::Left => {
                    p.wave();
                    p.say(&renderer.gl, text, "👋 Привет! Как дела? Пойдём на чай ☕", 3.0);
                }
                _ => {
                    p.hop();
                    p.say(&renderer.gl, text, "Ой!", 1.5);
                }
            }
        }
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

impl ApplicationHandler for App {
    fn resumed(&mut self, event_loop: &ActiveEventLoop) {
        if self.overlays.is_empty() {
            self.create(event_loop);
            self.next_frame = Instant::now();
            self.last_tick = Instant::now();
        }
    }

    fn window_event(&mut self, event_loop: &ActiveEventLoop, id: WindowId, event: WindowEvent) {
        match event {
            WindowEvent::CloseRequested => event_loop.exit(),
            WindowEvent::CursorMoved { position, .. } => {
                if let Some(o) = self.overlays.iter_mut().find(|o| o.window.id() == id) {
                    o.cursor = (position.x as f32, position.y as f32);
                    let over = o.peers.iter().any(|p| p.contains(o.cursor.0, o.cursor.1));
                    if over != o.hovering {
                        o.hovering = over;
                        o.window.set_cursor(if over { CursorIcon::Pointer } else { CursorIcon::Default });
                    }
                }
            }
            WindowEvent::MouseInput { state: ElementState::Pressed, button, .. } => self.mouse(id, button),
            _ => {}
        }
    }

    fn about_to_wait(&mut self, event_loop: &ActiveEventLoop) {
        if self.start.elapsed().as_secs_f32() >= self.opts.seconds {
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
            self.render();
            // Ограничитель: следующий кадр не раньше чем через 1/fps (vsync сверху выравнивает).
            self.next_frame = (self.next_frame + self.frame).max(Instant::now() + self.frame / 2);
        }
        event_loop.set_control_flow(ControlFlow::WaitUntil(self.next_frame));
    }
}

fn main() {
    let mut opts = Options { small: false, seconds: 20.0, season: particles::season_for_today().into(), fps: 60.0, density: 0.7 };
    let args: Vec<String> = std::env::args().skip(1).collect();
    let mut i = 0;
    while i < args.len() {
        let next = |i: usize| args.get(i + 1).cloned().unwrap_or_default();
        match args[i].as_str() {
            "--small" => opts.small = true,
            "--seconds" => { opts.seconds = next(i).parse().unwrap_or(20.0); i += 1; }
            "--season" => { opts.season = next(i); i += 1; }
            "--fps" => { opts.fps = next(i).parse().unwrap_or(60.0); i += 1; }
            "--density" => { opts.density = next(i).parse().unwrap_or(0.7); i += 1; }
            other => { eprintln!("неизвестный параметр {other}"); std::process::exit(2); }
        }
        i += 1;
    }
    eprintln!("Сезон: {}, плотность {}, выход через {} с", opts.season, opts.density, opts.seconds);
    let frame = Duration::from_secs_f32(1.0 / opts.fps);
    let now = Instant::now();
    let mut app = App {
        opts, start: now, overlays: Vec::new(), context: None, particles: None, batch: None, text: None, x11: None,
        stats: Stats::default(), frame, next_frame: now, last_tick: now,
    };
    let event_loop = EventLoop::new().expect("event loop");
    event_loop.run_app(&mut app).expect("run");
}
