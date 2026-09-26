import SwiftUI
import AppKit

private let fAc  = appAccent
private let fBg  = Color.clear
private let fPn  = glassDeep
private let fBdr = glassBorder

// MARK: - IDM tarzı Float Kart
struct FloatCardView: View {
    let itemID: UUID
    @ObservedObject var engine: DownloadEngine
    var onDismiss: () -> Void

    @State private var minimized = false   // eksi → sadece başlık görünür

    private var item: Transfer? { engine.items.first(where: { $0.id == itemID }) }

    private var speedStr: String {
        guard let s = item?.speed, s > 0 else { return "0 B/sn" }
        return byteString(Int64(s)) + "/sn"
    }
    private var etaStr: String {
        guard let it = item, it.speed > 0, it.expected > it.received else { return "—" }
        let s = Int(Double(it.expected - it.received) / it.speed)
        if s < 60   { return "\(s) sn" }
        if s < 3600 { return "\(s/60) dk \(s%60) sn" }
        return "\(s/3600) sa \(s%3600/60) dk"
    }
    private var statusStr: String {
        switch item?.state {
        case .downloading:
            // statusDetail zaten temiz (parse edilmiş %) — boşsa "İndiriliyor"
            let d = item?.statusDetail ?? ""
            return d.isEmpty ? "İndiriliyor" : d
        case .completed:   return "Tamamlandı"
        case .paused:      return "Duraklatıldı"
        case .failed:      return item?.error.flatMap { String($0.prefix(60)) } ?? "Hata"
        case .queued:      return "Sırada"
        default:           return "—"
        }
    }
    private var tint: Color {
        switch item?.state {
        case .failed:    return .orange
        case .completed: return fAc
        default:         return fAc
        }
    }
    private var progress: Double { item?.progress ?? 0 }
    private var pct: String { String(format: "%.1f%%", progress * 100) }

    var body: some View {
        VStack(spacing: 0) {
            titleBar

            if !minimized {
                Divider().background(fBdr)
                progressSection
                Divider().background(fBdr)
                infoTable
                Divider().background(fBdr)
                bottomBar
            }
        }
        .background(
            VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(fBdr, lineWidth: 1))
        .shadow(color: .black.opacity(0.6), radius: 24, x: 0, y: 10)
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: minimized)
    }

    // MARK: Başlık
    private var titleBar: some View {
        HStack(spacing: 9) {
            Image(systemName: item?.symbol ?? "doc.fill")
                .font(.system(size: 13))
                .foregroundColor(fAc)
                .frame(width: 26, height: 26)
                .background(fAc.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))

            Text(item?.name ?? "İndiriliyor")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)

            Spacer()

            // Eksi (minimize)
            Button {
                withAnimation { minimized.toggle() }
                // Panel yüksekliğini güncelle
                if let id = item?.id {
                    FloatWindowManager.shared.resize(id: id, minimized: !minimized)
                }
            } label: {
                Image(systemName: minimized ? "chevron.up" : "minus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(width: 22, height: 22)
                    .background(.white.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .help(minimized ? "Genişlet" : "Küçült")

            // Detay penceresi
            Button {
                if let id = item?.id {
                    DownloadDetailWindowManager.shared.open(itemID: id, engine: engine)
                }
            } label: {
                Image(systemName: "arrow.up.forward.square")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(width: 22, height: 22)
                    .background(.white.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Detay penceresini aç")

            // Kapat
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(width: 22, height: 22)
                    .background(.white.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Kapat")
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(fPn)
    }

    // MARK: Progress bar
    private var progressSection: some View {
        VStack(spacing: 5) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(.white.opacity(0.07))
                    LinearGradient(
                        colors: [fAc.opacity(0.75), fAc],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: max(0, geo.size.width * progress))
                    .animation(.linear(duration: 0.4), value: progress)

                    if progress > 0.08 {
                        Text(pct)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.black.opacity(0.65))
                            .padding(.leading, 8)
                    }
                }
            }
            .frame(height: 22)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            if item?.state == .downloading, (item?.expected ?? 0) == 0 {
                ProgressView().progressViewStyle(.linear).tint(fAc).frame(height: 3)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    // MARK: Bilgi tablosu
    private var infoTable: some View {
        VStack(spacing: 0) {
            infoRow("Durum",         statusStr,    hi: true)
            infoRow("Dosya boyutu",  (item?.expected ?? 0) > 0 ? byteString(item!.expected) : "Bilinmiyor")
            infoRow("İndirilen",     "\(byteString(item?.received ?? 0))  (\(pct))")
            infoRow("Transfer hızı", speedStr,     hi: item?.state == .downloading)
            infoRow("Kalan süre",    etaStr)
        }
        .padding(.vertical, 2)
    }

    private func infoRow(_ label: String, _ value: String, hi: Bool = false) -> some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.42))
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(.system(size: 11, weight: hi ? .semibold : .regular, design: .rounded))
                .foregroundColor(hi ? fAc : .white.opacity(0.85))
                .lineLimit(1)
                .monospacedDigit()
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 5)
    }

    // MARK: Alt butonlar
    private var bottomBar: some View {
        HStack(spacing: 8) {
            if item?.state == .downloading || item?.state == .queued {
                Button { engine.pause(itemID) } label: {
                    Label("Duraklat", systemImage: "pause.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain)
            }
            if item?.state == .paused || item?.state == .failed {
                Button { engine.resume(itemID) } label: {
                    Label("Devam et", systemImage: "play.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(fAc, in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain)
            }
            if item?.state == .completed, let t = item {
                Button { engine.reveal(t) } label: {
                    Label("Klasörü Aç", systemImage: "folder.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(fAc, in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain)
            }

            Spacer()

            if [TransferState.downloading, .queued, .paused].contains(item?.state ?? .queued) {
                Button {
                    engine.remove(itemID)
                    onDismiss()
                } label: {
                    Text("İptal")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(fPn)
    }
}

// MARK: - FloatWindowManager
final class FloatWindowManager {
    static let shared = FloatWindowManager()
    private init() {}

    private struct Entry {
        let panel: NSPanel
        var autoCloseWorkItem: DispatchWorkItem?
        var minimized: Bool = false
    }

    private var entries: [UUID: Entry] = [:]
    private let margin:        CGFloat = 20
    let cardWidth:  CGFloat = 460        // daha geniş
    let cardHeight: CGFloat = 230
    let miniHeight: CGFloat = 52         // sadece başlık

    func show(itemID: UUID, engine: DownloadEngine) {
        guard entries[itemID] == nil else { return }

        let panel = makePanel(width: cardWidth, height: cardHeight)
        panel.identifier = NSUserInterfaceItemIdentifier("float-\(itemID)")

        let view = FloatCardView(itemID: itemID, engine: engine) { [weak self] in
            self?.dismiss(id: itemID)
        }
        panel.contentView = NSHostingView(rootView: view.preferredColorScheme(.dark))

        entries[itemID] = Entry(panel: panel, minimized: false)
        restack()
        panel.orderFront(nil)
    }

    /// Minimize/restore — panel frame'i güncelle
    func resize(id: UUID, minimized: Bool) {
        guard var entry = entries[id] else { return }
        entry.minimized = minimized
        entries[id] = entry
        restack()
    }

    func scheduleAutoClose(id: UUID, after seconds: Double = 5) {
        entries[id]?.autoCloseWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.dismiss(id: id) }
        entries[id]?.autoCloseWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func dismiss(id: UUID) {
        entries[id]?.autoCloseWorkItem?.cancel()
        entries[id]?.panel.close()
        entries.removeValue(forKey: id)
        restack()
    }

    func dismissAll() {
        for (_, e) in entries { e.autoCloseWorkItem?.cancel(); e.panel.close() }
        entries.removeAll()
    }

    private func restack() {
        guard let screen = NSScreen.main else { return }
        let rect = screen.visibleFrame
        let x    = rect.maxX - cardWidth - margin
        var yOffset = rect.minY + margin
        for (_, entry) in entries {
            let h = entry.minimized ? miniHeight : cardHeight
            entry.panel.setFrame(NSRect(x: x, y: yOffset, width: cardWidth, height: h),
                                 display: true, animate: true)
            yOffset += h + 10
        }
    }

    private func makePanel(width: CGFloat, height: CGFloat) -> NSPanel {
        let p = DraggablePanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask:   [.borderless, .nonactivatingPanel],
            backing:     .buffered, defer: false
        )
        p.isFloatingPanel    = true
        p.level              = .floating
        p.backgroundColor    = .clear
        p.isOpaque           = false
        p.hasShadow          = false
        p.isMovable          = true
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return p
    }
}

// MARK: - Sürüklenebilir NSPanel
final class DraggablePanel: NSPanel {
    override var canBecomeKey: Bool { true }

    override func mouseDown(with event: NSEvent) {
        // Buton veya diğer kontrollere tıklanıyorsa sürükleme başlatma
        if let hit = contentView?.hitTest(event.locationInWindow) {
            // NSButton veya içinde buton olan bir view ise normal işle
            var v: NSView? = hit
            while let current = v {
                if current is NSButton { super.mouseDown(with: event); return }
                v = current.superview
            }
        }
        // macOS'un kendi pencere sürükleme sistemini kullan — sıfır bug
        performDrag(with: event)
    }

    // mouseDragged override'a gerek yok — performDrag halleder
}
