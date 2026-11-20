import AppKit
import SwiftUI
import HomeViewProtocol

/// Hamkasblar ro‘yxati: kim ekraningizda yurishini o‘zingiz tanlaysiz.
final class PeopleWindowController {
    static let shared = PeopleWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: PeopleView(office: Office.shared))
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.title = "HomeView — hamkasblar"
            newWindow.styleMask = [.titled, .closable, .resizable]
            newWindow.setContentSize(NSSize(width: 440, height: 600))
            newWindow.isReleasedWhenClosed = false
            newWindow.center()
            window = newWindow
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

private enum PeopleFilter: String, CaseIterable, Identifiable {
    case all, online, shown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Hammasi"
        case .online: return "Onlayn"
        case .shown: return "Ekranda"
        }
    }
}

private struct TeamGroup: Identifiable {
    let id: String
    let rows: [Office.Colleague]
}

struct PeopleView: View {
    @ObservedObject var office: Office
    @State private var search = ""
    @State private var filter = PeopleFilter.all
    @State private var autoShowNew = Settings.shared.newPeersVisible

    private var rows: [Office.Colleague] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return office.colleagues.filter { row in
            let matches: Bool = query.isEmpty || row.name.lowercased().contains(query) || row.team.lowercased().contains(query)
            guard matches else { return false }
            switch filter {
            case .all: return true
            case .online: return row.status != nil
            case .shown: return row.shown
            }
        }
    }

    /// Jamoalar bo‘yicha: avval o‘z jamoangiz, keyin alifbo bo‘yicha, jamoasizlar oxirida.
    private var groups: [TeamGroup] {
        let myTeam = Settings.shared.team.lowercased()
        let grouped = Dictionary(grouping: rows) { row -> String in
            row.team.isEmpty ? "Jamoasiz" : row.team
        }
        let names: [String] = grouped.keys.sorted { a, b in
            let aMine = !myTeam.isEmpty && a.lowercased() == myTeam
            let bMine = !myTeam.isEmpty && b.lowercased() == myTeam
            if aMine != bMine { return aMine }
            if (a == "Jamoasiz") != (b == "Jamoasiz") { return b == "Jamoasiz" }
            return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
        }
        return names.map { TeamGroup(id: $0, rows: grouped[$0] ?? []) }
    }

    var body: some View {
        let everyone = office.colleagues
        let shownCount = everyone.filter { $0.shown }.count
        let onlineCount = everyone.filter { $0.status != nil }.count
        VStack(alignment: .leading, spacing: 10) {
            Text("Ekraningizda \(shownCount) / \(everyone.count) hamkasb · \(onlineCount) onlayn")
                .font(.headline)
            Text("Yoqilganlarning odamchasi ekraningizda yuradi. O‘chirilganlar bilan ham xabar yozish va o‘ynash mumkin — ular faqat ekraningizda yurmaydi.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                TextField("Qidirish: ism yoki jamoa", text: $search)
                    .textFieldStyle(.roundedBorder)
                Picker("", selection: $filter) {
                    ForEach(PeopleFilter.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 210)
            }

            Toggle("Yangi qo‘shilganlar ekranimda avtomatik ko‘rinsin", isOn: $autoShowNew)
                .onChange(of: autoShowNew) { _, value in
                    Settings.shared.newPeersVisible = value
                }

            if everyone.isEmpty {
                emptyState
            } else if rows.isEmpty {
                Text("Hech kim topilmadi")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(groups) { group in
                        Section(group.id) {
                            ForEach(group.rows) { row in
                                PersonRow(row: row) { shown in
                                    office.setShown(row.id, shown)
                                }
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }

            HStack {
                Button("Ro‘yxatdagilarni yoqish") {
                    office.setShown(rows.map { $0.id }, true)
                }
                .buttonStyle(.glass)
                .disabled(rows.isEmpty)
                Button("Ro‘yxatdagilarni o‘chirish") {
                    office.setShown(rows.map { $0.id }, false)
                }
                .buttonStyle(.glass)
                .disabled(rows.isEmpty)
                Spacer()
            }
        }
        .padding(16)
        .frame(minWidth: 420, minHeight: 520)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("👥")
                .font(.system(size: 40))
            Text(office.isConnected ? "Hozircha hamkasblar yo‘q" : "Ofisga ulanmagan")
                .font(.headline)
            Text("Hamkasblar HomeView'ni o‘rnatib, ofisga ulanganda shu yerda paydo bo‘ladi.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PersonRow: View {
    let row: Office.Colleague
    let onChange: (Bool) -> Void

    private var dotColor: Color {
        switch row.status {
        case .some(.active): return .green
        case .some(.away): return .orange
        case .some(.busy): return .red
        case .some(.hidden), .none: return Color.secondary.opacity(0.5)
        }
    }

    private var subtitle: String {
        guard let status = row.status else { return "oflayn" }
        switch status {
        case .active: return "onlayn"
        case .away: return "uzoqda"
        case .busy: return "band"
        case .hidden: return "ko‘rinmas"
        }
    }

    var body: some View {
        let binding = Binding<Bool>(
            get: { row.shown },
            set: { onChange($0) }
        )
        Toggle(isOn: binding) {
            HStack(spacing: 8) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(row.status == nil ? Color.secondary : Color.primary)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .toggleStyle(.switch)
        .padding(.vertical, 2)
    }
}
