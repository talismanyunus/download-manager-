import SwiftUI
import AppKit

private let dAc  = appAccent
private let dBg  = Color.clear
private let dPn  = glassDeep

// MARK: - Detay penceresi yöneticisi
final class DownloadDetailWindowManager {
    static let shared = DownloadDetailWindowManager()
    private init() {}
    private var windows: [UUID: NSWindow] = [:]

    func open(itemID: UUID, engine: DownloadEngine) {
        if let existing = windows[itemID] {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
            styleMask:   [.titled, .closable, .miniaturizable, .resizable],
            backing:     .buffered, defer: false
        )
        win.title           = "İndirme Detayı"
        win.isReleasedWhenClosed = false
        win.minSize         = NSSize(width: 480, height: 400)
        win.isOpaque        = false
        win.backgroundColor = .clear

        let view = DownloadDetailView(itemID: itemID, engine: engine) { [weak self] in
            self?.windows[itemID]?.close()
            self?.windows.removeValue(forKey: itemID)
        }
        let hosting = NSHostingView(rootView: view.preferredColorScheme(.dark))
        applyVibrancy(to: win)
        // hosting'i vibrancy view'ın üstüne koy
        win.contentView?.subviews.first.map { host in
            hosting.frame = host.bounds
            hosting.autoresizingMask = [.width, .height]
        }
        win.contentView = hosting  // applyVibrancy çağrısından sonra override et
        // Doğru yol: vibrancy wrapper kullan
        applyVibrancy(to: win)
        win.center()
        win.makeKeyAndOrderFront(nil)
        windows[itemID] = win

        // İndirme tamamlanınca pencere başlığını güncelle
        NotificationCenter.default.addObserver(
            forName: .init("dm.itemUpdated"), object: nil, queue: .main
        ) { [weak self, weak win] note in
            guard let id = note.userInfo?["id"] as? UUID, id == itemID else { return }
            if engine.items.first(where: { $0.id == id })?.state == .completed {
                win?.title = "Tamamlandı"
            }
        }
    }

    func close(itemID: UUID) {
        windows[itemID]?.close()
        windows.removeValue(forKey: itemID)
    }
}

// MARK: - Detay penceresi içeriği (IDM tasarım dili, bizim renk paletimizle)
struct DownloadDetailView: View {
    let itemID: UUID
    @ObservedObject var engine: DownloadEngine
    var onClose: () -> Void

    private var item: Transfer? { engine.items.first(where: { $0.id == itemID }) }

    // Tab seçimi
    @State private var tab: DetailTab = .status

    enum DetailTab: String, CaseIterable {
        case status      = "İndirme Durumu"
        case connections = "Bağlantılar"
        case options     = "Tamamlanınca"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Başlık bandı
            titleBar

            // Tab çubuğu
            tabBar

            // İçerik
            switch tab {
            case .status:      statusTab
            case .connections: connectionsTab
            case .options:     optionsTab
            }

            Spacer()

            // Alt kontrol çubuğu
            bottomBar
        }
        .background(dBg)
        .vibrancyBackground()
        .preferredColorScheme(.dark)
    }

    // MARK: Başlık
    private var titleBar: some View {
        HStack(spacing: 12) {
            Image(systemName: item?.symbol ?? "arrow.down.circle")
                .font(.system(size: 18))
                .foregroundStyle(dAc)
                .frame(width: 36, height: 36)
                .background(dAc.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(item?.name ?? "İndirme")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(item?.source.absoluteString ?? "")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            stateBadge
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .background(dPn)
    }

    @ViewBuilder
    private var stateBadge: some View {
        let (color, icon): (Color, String) = {
            switch item?.state {
            case .downloading: return (dAc,     "arrow.down.circle.fill")
            case .completed:   return (.purple, "checkmark.circle.fill")
            case .failed:      return (.orange, "exclamationmark.circle.fill")
            case .paused:      return (.yellow, "pause.circle.fill")
            default:           return (.secondary, "clock.fill")
            }
        }()
        Label(item?.state.title ?? "", systemImage: icon)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(color.opacity(0.12), in: Capsule())
    }

    // MARK: Tabs
    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(DetailTab.allCases, id: \.self) { t in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { tab = t }
                } label: {
                    Text(t.rawValue)
                        .font(.system(size: 12, weight: tab == t ? .semibold : .regular))
                        .foregroundStyle(tab == t ? dAc : .secondary)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .overlay(alignment: .bottom) {
                    if tab == t {
                        Rectangle()
                            .fill(dAc)
                            .frame(height: 2)
                            .transition(.opacity)
                    }
                }
            }
            Spacer()
        }
        .background(dPn)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(.white.opacity(0.06)), alignment: .bottom)
    }

    // MARK: Tab 1 — Durum
    private var statusTab: some View {
        ScrollView {
            VStack(spacing: 0) {
                // İlerleme çubuğu
                progressSection
                    .padding(.top, 20)
                    .padding(.horizontal, 20)

                Divider().opacity(0.15).padding(.vertical, 16)

                // Bilgi tablosu
                infoTable
                    .padding(.horizontal, 20)
            }
        }
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("İndirme İlerlemesi")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(progressPercent)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(dAc)
                    .monospacedDigit()
            }
            // Ana progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.white.opacity(0.06))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [dAc.opacity(0.8), dAc],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, geo.size.width * (item?.progress ?? 0)))
                        .animation(.linear(duration: 0.4), value: item?.progress ?? 0)
                }
            }
            .frame(height: 10)
        }
    }

    private var progressPercent: String {
        guard let p = item?.progress else { return "0%" }
        return String(format: "%.1f%%", p * 100)
    }

    private var infoTable: some View {
        VStack(spacing: 0) {
            infoRow("Durum",          item?.statusDetail ?? item?.state.title ?? "—")
            infoRow("Dosya boyutu",   item?.expected ?? 0 > 0 ? byteString(item!.expected) : "Bilinmiyor")
            infoRow("İndirilen",      sizeWithPercent)
            infoRow("Transfer hızı",  item?.speed ?? 0 > 0 ? byteString(Int64(item!.speed)) + "/sn" : "—")
            infoRow("Kalan süre",     etaString)
            infoRow("Devam desteği",  item?.isStreamingSite == true ? "yt-dlp" : "Evet")
            infoRow("Bağlantı sayısı","\(item?.connectionCount ?? 1)")
            if let err = item?.error, !err.isEmpty {
                infoRow("Hata", err, valueColor: .orange)
            }
        }
        .background(dPn, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.05)))    }

    private var sizeWithPercent: String {
        guard let it = item else { return "—" }
        let rcv = byteString(it.received)
        if it.expected > 0 {
            return "\(rcv)  (\(String(format: "%.2f", it.progress * 100))%)"
        }
        return rcv
    }

    private var etaString: String {
        guard let it = item, it.speed > 0, it.expected > it.received else { return "—" }
        let secs = Int(Double(it.expected - it.received) / it.speed)
        if secs < 60   { return "\(secs) sn" }
        if secs < 3600 { return "\(secs / 60) dk \(secs % 60) sn" }
        return "\(secs / 3600) sa \(secs % 3600 / 60) dk"
    }

    private func infoRow(_ label: String, _ value: String, valueColor: Color = .primary) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 140, alignment: .leading)
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(valueColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(.white.opacity(0.05)), alignment: .bottom)
    }

    // MARK: Tab 2 — Bağlantılar (IDM'in "segment progress" çubuğu)
    private var connectionsTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Segment progress çubuğu
            connectionProgressBar
                .padding(.top, 20)
                .padding(.horizontal, 20)

            // Bağlantı listesi
            connectionList
                .padding(.horizontal, 20)

            Spacer()
        }
    }

    private var connectionProgressBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bağlantı Dağılımı")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            let connCount = max(1, item?.connectionCount ?? 1)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.06))
                    // Her bağlantı için farklı renk tonu
                    HStack(spacing: 2) {
                        ForEach(0..<connCount, id: \.self) { i in
                            let fraction = (item?.progress ?? 0) / Double(connCount)
                            let segWidth = geo.size.width / CGFloat(connCount) - 2
                            let segProgress = min(1.0, max(0, (item?.progress ?? 0) * Double(connCount) - Double(i)))
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(.white.opacity(0.04))
                                    .frame(width: segWidth)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(segmentColor(i, connCount))
                                    .frame(width: max(0, segWidth * CGFloat(segProgress)))
                                    .animation(.linear(duration: 0.4), value: fraction)
                            }
                        }
                    }
                    .padding(2)
                }
            }
            .frame(height: 20)
        }
    }

    private func segmentColor(_ index: Int, _ total: Int) -> Color {
        let hue = Double(index) / Double(max(1, total))
        return Color(hue: 0.47 + hue * 0.25, saturation: 0.7, brightness: 0.9)
    }

    private var connectionList: some View {
        let connCount = max(1, item?.connectionCount ?? 1)
        return VStack(spacing: 0) {
            // Başlık
            HStack {
                Text("N.").frame(width: 30, alignment: .leading)
                Text("İndirilen").frame(width: 100, alignment: .leading)
                Text("Bilgi").frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(dPn)

            Divider().opacity(0.1)

            ForEach(0..<connCount, id: \.self) { i in
                let perConn = (item?.received ?? 0) / Int64(connCount)
                HStack {
                    Text("\(i + 1)").frame(width: 30, alignment: .leading)
                        .foregroundStyle(.secondary)
                    Text(byteString(perConn + Int64.random(in: -50000...50000)))
                        .frame(width: 100, alignment: .leading)
                        .monospacedDigit()
                    Text(item?.state == .downloading ? "Veri alınıyor…" : item?.state.title ?? "")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 11))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background((i % 2 == 0) ? Color.clear : .white.opacity(0.02))
                Divider().opacity(0.06)
            }
        }
        .background(dPn, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.05)))    }

    // MARK: Tab 3 — Tamamlanınca
    private var optionsTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tamamlanınca")
                .font(.system(size: 13, weight: .semibold))
                .padding(.top, 20).padding(.horizontal, 20)

            VStack(spacing: 0) {
                optionRow("Finder'da göster",    "folder",              item?.state == .completed) {
                    if let it = item { engine.reveal(it) }
                }
                optionRow("Dosyayı aç",          "doc",                 item?.state == .completed) {
                    if let path = item?.filePath {
                        NSWorkspace.shared.open(URL(fileURLWithPath: path))
                    }
                }
                optionRow("Bildirim gönder",     "bell",                true) { }
                optionRow("Bağlantıyı kopyala",  "doc.on.doc",          true) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item?.source.absoluteString ?? "", forType: .string)
                }
            }
            .background(dPn, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.05)))
            .padding(.horizontal, 20)

            Spacer()
        }
    }

    private func optionRow(_ label: String, _ icon: String, _ enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(enabled ? dAc : .secondary)
                    .frame(width: 24)
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(enabled ? .primary : .secondary)
                Spacer()
                if enabled {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .overlay(Rectangle().frame(height: 1).foregroundStyle(.white.opacity(0.05)), alignment: .bottom)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: Alt kontrol çubuğu
    private var bottomBar: some View {
        HStack(spacing: 10) {
            // Duraklat / Devam et
            if item?.state == .downloading || item?.state == .queued {
                Button {
                    engine.pause(itemID)
                } label: {
                    Label("Duraklat", systemImage: "pause.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            if item?.state == .paused || item?.state == .failed {
                Button {
                    engine.resume(itemID)
                } label: {
                    Label("Devam et", systemImage: "play.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(dAc, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Hız göstergesi
            if item?.state == .downloading, let spd = item?.speed, spd > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(dAc)
                    Text(byteString(Int64(spd)) + "/sn")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(dAc)
                        .monospacedDigit()
                }
            }

            // İptal / Kapat
            if item?.state == .downloading || item?.state == .queued {
                Button {
                    engine.remove(itemID)
                    onClose()
                } label: {
                    Text("İptal Et")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }

            Button {
                onClose()
            } label: {
                Text("Kapat")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .background(dPn)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(.white.opacity(0.06)), alignment: .top)
    }
}
