import AppKit
import SwiftUI
import HomeViewProtocol

// MARK: - Oyna

/// Shaxmat alohida kichik oynada: ish stolini band qilmaydi, istalgan joyga suriladi,
/// yopilsa ham partiya davom etadi (navbat kelganda kartochka chiqadi).
final class ChessWindowController: NSObject, NSWindowDelegate {
    static let shared = ChessWindowController()
    let model = ChessViewModel()
    private var panel: NSPanel?
    private var visible = false

    func show(gameID: String? = nil) {
        if let gameID {
            model.select(gameID)
        } else if model.selectedID == nil {
            model.selectedID = Office.shared.chessGamesSorted.first?.id
        }
        if panel == nil {
            let hosting = NSHostingController(rootView: ChessPanelView(model: model, office: Office.shared))
            let newPanel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 456, height: 680),
                                   styleMask: [.titled, .closable, .utilityWindow],
                                   backing: .buffered, defer: false)
            newPanel.contentViewController = hosting
            newPanel.title = "♟ Shaxmat"
            newPanel.isFloatingPanel = true
            newPanel.level = .floating
            newPanel.hidesOnDeactivate = false
            newPanel.isReleasedWhenClosed = false
            newPanel.delegate = self
            _ = newPanel.setFrameAutosaveName("HomeViewChess")
            if !newPanel.setFrameUsingName("HomeViewChess") {
                newPanel.center()
            }
            panel = newPanel
        }
        visible = true
        NSApp.activate()
        panel?.makeKeyAndOrderFront(nil)
    }

    /// Shu partiya hozir ekranda ochiq turibdimi (kartochka chiqarish shart emas).
    func isShowing(_ gameID: String) -> Bool {
        visible && (panel?.isVisible ?? false) && model.selectedID == gameID
    }

    func windowWillClose(_ notification: Notification) {
        visible = false
        model.selectedSquare = nil
    }
}

final class ChessViewModel: ObservableObject {
    @Published var selectedID: String?
    @Published var selectedSquare: Int?
    @Published var promotionMove: ChessMove?

    func select(_ id: String) {
        selectedID = id
        selectedSquare = nil
    }
}

// MARK: - Panel

struct ChessPanelView: View {
    @ObservedObject var model: ChessViewModel
    @ObservedObject var office: Office
    @State private var confirmResign = false

    private struct VoteRow: Identifiable {
        let id: String
        let san: String
        let count: Int
        let names: String
    }

    private var games: [ChessGameState] {
        office.chessGamesSorted
    }

    private var game: ChessGameState? {
        if let id = model.selectedID, let state = office.chessGames[id] {
            return state
        }
        return games.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if games.count > 1 {
                gamePicker
            }
            if let game {
                content(game)
            } else {
                emptyState
            }
        }
        .padding(16)
        .frame(width: 456)
        .confirmationDialog("Piyoda nimaga aylansin?", isPresented: promotionBinding, titleVisibility: .visible) {
            ForEach([ChessPieceKind.queen, .rook, .bishop, .knight], id: \.self) { kind in
                Button(kind.title) { promote(to: kind) }
            }
            Button("Bekor", role: .cancel) { model.promotionMove = nil }
        }
    }

    // MARK: Tanlash

    private var gamePicker: some View {
        let selection = Binding<String>(
            get: { game?.id ?? "" },
            set: { model.select($0) }
        )
        return Picker("Partiya", selection: selection) {
            ForEach(games, id: \.id) { state in
                Text(pickerTitle(state)).tag(state.id)
            }
        }
        .pickerStyle(.menu)
    }

    private func pickerTitle(_ state: ChessGameState) -> String {
        let prefix = "\(state.mode.emoji) \(opponentTitle(state))"
        if state.result != nil { return prefix + " · tugadi" }
        guard let mine = state.color(of: office.myID) else { return prefix + " · kuzatuv" }
        return prefix + (state.position.turn == mine ? " · navbat sizda" : " · raqib o‘ylamoqda")
    }

    private func opponentTitle(_ state: ChessGameState) -> String {
        if state.mode == .team { return "Ko‘klar — Qizillar" }
        if let mine = state.color(of: office.myID) {
            return office.chessOpponentTitle(state, for: mine)
        }
        let white = state.white.first.map { office.name($0) } ?? "?"
        let black = state.black.first.map { office.name($0) } ?? "?"
        return "\(white) — \(black)"
    }

    // MARK: Asosiy ko‘rinish

    @ViewBuilder
    private func content(_ game: ChessGameState) -> some View {
        let myColor: ChessColor? = game.color(of: office.myID)
        let bottom: ChessColor = myColor ?? .white
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            playerRow(game, color: bottom.opposite, now: context.date.timeIntervalSince1970)
        }
        ChessBoardView(state: game, flipped: bottom == .black, selected: model.selectedSquare,
                       targets: targets(game), myVote: game.votes[office.myID],
                       season: SeasonTheme.current.kind) { square in
            tap(square, game: game)
        }
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            playerRow(game, color: bottom, now: context.date.timeIntervalSince1970)
        }
        if let result = game.result {
            Text(resultText(game, result: result))
                .font(.system(size: 15, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        } else if game.mode == .team, let myColor {
            votesPanel(game, myColor: myColor)
        }
        controls(game, myColor: myColor)
        moveList(game)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("♟\u{FE0E}")
                .font(.system(size: 48))
            Text("Hozircha partiya yo‘q")
                .font(.headline)
            Text("Hamkasbning odamchasini bosing → O‘yinga taklif qilish → Shaxmat. Jamoaviy partiya: ❄ → Ofis → Hammani o‘yinga chaqirish.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: O‘yinchi qatori va soat

    private func sideTitle(_ game: ChessGameState, _ color: ChessColor) -> String {
        if game.mode == .team {
            let count = game.players(color).count
            return color == .white ? "🔵 Ko‘klar (\(count))" : "🔴 Qizillar (\(count))"
        }
        return game.players(color).first.map { office.name($0) } ?? color.title
    }

    private func clockText(_ game: ChessGameState, color: ChessColor, now: Double) -> String {
        let left: Double = game.remaining(color, now: now)
        let toMove: Bool = game.result == nil && game.position.turn == color
        switch game.mode {
        case .blitz:
            let seconds = Int(left.rounded(.up))
            return String(format: "%d:%02d", seconds / 60, seconds % 60)
        case .daily:
            guard toMove else { return "—" }
            let hours = Int(left / 3600)
            if hours >= 1 { return "\(hours) soat" }
            return "\(max(1, Int(left / 60))) daqiqa"
        case .team:
            guard toMove else { return "—" }
            if now < game.turnStartedAt { return "Tayyorlaning" }
            return "\(Int(left.rounded(.up))) s"
        }
    }

    private func playerRow(_ game: ChessGameState, color: ChessColor, now: Double) -> some View {
        let toMove: Bool = game.result == nil && game.position.turn == color
        let low: Bool = game.mode == .blitz && game.remaining(color, now: now) < 20
        let badge: Color = toMove ? (low ? Color.red : Color.accentColor) : Color.secondary.opacity(0.18)
        return HStack(spacing: 8) {
            Text(color == .white ? "♔" : "♚")
                .font(.system(size: 18))
            Text(sideTitle(game, color))
                .font(.system(size: 13, weight: toMove ? .semibold : .regular))
                .lineLimit(1)
            Spacer()
            Text(clockText(game, color: color, now: now))
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(badge))
                .foregroundStyle(toMove ? Color.white : Color.primary)
        }
    }

    // MARK: Jamoa ovozlari

    private func voteRows(_ game: ChessGameState) -> [VoteRow] {
        var grouped: [ChessMove: [String]] = [:]
        for (voter, move) in game.votes {
            grouped[move, default: []].append(voter)
        }
        let rows: [VoteRow] = grouped.map { move, voters in
            let names = voters.map { office.name($0) }.sorted().joined(separator: ", ")
            return VoteRow(id: "\(move.from)-\(move.to)-\(move.promotion?.rawValue ?? "")",
                           san: game.position.san(for: move), count: voters.count, names: names)
        }
        return rows.sorted { $0.count > $1.count }
    }

    private func votesPanel(_ game: ChessGameState, myColor: ChessColor) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if game.position.turn == myColor {
                Text(game.votes[office.myID] == nil
                     ? "Jamoangiz uchun yurish tanlang — bu sizning ovozingiz."
                     : "Ovoz berdingiz. Boshqa yurishni bossangiz, ovoz o‘zgaradi.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                ForEach(voteRows(game)) { row in
                    HStack {
                        Text(row.san)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        Text("· \(row.count) ovoz")
                            .font(.system(size: 12))
                        Text(row.names)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } else {
                Text("Raqib jamoa o‘ylamoqda…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Tugmalar va yozuv

    @ViewBuilder
    private func controls(_ game: ChessGameState, myColor: ChessColor?) -> some View {
        if game.result == nil, let myColor, game.mode != .team {
            HStack {
                if game.drawOffer == myColor.opposite {
                    Button("🤝 Durangni qabul qilish") { office.chessDraw(game.id) }
                        .buttonStyle(.glassProminent)
                } else if game.drawOffer == myColor {
                    Text("Durang taklif qilindi")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    Button("Durang taklif qilish") { office.chessDraw(game.id) }
                        .buttonStyle(.glass)
                }
                Spacer()
                Button("Taslim bo‘lish") { confirmResign = true }
                    .buttonStyle(.glass)
            }
            .alert("Taslim bo‘lasizmi?", isPresented: $confirmResign) {
                Button("Taslim bo‘lish", role: .destructive) { office.chessResign(game.id) }
                Button("Bekor", role: .cancel) {}
            } message: {
                Text("Partiya raqibingiz g‘alabasi bilan tugaydi.")
            }
        } else if myColor == nil {
            Text("👀 Siz kuzatayapsiz")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private func movesText(_ sans: [String]) -> String {
        var parts: [String] = []
        var index = 0
        while index < sans.count {
            var pair = "\(index / 2 + 1). \(sans[index])"
            if index + 1 < sans.count {
                pair += " \(sans[index + 1])"
            }
            parts.append(pair)
            index += 2
        }
        return parts.joined(separator: "   ")
    }

    private func moveList(_ game: ChessGameState) -> some View {
        let text = movesText(game.sans)
        return ScrollView {
            Text(text.isEmpty ? "Hali yurish yo‘q" : text)
                .font(.system(size: 12, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(height: 64)
    }

    private func resultText(_ game: ChessGameState, result: ChessResult) -> String {
        guard let winner = result.winner else {
            return "🤝 Durang — \(result.reason.title)"
        }
        if game.color(of: office.myID) == winner {
            return "🏆 Siz yutdingiz — \(result.reason.title)"
        }
        let who: String
        if game.mode == .team {
            who = winner == .white ? "Ko‘klar" : "Qizillar"
        } else {
            who = game.players(winner).first.map { office.name($0) } ?? winner.title
        }
        return "🏁 \(who) yutdi — \(result.reason.title)"
    }

    // MARK: Bosish

    private func targets(_ game: ChessGameState) -> Set<Int> {
        guard let from = model.selectedSquare else { return [] }
        let moves = game.position.legalMoves().filter { $0.from == from }
        return Set(moves.map { $0.to })
    }

    private func tap(_ square: Int, game: ChessGameState) {
        guard game.result == nil, let myColor = game.color(of: office.myID), game.position.turn == myColor else {
            model.selectedSquare = nil
            return
        }
        if game.mode == .team && Date().timeIntervalSince1970 < game.turnStartedAt {
            return
        }
        let legal = game.position.legalMoves()
        if let from = model.selectedSquare {
            let candidates = legal.filter { $0.from == from && $0.to == square }
            if candidates.count > 1 {
                model.promotionMove = ChessMove(from: from, to: square)
                model.selectedSquare = nil
                return
            }
            if let move = candidates.first {
                office.chessMove(game.id, move)
                model.selectedSquare = nil
                return
            }
        }
        if let piece = game.position.board[square], piece.color == myColor, legal.contains(where: { $0.from == square }) {
            model.selectedSquare = square
        } else {
            model.selectedSquare = nil
        }
    }

    private var promotionBinding: Binding<Bool> {
        Binding(
            get: { model.promotionMove != nil },
            set: { shown in
                if !shown { model.promotionMove = nil }
            }
        )
    }

    private func promote(to kind: ChessPieceKind) {
        guard let pending = model.promotionMove, let id = game?.id else { return }
        office.chessMove(id, ChessMove(from: pending.from, to: pending.to, promotion: kind))
        model.promotionMove = nil
    }
}

// MARK: - Doska

struct ChessBoardView: View {
    let state: ChessGameState
    let flipped: Bool
    let selected: Int?
    let targets: Set<Int>
    let myVote: ChessMove?
    let season: SeasonKind
    let onTap: (Int) -> Void
    private let squareSize: CGFloat = 52

    var body: some View {
        let turn = state.position.turn
        let checkSquare: Int? = state.position.isInCheck(turn) ? state.position.kingSquare(turn) : nil
        let last: ChessMove? = state.moves.last
        let colors = palette
        VStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { column in
                        let square = index(row: row, column: column)
                        ChessSquareView(square: square, piece: state.position.board[square], size: squareSize,
                                        light: colors.light, dark: colors.dark,
                                        isSelected: selected == square,
                                        isTarget: targets.contains(square),
                                        isLastMove: last?.from == square || last?.to == square,
                                        isCheck: checkSquare == square,
                                        isVote: myVote?.from == square || myVote?.to == square,
                                        showFile: row == 7, showRank: column == 0)
                            .onTapGesture { onTap(square) }
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.black.opacity(0.25), lineWidth: 1))
    }

    private func index(row: Int, column: Int) -> Int {
        let rank: Int = flipped ? row : 7 - row
        let file: Int = flipped ? 7 - column : column
        return rank * 8 + file
    }

    /// Doska ranglari faslga qarab: qishda muzday, bahorda yashil, yozda qum, kuzda yong‘oq.
    private var palette: (light: Color, dark: Color) {
        switch season {
        case .winter:
            return (Color(red: 0.87, green: 0.91, blue: 0.95), Color(red: 0.49, green: 0.61, blue: 0.72))
        case .spring:
            return (Color(red: 0.93, green: 0.95, blue: 0.84), Color(red: 0.47, green: 0.64, blue: 0.40))
        case .summer:
            return (Color(red: 0.98, green: 0.92, blue: 0.79), Color(red: 0.83, green: 0.58, blue: 0.35))
        case .autumn:
            return (Color(red: 0.94, green: 0.87, blue: 0.75), Color(red: 0.62, green: 0.42, blue: 0.27))
        }
    }
}

struct ChessSquareView: View {
    let square: Int
    let piece: ChessPiece?
    let size: CGFloat
    let light: Color
    let dark: Color
    let isSelected: Bool
    let isTarget: Bool
    let isLastMove: Bool
    let isCheck: Bool
    let isVote: Bool
    let showFile: Bool
    let showRank: Bool

    var body: some View {
        let isLight = ChessSquare.isLight(square)
        let labelColor: Color = isLight ? dark : light
        ZStack {
            Rectangle().fill(isLight ? light : dark)
            if isLastMove {
                Rectangle().fill(Color.yellow.opacity(0.3))
            }
            if isVote {
                Rectangle().fill(Color.blue.opacity(0.22))
            }
            if isSelected {
                Rectangle().fill(Color.accentColor.opacity(0.38))
            }
            if isCheck {
                RadialGradient(colors: [Color.red.opacity(0.8), Color.red.opacity(0)], center: .center,
                               startRadius: 2, endRadius: size * 0.62)
            }
            if let piece {
                ChessPieceGlyph(piece: piece, size: size)
            }
            if isTarget {
                if piece == nil {
                    Circle()
                        .fill(Color.black.opacity(0.22))
                        .frame(width: size * 0.28, height: size * 0.28)
                } else {
                    Circle()
                        .stroke(Color.black.opacity(0.32), lineWidth: 4)
                        .frame(width: size * 0.88, height: size * 0.88)
                }
            }
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) {
            if showFile {
                Text(ChessSquare.fileLetter(square))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(labelColor)
                    .padding(2)
            }
        }
        .overlay(alignment: .topLeading) {
            if showRank {
                Text(String(ChessSquare.rank(square) + 1))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(labelColor)
                    .padding(2)
            }
        }
        .contentShape(Rectangle())
    }
}

/// Figura — tizim shriftidagi shaxmat belgisi. Ikkala rang uchun ham to‘la shakl olinadi
/// va oq/qora bo‘yaladi; U+FE0E — emoji emas, oddiy belgi ko‘rinishida chizilsin.
struct ChessPieceGlyph: View {
    let piece: ChessPiece
    let size: CGFloat

    private var symbol: String {
        let base: String
        switch piece.kind {
        case .king: base = "\u{265A}"
        case .queen: base = "\u{265B}"
        case .rook: base = "\u{265C}"
        case .bishop: base = "\u{265D}"
        case .knight: base = "\u{265E}"
        case .pawn: base = "\u{265F}"
        }
        return base + "\u{FE0E}"
    }

    var body: some View {
        let isWhite = piece.color == .white
        let fill: Color = isWhite ? Color.white : Color(white: 0.12)
        let edge: Color = isWhite ? Color.black.opacity(0.85) : Color.white.opacity(0.35)
        Text(symbol)
            .font(.system(size: size * 0.78))
            .foregroundStyle(fill)
            .shadow(color: edge, radius: 0, x: 0.9, y: 0.9)
            .shadow(color: edge, radius: 0, x: -0.9, y: -0.9)
            .shadow(color: edge, radius: 0, x: 0.9, y: -0.9)
            .shadow(color: edge, radius: 0, x: -0.9, y: 0.9)
    }
}
