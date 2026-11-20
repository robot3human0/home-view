import Foundation

// Shaxmat qoidalari — ilova ham, server ham aynan shu kodni ishlatadi:
// ilova qonuniy yurishlarni ko‘rsatadi, server har bir yurishni shu qoidalar bilan tekshiradi.
//
// Kataklar 0...63: indeks = qator * 8 + ustun. 0 — a1, 7 — h1, 56 — a8, 63 — h8.

public enum ChessColor: String, Codable {
    case white, black

    public var opposite: ChessColor {
        self == .white ? .black : .white
    }

    public var title: String {
        self == .white ? "Oqlar" : "Qoralar"
    }
}

public enum ChessPieceKind: String, Codable, CaseIterable {
    case king, queen, rook, bishop, knight, pawn

    /// Xalqaro yozuvdagi harf (piyoda — harfsiz).
    public var letter: String {
        switch self {
        case .king: return "K"
        case .queen: return "Q"
        case .rook: return "R"
        case .bishop: return "B"
        case .knight: return "N"
        case .pawn: return ""
        }
    }

    public var title: String {
        switch self {
        case .king: return "Shoh"
        case .queen: return "Farzin"
        case .rook: return "Ruh"
        case .bishop: return "Fil"
        case .knight: return "Ot"
        case .pawn: return "Piyoda"
        }
    }
}

public struct ChessPiece: Codable, Equatable, Hashable {
    public let color: ChessColor
    public let kind: ChessPieceKind

    public init(_ color: ChessColor, _ kind: ChessPieceKind) {
        self.color = color
        self.kind = kind
    }
}

public struct ChessMove: Codable, Equatable, Hashable {
    public let from: Int
    public let to: Int
    public let promotion: ChessPieceKind?

    public init(from: Int, to: Int, promotion: ChessPieceKind? = nil) {
        self.from = from
        self.to = to
        self.promotion = promotion
    }
}

public enum ChessOutcomeReason: String, Codable {
    case checkmate, stalemate, timeout, resignation, agreement, repetition, fiftyMoves, insufficientMaterial, abandoned

    public var title: String {
        switch self {
        case .checkmate: return "mot"
        case .stalemate: return "pat"
        case .timeout: return "vaqt tugadi"
        case .resignation: return "taslim bo‘ldi"
        case .agreement: return "kelishilgan durang"
        case .repetition: return "uch marta takrorlandi"
        case .fiftyMoves: return "50 yurish qoidasi"
        case .insufficientMaterial: return "mot qilishga kuch yetmaydi"
        case .abandoned: return "o‘yin tark etildi"
        }
    }
}

public struct ChessResult: Codable, Equatable {
    /// nil — durang.
    public var winner: ChessColor?
    public var reason: ChessOutcomeReason

    public init(winner: ChessColor?, reason: ChessOutcomeReason) {
        self.winner = winner
        self.reason = reason
    }
}

// MARK: - Kataklar

public enum ChessSquare {
    private static let files: [String] = ["a", "b", "c", "d", "e", "f", "g", "h"]

    public static func file(_ square: Int) -> Int { square % 8 }
    public static func rank(_ square: Int) -> Int { square / 8 }

    /// Doskadan tashqarida bo‘lsa — nil.
    public static func at(file: Int, rank: Int) -> Int? {
        guard file >= 0, file < 8, rank >= 0, rank < 8 else { return nil }
        return rank * 8 + file
    }

    public static func name(_ square: Int) -> String {
        files[file(square)] + String(rank(square) + 1)
    }

    public static func fileLetter(_ square: Int) -> String {
        files[file(square)]
    }

    public static func isLight(_ square: Int) -> Bool {
        (file(square) + rank(square)) % 2 == 1
    }
}

// MARK: - Pozitsiya

public struct ChessPosition: Codable, Equatable {
    public var board: [ChessPiece?]
    public var turn: ChessColor
    public var castleWhiteKing: Bool
    public var castleWhiteQueen: Bool
    public var castleBlackKing: Bool
    public var castleBlackQueen: Bool
    public var enPassant: Int?
    public var halfmoveClock: Int
    public var fullmoveNumber: Int

    public static var initial: ChessPosition {
        var board = [ChessPiece?](repeating: nil, count: 64)
        let back: [ChessPieceKind] = [.rook, .knight, .bishop, .queen, .king, .bishop, .knight, .rook]
        for file in 0..<8 {
            board[file] = ChessPiece(.white, back[file])
            board[8 + file] = ChessPiece(.white, .pawn)
            board[48 + file] = ChessPiece(.black, .pawn)
            board[56 + file] = ChessPiece(.black, back[file])
        }
        return ChessPosition(board: board, turn: .white,
                             castleWhiteKing: true, castleWhiteQueen: true,
                             castleBlackKing: true, castleBlackQueen: true,
                             enPassant: nil, halfmoveClock: 0, fullmoveNumber: 1)
    }

    private static let knightSteps: [(Int, Int)] = [(1, 2), (2, 1), (-1, 2), (-2, 1), (1, -2), (2, -1), (-1, -2), (-2, -1)]
    private static let kingSteps: [(Int, Int)] = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)]
    private static let straight: [(Int, Int)] = [(1, 0), (-1, 0), (0, 1), (0, -1)]
    private static let diagonal: [(Int, Int)] = [(1, 1), (1, -1), (-1, 1), (-1, -1)]
    private static let promotions: [ChessPieceKind] = [.queen, .rook, .bishop, .knight]

    // MARK: Hujum ostidami

    public func kingSquare(_ color: ChessColor) -> Int? {
        board.firstIndex { $0 == ChessPiece(color, .king) }
    }

    public func isInCheck(_ color: ChessColor) -> Bool {
        guard let king = kingSquare(color) else { return false }
        return isAttacked(king, by: color.opposite)
    }

    /// `square` katagini `color` rangidagi biror figura urib turibdimi?
    public func isAttacked(_ square: Int, by color: ChessColor) -> Bool {
        let file = ChessSquare.file(square)
        let rank = ChessSquare.rank(square)

        // Piyodalar
        let pawnRank: Int = color == .white ? rank - 1 : rank + 1
        for df in [-1, 1] {
            if let from = ChessSquare.at(file: file + df, rank: pawnRank), board[from] == ChessPiece(color, .pawn) {
                return true
            }
        }
        // Otlar
        for step in ChessPosition.knightSteps {
            if let from = ChessSquare.at(file: file + step.0, rank: rank + step.1), board[from] == ChessPiece(color, .knight) {
                return true
            }
        }
        // Shoh
        for step in ChessPosition.kingSteps {
            if let from = ChessSquare.at(file: file + step.0, rank: rank + step.1), board[from] == ChessPiece(color, .king) {
                return true
            }
        }
        // Ruh va farzin (to‘g‘ri chiziq)
        if rayHits(file: file, rank: rank, directions: ChessPosition.straight, color: color, kinds: [.rook, .queen]) {
            return true
        }
        // Fil va farzin (diagonal)
        return rayHits(file: file, rank: rank, directions: ChessPosition.diagonal, color: color, kinds: [.bishop, .queen])
    }

    private func rayHits(file: Int, rank: Int, directions: [(Int, Int)], color: ChessColor, kinds: [ChessPieceKind]) -> Bool {
        for direction in directions {
            var f = file + direction.0
            var r = rank + direction.1
            while let square = ChessSquare.at(file: f, rank: r) {
                if let piece = board[square] {
                    if piece.color == color && kinds.contains(piece.kind) {
                        return true
                    }
                    break
                }
                f += direction.0
                r += direction.1
            }
        }
        return false
    }

    // MARK: Yurishlar

    /// Qonuniy yurishlar (o‘z shohini xavf ostida qoldiradiganlari olib tashlangan).
    public func legalMoves() -> [ChessMove] {
        let mover = turn
        return pseudoMoves().filter { move in
            !applying(move).isInCheck(mover)
        }
    }

    public func isLegal(_ move: ChessMove) -> Bool {
        legalMoves().contains(normalized(move))
    }

    /// Oxirgi qatorga yetgan piyoda uchun figura aytilmagan bo‘lsa — farzin.
    public func normalized(_ move: ChessMove) -> ChessMove {
        guard move.promotion == nil, let piece = board[move.from], piece.kind == .pawn else { return move }
        let lastRank: Int = piece.color == .white ? 7 : 0
        guard ChessSquare.rank(move.to) == lastRank else { return move }
        return ChessMove(from: move.from, to: move.to, promotion: .queen)
    }

    private func pseudoMoves() -> [ChessMove] {
        var moves: [ChessMove] = []
        for from in 0..<64 {
            guard let piece = board[from], piece.color == turn else { continue }
            switch piece.kind {
            case .pawn:
                addPawnMoves(from: from, color: piece.color, into: &moves)
            case .knight:
                addSteps(from: from, steps: ChessPosition.knightSteps, into: &moves)
            case .king:
                addSteps(from: from, steps: ChessPosition.kingSteps, into: &moves)
                addCastling(into: &moves)
            case .bishop:
                addSlides(from: from, directions: ChessPosition.diagonal, into: &moves)
            case .rook:
                addSlides(from: from, directions: ChessPosition.straight, into: &moves)
            case .queen:
                addSlides(from: from, directions: ChessPosition.diagonal, into: &moves)
                addSlides(from: from, directions: ChessPosition.straight, into: &moves)
            }
        }
        return moves
    }

    private func addPawnMoves(from: Int, color: ChessColor, into moves: inout [ChessMove]) {
        let file = ChessSquare.file(from)
        let rank = ChessSquare.rank(from)
        let direction: Int = color == .white ? 1 : -1
        let startRank: Int = color == .white ? 1 : 6
        let lastRank: Int = color == .white ? 7 : 0

        func add(_ to: Int) {
            if ChessSquare.rank(to) == lastRank {
                for kind in ChessPosition.promotions {
                    moves.append(ChessMove(from: from, to: to, promotion: kind))
                }
            } else {
                moves.append(ChessMove(from: from, to: to))
            }
        }

        if let one = ChessSquare.at(file: file, rank: rank + direction), board[one] == nil {
            add(one)
            if rank == startRank, let two = ChessSquare.at(file: file, rank: rank + 2 * direction), board[two] == nil {
                moves.append(ChessMove(from: from, to: two))
            }
        }
        for df in [-1, 1] {
            guard let target = ChessSquare.at(file: file + df, rank: rank + direction) else { continue }
            if let piece = board[target], piece.color != color {
                add(target)
            } else if target == enPassant {
                moves.append(ChessMove(from: from, to: target))
            }
        }
    }

    private func addSteps(from: Int, steps: [(Int, Int)], into moves: inout [ChessMove]) {
        let file = ChessSquare.file(from)
        let rank = ChessSquare.rank(from)
        for step in steps {
            guard let to = ChessSquare.at(file: file + step.0, rank: rank + step.1) else { continue }
            if let piece = board[to], piece.color == turn { continue }
            moves.append(ChessMove(from: from, to: to))
        }
    }

    private func addSlides(from: Int, directions: [(Int, Int)], into moves: inout [ChessMove]) {
        let file = ChessSquare.file(from)
        let rank = ChessSquare.rank(from)
        for direction in directions {
            var f = file + direction.0
            var r = rank + direction.1
            while let to = ChessSquare.at(file: f, rank: r) {
                if let piece = board[to] {
                    if piece.color != turn {
                        moves.append(ChessMove(from: from, to: to))
                    }
                    break
                }
                moves.append(ChessMove(from: from, to: to))
                f += direction.0
                r += direction.1
            }
        }
    }

    private func addCastling(into moves: inout [ChessMove]) {
        let enemy = turn.opposite
        if turn == .white {
            guard board[4] == ChessPiece(.white, .king), !isAttacked(4, by: enemy) else { return }
            if castleWhiteKing, board[5] == nil, board[6] == nil, board[7] == ChessPiece(.white, .rook),
               !isAttacked(5, by: enemy), !isAttacked(6, by: enemy) {
                moves.append(ChessMove(from: 4, to: 6))
            }
            if castleWhiteQueen, board[1] == nil, board[2] == nil, board[3] == nil, board[0] == ChessPiece(.white, .rook),
               !isAttacked(3, by: enemy), !isAttacked(2, by: enemy) {
                moves.append(ChessMove(from: 4, to: 2))
            }
        } else {
            guard board[60] == ChessPiece(.black, .king), !isAttacked(60, by: enemy) else { return }
            if castleBlackKing, board[61] == nil, board[62] == nil, board[63] == ChessPiece(.black, .rook),
               !isAttacked(61, by: enemy), !isAttacked(62, by: enemy) {
                moves.append(ChessMove(from: 60, to: 62))
            }
            if castleBlackQueen, board[57] == nil, board[58] == nil, board[59] == nil, board[56] == ChessPiece(.black, .rook),
               !isAttacked(59, by: enemy), !isAttacked(58, by: enemy) {
                moves.append(ChessMove(from: 60, to: 58))
            }
        }
    }

    // MARK: Yurishni bajarish

    public func applying(_ rawMove: ChessMove) -> ChessPosition {
        let move = normalized(rawMove)
        var next = self
        guard let piece = board[move.from] else { return next }
        var captured: Bool = board[move.to] != nil
        next.board[move.from] = nil

        // Yo‘l-yo‘lakay urish
        if piece.kind == .pawn, move.to == enPassant, board[move.to] == nil {
            let victim: Int = piece.color == .white ? move.to - 8 : move.to + 8
            next.board[victim] = nil
            captured = true
        }

        if piece.kind == .pawn, let promotion = move.promotion {
            next.board[move.to] = ChessPiece(piece.color, promotion)
        } else {
            next.board[move.to] = piece
        }

        // Rokirovka: ruh ham suriladi
        if piece.kind == .king && abs(move.to - move.from) == 2 {
            switch move.to {
            case 6:
                next.board[5] = next.board[7]
                next.board[7] = nil
            case 2:
                next.board[3] = next.board[0]
                next.board[0] = nil
            case 62:
                next.board[61] = next.board[63]
                next.board[63] = nil
            case 58:
                next.board[59] = next.board[56]
                next.board[56] = nil
            default:
                break
            }
        }

        // Rokirovka huquqlari
        if piece.kind == .king {
            if piece.color == .white {
                next.castleWhiteKing = false
                next.castleWhiteQueen = false
            } else {
                next.castleBlackKing = false
                next.castleBlackQueen = false
            }
        }
        for square in [move.from, move.to] {
            switch square {
            case 0: next.castleWhiteQueen = false
            case 7: next.castleWhiteKing = false
            case 56: next.castleBlackQueen = false
            case 63: next.castleBlackKing = false
            default: break
            }
        }

        next.enPassant = nil
        if piece.kind == .pawn && abs(move.to - move.from) == 16 {
            next.enPassant = (move.from + move.to) / 2
        }
        next.halfmoveClock = (piece.kind == .pawn || captured) ? 0 : halfmoveClock + 1
        if piece.color == .black {
            next.fullmoveNumber += 1
        }
        next.turn = turn.opposite
        return next
    }

    // MARK: O‘yin holati

    /// Pozitsiyaning o‘zidan kelib chiqadigan natija (mot, pat, kuch yetmasligi, 50 yurish). Davom etsa — nil.
    public func evaluate() -> ChessResult? {
        if legalMoves().isEmpty {
            if isInCheck(turn) {
                return ChessResult(winner: turn.opposite, reason: .checkmate)
            }
            return ChessResult(winner: nil, reason: .stalemate)
        }
        if hasInsufficientMaterial {
            return ChessResult(winner: nil, reason: .insufficientMaterial)
        }
        if halfmoveClock >= 100 {
            return ChessResult(winner: nil, reason: .fiftyMoves)
        }
        return nil
    }

    /// Ikkala tomonda ham mot qilishga kuch yo‘q.
    public var hasInsufficientMaterial: Bool {
        var minorSquares: [Int] = []
        var bishopsOnly = true
        for (square, piece) in board.enumerated() {
            guard let piece else { continue }
            switch piece.kind {
            case .king:
                continue
            case .bishop:
                minorSquares.append(square)
            case .knight:
                minorSquares.append(square)
                bishopsOnly = false
            default:
                return false
            }
        }
        if minorSquares.count <= 1 { return true }
        guard bishopsOnly else { return false }
        let shades = Set(minorSquares.map { ChessSquare.isLight($0) })
        return shades.count == 1
    }

    /// Shu rangda mot qilish uchun yetarli kuch bormi (vaqt tugaganda durangni aniqlash uchun).
    public func hasMatingMaterial(_ color: ChessColor) -> Bool {
        var minors = 0
        for piece in board {
            guard let piece, piece.color == color else { continue }
            switch piece.kind {
            case .pawn, .rook, .queen: return true
            case .bishop, .knight: minors += 1
            case .king: continue
            }
        }
        return minors >= 2
    }

    /// Takrorlanishni sanash uchun pozitsiya "barmoq izi".
    public var repetitionKey: String {
        var key = ""
        for piece in board {
            if let piece {
                let letter = piece.kind == .pawn ? "P" : piece.kind.letter
                key += piece.color == .white ? letter : letter.lowercased()
            } else {
                key += "."
            }
        }
        key += turn == .white ? "w" : "b"
        key += castleWhiteKing ? "K" : "-"
        key += castleWhiteQueen ? "Q" : "-"
        key += castleBlackKing ? "k" : "-"
        key += castleBlackQueen ? "q" : "-"
        if let enPassant, legalMoves().contains(where: { $0.to == enPassant && board[$0.from]?.kind == .pawn }) {
            key += String(enPassant)
        }
        return key
    }

    // MARK: Yozuv (SAN): e4, Nf3, exd5, O-O, e8=Q+, Qh5#

    public func san(for rawMove: ChessMove) -> String {
        let move = normalized(rawMove)
        guard let piece = board[move.from] else { return "?" }
        var text = ""
        if piece.kind == .king && abs(move.to - move.from) == 2 {
            text = move.to > move.from ? "O-O" : "O-O-O"
        } else {
            let isCapture: Bool = board[move.to] != nil || (piece.kind == .pawn && move.to == enPassant)
            if piece.kind == .pawn {
                if isCapture {
                    text += ChessSquare.fileLetter(move.from)
                }
            } else {
                text += piece.kind.letter
                let rivals = legalMoves().filter { other in
                    other.to == move.to && other.from != move.from && board[other.from] == piece
                }
                if !rivals.isEmpty {
                    let sameFile = rivals.contains { ChessSquare.file($0.from) == ChessSquare.file(move.from) }
                    let sameRank = rivals.contains { ChessSquare.rank($0.from) == ChessSquare.rank(move.from) }
                    if !sameFile {
                        text += ChessSquare.fileLetter(move.from)
                    } else if !sameRank {
                        text += String(ChessSquare.rank(move.from) + 1)
                    } else {
                        text += ChessSquare.name(move.from)
                    }
                }
            }
            if isCapture {
                text += "x"
            }
            text += ChessSquare.name(move.to)
            if let promotion = move.promotion {
                text += "=" + promotion.letter
            }
        }
        let next = applying(move)
        if next.isInCheck(next.turn) {
            text += next.legalMoves().isEmpty ? "#" : "+"
        }
        return text
    }
}

// MARK: - Tarmoq o‘yini

public enum ChessMode: String, Codable, CaseIterable {
    /// 5 daqiqa + har yurishga 3 soniya, jonli.
    case blitz
    /// Har yurishga 24 soatgacha — bo‘sh paytda.
    case daily
    /// Jamoa ovoz berib yuradi, har yurishga 60 soniya.
    case team

    public var title: String {
        switch self {
        case .blitz: return "Blits"
        case .daily: return "Kunlik"
        case .team: return "Jamoaviy"
        }
    }

    public var emoji: String {
        switch self {
        case .blitz: return "⚡"
        case .daily: return "📅"
        case .team: return "👥"
        }
    }

    /// Boshlang‘ich vaqt (sekund). Kunlik va jamoaviyda — bir yurish uchun.
    public var clock: Double {
        switch self {
        case .blitz: return 300
        case .daily: return 86_400
        case .team: return 60
        }
    }

    public var increment: Double {
        self == .blitz ? 3 : 0
    }
}

/// Bitta partiyaning to‘liq holati — server har o‘zgarishda ishtirokchilar va tomoshabinlarga yuboradi.
public struct ChessGameState: Codable, Equatable {
    public var id: String
    public var mode: ChessMode
    /// Oqlar (jamoaviyda — Ko‘klar jamoasi).
    public var white: [String]
    /// Qoralar (jamoaviyda — Qizillar jamoasi).
    public var black: [String]
    public var position: ChessPosition
    public var moves: [ChessMove]
    public var sans: [String]
    /// Navbat boshlangan paytdagi qolgan vaqt (sekund).
    public var whiteTime: Double
    public var blackTime: Double
    /// Navbat qachon boshlangan (Unix vaqt).
    public var turnStartedAt: Double
    public var result: ChessResult?
    /// Kim durang taklif qilgan.
    public var drawOffer: ChessColor?
    /// Jamoaviyda: ko‘ruvchining jamoasi ovozlari (raqib ovozlari ko‘rsatilmaydi).
    public var votes: [String: ChessMove]
    public var updatedAt: Double

    public init(id: String, mode: ChessMode, white: [String], black: [String], position: ChessPosition,
                moves: [ChessMove], sans: [String], whiteTime: Double, blackTime: Double, turnStartedAt: Double,
                result: ChessResult?, drawOffer: ChessColor?, votes: [String: ChessMove], updatedAt: Double) {
        self.id = id
        self.mode = mode
        self.white = white
        self.black = black
        self.position = position
        self.moves = moves
        self.sans = sans
        self.whiteTime = whiteTime
        self.blackTime = blackTime
        self.turnStartedAt = turnStartedAt
        self.result = result
        self.drawOffer = drawOffer
        self.votes = votes
        self.updatedAt = updatedAt
    }

    public func color(of id: String) -> ChessColor? {
        if white.contains(id) { return .white }
        if black.contains(id) { return .black }
        return nil
    }

    public func players(_ color: ChessColor) -> [String] {
        color == .white ? white : black
    }

    /// Hozirgi paytda qolgan vaqt.
    public func remaining(_ color: ChessColor, now: Double) -> Double {
        let base: Double = color == .white ? whiteTime : blackTime
        guard result == nil, position.turn == color else { return base }
        return max(0, base - (now - turnStartedAt))
    }
}

/// Jonli partiyalar ro‘yxati (odamcha bayroqchasi va "kuzatish" uchun).
public struct ChessSummary: Codable, Equatable {
    public var id: String
    public var mode: ChessMode
    public var white: [String]
    public var black: [String]

    public init(id: String, mode: ChessMode, white: [String], black: [String]) {
        self.id = id
        self.mode = mode
        self.white = white
        self.black = black
    }
}
