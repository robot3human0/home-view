import AppKit
import Combine
import HomeViewProtocol
import SwiftUI

/// O‘ng yuqori burchakdagi kichik kartochkalar oynasi.
/// Ilovani faollashtirmaydi (ishingiz to‘xtamaydi), lekin xabar yozish uchun klaviaturani qabul qila oladi.
final class ToastPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class ToastCenter {
    static let shared = ToastCenter()
    private var panel: ToastPanel?
    private var hosting: NSHostingView<ToastStack>?
    private var subscription: AnyCancellable?

    func start() {
        subscription = Office.shared.$toasts
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                // SwiftUI o‘zini yangilab olishi uchun bir lahza kutamiz, keyin o‘lchamni moslaymiz
                DispatchQueue.main.async { self?.refresh() }
            }
    }

    private func makePanel() -> ToastPanel {
        let panel = ToastPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 100),
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        let view = NSHostingView(rootView: ToastStack(office: Office.shared))
        panel.contentView = view
        hosting = view
        return panel
    }

    private func refresh() {
        let toasts = Office.shared.toasts
        guard !toasts.isEmpty else {
            panel?.orderOut(nil)
            return
        }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        guard let hosting, let screen = NSScreen.screens.first else { return }
        let size = hosting.fittingSize
        let frame = screen.visibleFrame
        panel.setFrame(NSRect(x: frame.maxX - size.width - 12, y: frame.maxY - size.height - 8,
                              width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
        if toasts.contains(where: { if case .compose = $0.kind { return true }; return false }) {
            panel.makeKey()
        }
    }
}

// MARK: - Ko‘rinishlar

struct ToastStack: View {
    @ObservedObject var office: Office

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            VStack(alignment: .trailing, spacing: 10) {
                ForEach(office.toasts) { toast in
                    ToastCard(toast: toast, office: office)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .padding(12)
        .frame(width: 360)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: office.toasts.map { $0.id })
    }
}

struct ToastCard: View {
    let toast: Toast
    @ObservedObject var office: Office

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Text(toast.icon)
                    .font(.system(size: 22))
                VStack(alignment: .leading, spacing: 3) {
                    Text(toast.title)
                        .font(.system(size: 13, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    if !toast.message.isEmpty {
                        Text(toast.message)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                Button {
                    office.dismiss(toast.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            content
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    @ViewBuilder
    private var content: some View {
        switch toast.kind {
        case .standard:
            if !toast.actions.isEmpty {
                HStack {
                    Spacer()
                    ForEach(toast.actions) { action in
                        if action.primary {
                            Button(action.title) {
                                action.handler()
                                office.dismiss(toast.id)
                            }
                            .buttonStyle(.glassProminent)
                        } else {
                            Button(action.title) {
                                action.handler()
                                office.dismiss(toast.id)
                            }
                            .buttonStyle(.glass)
                        }
                    }
                }
            }
        case .lobby(let roomID):
            LobbyView(roomID: roomID, office: office)
        case .compose(let to):
            ComposeView(to: to, toastID: toast.id, office: office)
        }
    }
}

/// O‘yin lobbisi: kimlar qo‘shildi, qachon boshlanadi.
struct LobbyView: View {
    let roomID: String
    @ObservedObject var office: Office

    var body: some View {
        if let room = office.rooms.first(where: { $0.id == roomID }) {
            VStack(alignment: .leading, spacing: 8) {
                if room.game.isTeamGame {
                    VStack(alignment: .leading, spacing: 4) {
                        teamLine(room, team: TeamSide.blue)
                        teamLine(room, team: TeamSide.red)
                    }
                } else {
                    Text(playersLine(room))
                        .font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)
                }
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    if let startsAt = room.startsAt {
                        let left = max(0, Int(startsAt - context.date.timeIntervalSince1970))
                        Text("\(left) soniyadan keyin boshlanadi")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Kamida yana bitta o‘yinchi kerak...")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Spacer()
                    if room.game.isTeamGame {
                        Button("⇄ Jamoa") { office.switchTeam(roomID: roomID) }
                            .buttonStyle(.glass)
                            .help("Boshqa jamoaga o‘tish")
                    }
                    Button("Chiqish") { office.leave(roomID: roomID) }
                        .buttonStyle(.glass)
                    if room.hostID == office.myID {
                        Button("Hozir boshlash") { office.start(roomID: roomID) }
                            .buttonStyle(.glassProminent)
                            .disabled(room.players.count < room.game.minPlayers)
                    }
                }
            }
        } else {
            Text("O‘yin yopildi")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private func playersLine(_ room: RoomInfo) -> String {
        let names: [String] = room.players.map { office.name($0) }
        return "O‘yinchilar (\(room.players.count)/\(room.game.maxPlayers)): " + names.joined(separator: ", ")
    }

    private func teamLine(_ room: RoomInfo, team: Int) -> some View {
        let ids: [String] = room.players.filter { room.team(of: $0) == team }
        let names: [String] = ids.map { office.name($0) }
        let list: String = names.isEmpty ? "—" : names.joined(separator: ", ")
        let label: String
        if room.game.isChess {
            label = team == TeamSide.blue ? "♔ Oqlar" : "♚ Qoralar"
        } else {
            label = "\(TeamSide.emoji(team)) \(TeamSide.name(team))"
        }
        return Text("\(label): \(list)")
            .font(.system(size: 12))
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Qisqa xabar yozish.
struct ComposeView: View {
    let to: String?
    let toastID: UUID
    @ObservedObject var office: Office
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Xabar (Enter — yuborish)", text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(send)
            HStack {
                Text("\(text.count)/\(HVProtocol.maxChatLength)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Bekor") { office.dismiss(toastID) }
                    .buttonStyle(.glass)
                Button("Yuborish", action: send)
                    .buttonStyle(.glassProminent)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear { focused = true }
    }

    private func send() {
        office.chat(to: to, text: String(text.prefix(HVProtocol.maxChatLength)))
        office.dismiss(toastID)
    }
}
