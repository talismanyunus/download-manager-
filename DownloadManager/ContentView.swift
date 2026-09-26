import SwiftUI
import AppKit

// Eski opak renkler kaldırıldı — VibrancyView.swift'teki paylaşılan sabitler kullanılıyor
private let accent = appAccent
private let panel  = glassSurface   // frosted card surface
private let canvas = Color.clear    // vibrancy arka plana bırakılıyor

// MARK: - Ana ekran
struct ContentView: View {
    @ObservedObject var engine: DownloadEngine
    @State private var selection = "Tüm indirmeler"
    @State private var query    = ""
    @State private var adding   = false
    @State private var settings = false
    @State private var extensionSheet = false

    private var filtered: [Transfer] {
        engine.items.filter { item in
            let match: Bool
            switch selection {
            case "İndiriliyor":    match = item.state == .downloading
            case "Bekleyenler":    match = [.queued, .paused].contains(item.state)
            case "Tamamlananlar":  match = item.state == .completed
            case "Hatalar":        match = item.state == .failed
            case "Tüm indirmeler": match = true
            default:               match = item.category == selection
            }
            return match && (query.isEmpty
                || item.name.localizedCaseInsensitiveContains(query)
                || item.source.host?.localizedCaseInsensitiveContains(query) == true)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(alignment: .leading, spacing: 0) {
                header
                HStack(spacing: 14) {
                    metric("ANLIK HIZ",      value: byteString(Int64(engine.totalSpeed)) + "/sn", icon: "bolt.fill",         color: accent)
                    metric("AKTİF İNDİRME", value: "\(engine.activeCount)",                       icon: "arrow.down.circle", color: .cyan)
                    metric("TAMAMLANAN",     value: "\(engine.completedCount)",                    icon: "checkmark.circle",  color: .purple)
                }.padding(.horizontal, 30).padding(.bottom, 26)

                if !engine.ytdlpInstalled { ytdlpBanner }

                HStack {
                    Text(selection).font(.system(size: 19, weight: .semibold))
                    Text("\(filtered.count)")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.white.opacity(0.06), in: Capsule())
                    Spacer()
                    Button { engine.pauseAll()  } label: { Label("Duraklat", systemImage: "pause") }
                    Button { engine.resumeAll() } label: { Image(systemName: "play") }.help("Tümünü devam ettir")
                    Menu {
                        Button("Tamamlananları listeden kaldır") { engine.clearCompleted() }
                        Button("İndirme klasörünü aç") { NSWorkspace.shared.open(URL(fileURLWithPath: engine.folder)) }
                    } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 24)
                }
                .buttonStyle(.borderless).foregroundStyle(.secondary)
                .padding(.horizontal, 30).padding(.bottom, 16)

                if filtered.isEmpty {
                    Spacer()
                    VStack(spacing: 15) {
                        Image(systemName: query.isEmpty ? "arrow.down.to.line.compact" : "magnifyingglass")
                            .font(.system(size: 40, weight: .light)).foregroundStyle(accent)
                            .frame(width: 90, height: 90)
                            .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 28))
                        Text(query.isEmpty ? "Bir sonraki indirmene hazır." : "Sonuç bulunamadı")
                            .font(.system(size: 23, weight: .semibold))
                        Text(query.isEmpty ? "YouTube, Vimeo veya direkt link ekle." : "Başka bir dosya adı veya alan adı ara.")
                            .foregroundStyle(.secondary)
                        if query.isEmpty {
                            Button("Bağlantı ekle") { adding = true }
                                .buttonStyle(MintButton()).padding(.top, 8)
                        }
                    }.frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(filtered) { item in TransferRow(item: item, engine: engine) }
                        }.padding(.horizontal, 30).padding(.bottom, 20)
                    }
                }

                // Durum çubuğu
                HStack(spacing: 8) {
                    Circle().fill(accent).frame(width: 6, height: 6)
                    Text(engine.activeCount > 0 ? "İndirmeler sürüyor" : "Hazır")
                    Spacer()
                    Image(systemName: "folder")
                    Text((engine.folder as NSString).lastPathComponent)
                    Text("•  \(engine.maxConcurrent) eşzamanlı").padding(.leading, 8)
                }
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .padding(.horizontal, 30).padding(.vertical, 14)
                .background(.black.opacity(0.12))
            }
            // Sağ panel — behindWindow ile masaüstüne karşı blur
            .background(VisualEffectBackground(material: .underWindowBackground, blendingMode: .behindWindow))
        }
        .tint(accent)
        .background(Color.clear)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $adding)  { AddDownloadView(engine: engine) }
        .sheet(isPresented: $settings) {
            SettingsSheetContainer(engine: engine) { settings = false }
        }
        .sheet(isPresented: $extensionSheet) {
            ExtensionInstallSheet(engine: engine) { extensionSheet = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("newDownload"))) { _ in adding = true }
        .alert("İşlem tamamlanamadı",
               isPresented: Binding(get: { engine.globalError != nil }, set: { if !$0 { engine.globalError = nil } })) {
            Button("Tamam") { engine.globalError = nil }
        } message: { Text(engine.globalError ?? "") }
    }

    // MARK: yt-dlp banner
    @ViewBuilder
    private var ytdlpBanner: some View {
        HStack(spacing: 12) {
            if engine.ytdlpInstalling {
                ProgressView().progressViewStyle(.circular).scaleEffect(0.7).frame(width: 20, height: 20)
            } else {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            VStack(alignment: .leading, spacing: 2) {
                if engine.ytdlpInstalling {
                    Text(engine.ytdlpUpdateStatus.isEmpty ? "yt-dlp kuruluyor…" : engine.ytdlpUpdateStatus)
                        .font(.system(size: 12, weight: .semibold))
                } else {
                    Text("yt-dlp kurulu değil").font(.system(size: 12, weight: .semibold))
                    Text("YouTube, Vimeo vb. sitelerden indirmek için gerekli.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if engine.ytdlpInstalling {
                Text("Lütfen bekleyin…").font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                Button { engine.installYtdlp() } label: {
                    Label("Yükle", systemImage: "arrow.down.circle.fill")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.black)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(accent, in: RoundedRectangle(cornerRadius: 7))
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 30).padding(.vertical, 12)
        .background(engine.ytdlpInstalling ? accent.opacity(0.08) : Color.orange.opacity(0.10))
        .overlay(Rectangle().frame(height: 1)
            .foregroundStyle(engine.ytdlpInstalling ? accent.opacity(0.2) : .orange.opacity(0.3)),
                 alignment: .bottom)
    }

    // MARK: Sidebar
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable().frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Download").font(.system(size: 16, weight: .bold))
                    Text("MANAGER").font(.system(size: 8, weight: .medium)).tracking(3).foregroundStyle(.secondary)
                }
            }.padding(.top, 40).padding(.bottom, 32).padding(.horizontal, 20)

            sidebarSection("KÜTÜPHANE")
            nav("Tüm indirmeler",  "square.grid.2x2",       engine.items.count)
            nav("İndiriliyor",     "arrow.down.circle",      engine.activeCount)
            nav("Bekleyenler",     "clock",                  engine.items.filter { [.queued, .paused].contains($0.state) }.count)
            nav("Tamamlananlar",   "checkmark.circle",       engine.completedCount)
            nav("Hatalar",         "exclamationmark.circle", engine.items.filter { $0.state == .failed }.count)

            sidebarSection("DOSYA TÜRLERİ").padding(.top, 24)
            ForEach([("Video","film"),("Müzik","music.note"),("Arşiv","archivebox"),
                     ("Uygulama","app.dashed"),("Belge","doc.text"),("Diğer","doc")], id: \.0) { name, icon in
                nav(name, icon, nil)
            }

            Spacer(minLength: 20)

            // Tarayıcı Eklentisi
            Button { extensionSheet = true } label: {
                HStack(spacing: 9) {
                    Image(systemName: "puzzlepiece.fill").frame(width: 18)
                    Text("Tarayıcı Eklentisi").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Circle().fill(accent).frame(width: 6, height: 6)
                }
                .padding(.horizontal, 13).padding(.vertical, 10)
                .foregroundStyle(accent.opacity(0.9))
                .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain).padding(.horizontal, 12).padding(.bottom, 4)

            Button { settings = true } label: {
                Label("Ayarlar", systemImage: "slider.horizontal.3").font(.system(size: 13))
            }.buttonStyle(.plain).foregroundStyle(.secondary).padding(22)
        }
        .frame(width: 220)
        // Sidebar — behindWindow ile masaüstüne karşı tam blur
        .background(VisualEffectBackground(material: .sidebar, blendingMode: .behindWindow))
        .overlay(Rectangle().frame(width: 0.5).foregroundStyle(Color.white.opacity(0.12)), alignment: .trailing)
    }

    private func sidebarSection(_ title: String) -> some View {
        Text(title).font(.system(size: 9, weight: .semibold)).tracking(1.8)
            .foregroundStyle(.secondary).padding(.leading, 22).padding(.bottom, 8)
    }

    private func nav(_ title: String, _ icon: String, _ count: Int?) -> some View {
        Button { selection = title } label: {
            HStack(spacing: 11) {
                Image(systemName: icon).frame(width: 18)
                Text(title).font(.system(size: 12, weight: selection == title ? .semibold : .regular))
                Spacer()
                if let count, count > 0 {
                    Text("\(count)").font(.system(size: 10, weight: .medium)).monospacedDigit()
                }
            }
            .padding(.horizontal, 13).padding(.vertical, 9)
            .foregroundStyle(selection == title ? accent : .white.opacity(0.7))
            .background(selection == title ? glassSelected : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain).padding(.horizontal, 10).padding(.bottom, 2)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Her şey, tek bir yerde.").font(.system(size: 26, weight: .bold))
                Text("İndirmelerini düzenle. Akışı kontrol et.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 20)
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("İndirmelerde ara", text: $query).textFieldStyle(.plain)
            }
            .font(.system(size: 12)).padding(10).frame(width: 175)
            .background(glassSurface, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(glassBorder, lineWidth: 0.5))

            Button { adding = true } label: { Label("Yeni indirme", systemImage: "plus") }
                .buttonStyle(MintButton())
        }.padding(.horizontal, 30).padding(.top, 40).padding(.bottom, 28)
    }

    private func metric(_ title: String, value: String, icon: String, color: Color) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.system(size: 9, weight: .semibold)).tracking(1.4).foregroundStyle(.secondary)
                Text(value).font(.system(size: 24, weight: .semibold, design: .rounded)).monospacedDigit()
            }
            Spacer()
            Image(systemName: icon).font(.system(size: 20)).foregroundStyle(color)
                .frame(width: 42, height: 42)
                .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(17).frame(maxWidth: .infinity)
        .glassCard(cornerRadius: 13)
    }
}

// MARK: - Buton stili
struct MintButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.85))
            .padding(.horizontal, 16).padding(.vertical, 11)
            .background(appAccent.opacity(configuration.isPressed ? 0.7 : 1),
                        in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Transfer satırı
struct TransferRow: View {
    let item: Transfer
    @ObservedObject var engine: DownloadEngine
    var tint: Color { item.state == .failed ? .orange : item.state == .completed ? appAccent : .cyan }

    var body: some View {
        HStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: item.symbol)
                    .font(.system(size: 20)).foregroundStyle(tint)
                    .frame(width: 46, height: 52)
                    .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                if item.isStreamingSite {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 9)).foregroundStyle(.white)
                        .padding(3)
                        .background(appAccent.opacity(0.9), in: RoundedRectangle(cornerRadius: 4))
                        .offset(x: 4, y: 4)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(item.name).font(.system(size: 13, weight: .semibold))
                        .lineLimit(1).help(item.source.absoluteString)
                    Spacer()
                    Text(item.state.title).font(.system(size: 10, weight: .medium)).foregroundStyle(tint)
                }
                if item.state == .downloading && item.expected == 0 {
                    ProgressView().progressViewStyle(.linear).tint(tint)
                } else {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.07))
                            Capsule().fill(tint).frame(width: max(0, geo.size.width * item.progress))
                        }
                    }.frame(height: 4)
                }
                HStack(spacing: 10) {
                    Text(byteString(item.received) + (item.expected > 0 ? " / " + byteString(item.expected) : ""))
                    Text("·")
                    if item.isStreamingSite {
                        Text(item.source.host ?? "").lineLimit(1)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(appAccent.opacity(0.12), in: Capsule())
                    } else {
                        Text(item.source.host ?? "").lineLimit(1)
                    }
                    Spacer()
                    if item.state == .downloading {
                        if let detail = item.statusDetail, !detail.isEmpty { Text(detail).lineLimit(1) }
                        if item.speed > 0 {
                            Text("·")
                            Text(byteString(Int64(item.speed)) + "/sn").foregroundStyle(appAccent)
                            if item.expected > item.received {
                                Text("\(Int(Double(item.expected - item.received) / item.speed)) sn")
                            }
                        }
                    } else if let s = item.scheduledAt, item.state == .queued {
                        Text(s, style: .time)
                    }
                }.font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
                if let error = item.error {
                    Text(error).font(.system(size: 10)).foregroundStyle(.orange).lineLimit(2)
                }
            }

            HStack(spacing: 10) {
                Button { DownloadDetailWindowManager.shared.open(itemID: item.id, engine: engine) } label: {
                    Image(systemName: "info.circle")
                }.help("Detaylar")
                if [.downloading, .queued].contains(item.state) {
                    Button { engine.pause(item.id) } label: { Image(systemName: "pause.fill") }.help("Duraklat")
                }
                if [.paused, .failed].contains(item.state) {
                    Button { engine.resume(item.id) } label: { Image(systemName: "play.fill") }.help("Devam et")
                }
                if item.state == .completed {
                    Button { engine.reveal(item) } label: { Image(systemName: "folder") }.help("Finder'da göster")
                }
                Menu {
                    Button("Detayları göster") { DownloadDetailWindowManager.shared.open(itemID: item.id, engine: engine) }
                    Button("Bağlantıyı kopyala") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(item.source.absoluteString, forType: .string)
                    }
                    if item.state == .completed { Button("Finder'da göster") { engine.reveal(item) } }
                    Divider()
                    Button("Listeden kaldır", role: .destructive) { engine.remove(item.id) }
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 18)
            }.buttonStyle(.plain).foregroundStyle(.secondary).frame(width: 80)
        }
        .padding(16)
        .glassCard(cornerRadius: 12)
    }
}

// MARK: - Yeni indirme
struct AddDownloadView: View {
    @ObservedObject var engine: DownloadEngine
    @Environment(\.dismiss) private var dismiss
    @State private var urls = ""
    @State private var scheduled = false
    @State private var date = Date().addingTimeInterval(3600)
    @State private var error: String?

    private var hasStreamingURL: Bool {
        urls.components(separatedBy: .newlines).contains { line in
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: t) else { return false }
            return TransferWorker.isStreamingSite(url)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "link.circle.fill").font(.system(size: 28)).foregroundStyle(appAccent)
                Text("Yeni indirme").font(.title2.bold())
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(.secondary) }.buttonStyle(.plain)
            }
            Text("YouTube, Vimeo veya direkt dosya bağlantısı. Toplu indirme için her satıra bir link.")
                .font(.callout).foregroundStyle(.secondary)

            TextEditor(text: $urls)
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden).padding(10).frame(height: 120)
                .background(glassDeep, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(glassBorder, lineWidth: 0.5))

            HStack {
                Button("Panodan yapıştır") { urls = NSPasteboard.general.string(forType: .string) ?? "" }
                Spacer()
                Text("\(urls.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count) bağlantı")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if hasStreamingURL {
                HStack(spacing: 10) {
                    Image(systemName: engine.ytdlpInstalled ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(engine.ytdlpInstalled ? appAccent : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(engine.ytdlpInstalled ? "yt-dlp hazır" : "yt-dlp kurulu değil")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(engine.ytdlpInstalled ? appAccent : .orange)
                        Text(engine.ytdlpInstalled ? "Format: \(engine.ytdlpFormat)" : "brew install yt-dlp")
                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(engine.ytdlpInstalled ? appAccent.opacity(0.08) : Color.orange.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                Image(systemName: "folder").foregroundStyle(appAccent)
                Text(engine.folder).lineLimit(1).truncationMode(.middle).font(.caption)
                Spacer()
                Button("Değiştir") { engine.chooseFolder() }
            }
            Toggle("Daha sonra başlat", isOn: $scheduled)
            if scheduled {
                DatePicker("Başlangıç", selection: $date, in: Date()...)
                Text("Zamanlama için uygulama açık olmalı.").font(.caption).foregroundStyle(.secondary)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
            HStack {
                Spacer()
                Button("Vazgeç") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("İndirmeyi ekle") {
                    let lines = urls.components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                    guard !lines.isEmpty else { error = "En az bir bağlantı girin."; return }
                    let invalid = lines.filter { t in
                        guard let u = URL(string: t) else { return true }
                        return !["http","https"].contains(u.scheme?.lowercased() ?? "") || u.host == nil
                    }
                    guard invalid.isEmpty else { error = "Geçersiz: \(invalid.first ?? "")"; return }
                    if engine.add(urls, scheduledAt: scheduled ? date : nil) > 0 { dismiss() }
                }.buttonStyle(MintButton()).keyboardShortcut(.defaultAction)
            }
        }
        .padding(28).frame(width: 540)
        .vibrancyBackground()
        .preferredColorScheme(.dark)
    }
}

// MARK: - Ayarlar sheet container
struct SettingsSheetContainer: View {
    @ObservedObject var engine: DownloadEngine
    var onDone: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            SettingsView(engine: engine)
            Divider().opacity(0.1)
            HStack {
                Spacer()
                Button("Bitti") { onDone() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(MintButton())
                    .padding(20)
            }
        }
        .vibrancyBackground()
        .preferredColorScheme(.dark)
    }
}

// MARK: - Tarayıcı Eklentisi Sheet
struct ExtensionInstallSheet: View {
    @ObservedObject var engine: DownloadEngine
    var onDone: () -> Void

    @State private var selectedBrowser: Browser? = nil
    @State private var pathCopied = false

    var body: some View {
        VStack(spacing: 0) {
            // Başlık
            HStack(spacing: 12) {
                Image(systemName: "puzzlepiece.fill").font(.system(size: 20)).foregroundStyle(appAccent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tarayıcı Eklentisi").font(.title2.bold())
                    Text("Tarayıcını seç, adımları takip et.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { onDone() } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                }.buttonStyle(.plain)
            }
            .padding(22)
            .background(glassDeep)

            Divider().opacity(0.12)

            ScrollView {
                VStack(spacing: 12) {
                    VStack(spacing: 6) {
                        ForEach(Browser.allCases) { browser in extBrowserRow(browser) }
                    }
                    if let b = selectedBrowser {
                        extGuide(for: b).transition(.opacity.combined(with: .move(edge: .top)))
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "hand.point.up.left").foregroundStyle(appAccent.opacity(0.6))
                            Text("Tarayıcına tıkla, kurulum adımları burada çıkar.").font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        .padding(14).frame(maxWidth: .infinity)
                        .glassCard()
                    }
                }
                .padding(18)
                .animation(.easeInOut(duration: 0.18), value: selectedBrowser)
            }

            Divider().opacity(0.12)

            HStack {
                Spacer()
                Button("Tamam") { onDone() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(MintButton())
            }
            .padding(18).background(glassDeep)
        }
        .frame(width: 540, height: 520)
        .vibrancyBackground()
        .preferredColorScheme(.dark)
    }

    private func extBrowserRow(_ browser: Browser) -> some View {
        let sel = selectedBrowser == browser
        return Button {
            withAnimation { selectedBrowser = browser; pathCopied = false }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(browser.color.opacity(sel ? 0.25 : 0.12)).frame(width: 36, height: 36)
                    Text(String(browser.displayName.prefix(1)))
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(browser.color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(browser.displayName).font(.system(size: 13, weight: .semibold))
                    Text(browser.isInstalled ? "Kurulu" : "Bulunamadı")
                        .font(.system(size: 10)).foregroundStyle(browser.isInstalled ? .secondary : .tertiary)
                }
                Spacer()
                Image(systemName: sel ? "chevron.down.circle.fill" : "chevron.right")
                    .foregroundStyle(sel ? appAccent : .secondary).font(.system(size: sel ? 14 : 11))
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(sel ? glassSelected : glassSurface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(sel ? appAccent.opacity(0.3) : glassBorder, lineWidth: 0.5))
        }
        .buttonStyle(.plain).opacity(browser.isInstalled ? 1 : 0.4).disabled(!browser.isInstalled)
    }

    @ViewBuilder
    private func extGuide(for browser: Browser) -> some View {
        let extPath = extensionPath()
        VStack(alignment: .leading, spacing: 10) {
            Label("\(browser.displayName) Kurulum", systemImage: "list.number")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(appAccent)

            if browser != .firefox {
                let scheme = browser == .brave ? "brave" : browser == .edge ? "edge" : "chrome"
                extStep(1, "Uzantılar sayfasını aç") { openInBrowser(browser, url: "\(scheme)://extensions") }
                extStep(2, "Geliştirici modunu AÇ")
                extStep(3, "\"Paketlenmemiş öğe yükle\" tıkla")
                extPathRow("4. Bu klasörü seç:", path: extPath)
            } else {
                extStep(1, "about:debugging sayfasını aç") { openInBrowser(browser, url: "about:debugging#/runtime/this-firefox") }
                extStep(2, "\"Geçici Eklenti Yükle\" tıkla")
                extPathRow("3. manifest.json dosyasını seç:", path: extPath.isEmpty ? "" : extPath + "/manifest.json")
                Text("⚠️ Firefox geçici eklentiler her kapanışta silinir.").font(.system(size: 10)).foregroundStyle(.orange)
            }
        }
        .padding(14)
        .glassCard()
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(appAccent.opacity(0.2), lineWidth: 0.5))
    }

    private func extStep(_ n: Int, _ text: String, action: (() -> Void)? = nil) -> some View {
        HStack(spacing: 10) {
            Text("\(n).").font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(appAccent).frame(width: 18, alignment: .leading)
            Text(text).font(.system(size: 11)).frame(maxWidth: .infinity, alignment: .leading)
            if let action {
                Button(action: action) {
                    Text("Aç").font(.system(size: 10, weight: .semibold)).foregroundStyle(.black)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(appAccent, in: RoundedRectangle(cornerRadius: 6))
                }.buttonStyle(.plain)
            }
        }
    }

    private func extPathRow(_ label: String, path: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Text(path.isEmpty ? "Bulunamadı" : path)
                    .font(.system(size: 9, design: .monospaced)).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(7)
                    .background(glassDeep, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(glassBorder, lineWidth: 0.5))
                VStack(spacing: 5) {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(path, forType: .string)
                        pathCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { pathCopied = false }
                    } label: {
                        Text(pathCopied ? "✓" : "Kopyala").font(.system(size: 9, weight: .semibold)).foregroundStyle(.black)
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(appAccent, in: RoundedRectangle(cornerRadius: 5))
                    }.buttonStyle(.plain)
                    Button {
                        guard !path.isEmpty else { return }
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                    } label: {
                        Label("Finder", systemImage: "folder").font(.system(size: 9)).foregroundStyle(.primary)
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(glassSurface, in: RoundedRectangle(cornerRadius: 5))
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func openInBrowser(_ browser: Browser, url: String) {
        guard !browser.appPath.isEmpty else { return }
        let cfg = NSWorkspace.OpenConfiguration(); cfg.arguments = [url]
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: browser.appPath), configuration: cfg) { _, _ in }
    }

    private func extensionPath() -> String {
        let dev = (NSHomeDirectory() as NSString).appendingPathComponent("Desktop/download manager/BrowserExtension")
        if FileManager.default.fileExists(atPath: dev) { return dev }
        let sib = ((Bundle.main.bundlePath as NSString).deletingLastPathComponent) + "/BrowserExtension"
        if FileManager.default.fileExists(atPath: sib) { return sib }
        return Bundle.main.path(forResource: "BrowserExtension", ofType: nil) ?? ""
    }
}

// MARK: - Ayarlar
struct SettingsView: View {
    @ObservedObject var engine: DownloadEngine
    private let formatOptions: [(label: String, value: String)] = [
        ("En iyi kalite (video + ses)",    "bestvideo+bestaudio/best"),
        ("Max 1080p",                       "bestvideo[height<=1080]+bestaudio/best"),
        ("Max 720p",                        "bestvideo[height<=720]+bestaudio/best"),
        ("Max 480p",                        "bestvideo[height<=480]+bestaudio/best"),
        ("Sadece ses",                      "bestaudio/best"),
        ("MP4 tercihli",                    "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Ayarlar").font(.title2.bold()).padding(.bottom, 4)

                GroupBox("Genel") {
                    VStack(alignment: .leading, spacing: 14) {
                        Stepper("Eşzamanlı indirmeler: \(engine.maxConcurrent)", value: $engine.maxConcurrent, in: 1...8)
                        Stepper("Bağlantı sayısı: \(engine.connections)", value: $engine.connections, in: 1...16)
                        HStack {
                            Text("Hız sınırı")
                            Spacer()
                            Text(engine.speedLimitKB == 0 ? "Sınırsız" : "\(engine.speedLimitKB) KB/sn")
                                .foregroundStyle(.secondary).font(.caption)
                        }
                        Slider(value: Binding(
                            get: { Double(engine.speedLimitKB) },
                            set: { engine.speedLimitKB = Int($0) }
                        ), in: 0...10240, step: 128).tint(appAccent)
                    }.padding(4)
                }

                GroupBox("İndirme Klasörü") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(engine.folder).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        Button("Klasör seç…") { engine.chooseFolder() }
                    }.padding(4)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 10) {
                            Image(systemName: engine.ytdlpInstalled ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(engine.ytdlpInstalled ? appAccent : .orange).font(.system(size: 18))
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(engine.ytdlpInstalled ? "yt-dlp kurulu" : "yt-dlp bulunamadı")
                                        .font(.system(size: 13, weight: .semibold))
                                    if !engine.ytdlpVersion.isEmpty {
                                        Text("v\(engine.ytdlpVersion)").font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(.secondary).padding(.horizontal, 5).padding(.vertical, 2)
                                            .background(.white.opacity(0.06), in: Capsule())
                                    }
                                }
                                Text(engine.ytdlpInstalled
                                     ? "YouTube, Vimeo ve daha fazlası"
                                     : "Terminal: brew install yt-dlp")
                                    .font(.caption).foregroundStyle(engine.ytdlpInstalled ? Color.secondary : Color.orange)
                                if !engine.ytdlpUpdateStatus.isEmpty {
                                    Text(engine.ytdlpUpdateStatus).font(.system(size: 10))
                                        .foregroundStyle(engine.ytdlpUpdateStatus.contains("güncellendi") ? appAccent : .secondary)
                                }
                            }
                            Spacer()
                            if engine.ytdlpInstalled {
                                Button { engine.updateYtdlpNow() } label: {
                                    Label("Güncelle", systemImage: "arrow.clockwise").font(.system(size: 11))
                                }.buttonStyle(.plain).foregroundStyle(appAccent)
                            } else if engine.ytdlpInstalling {
                                ProgressView().scaleEffect(0.7)
                            } else {
                                Button { engine.installYtdlp() } label: {
                                    Label("Yükle", systemImage: "arrow.down.circle.fill")
                                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.black)
                                        .padding(.horizontal, 10).padding(.vertical, 5)
                                        .background(appAccent, in: RoundedRectangle(cornerRadius: 6))
                                }.buttonStyle(.plain)
                            }
                        }
                        Divider().opacity(0.15)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Video kalitesi").font(.system(size: 12, weight: .semibold))
                            Picker("", selection: $engine.ytdlpFormat) {
                                ForEach(formatOptions, id: \.value) { opt in Text(opt.label).tag(opt.value) }
                            }.pickerStyle(.menu).disabled(!engine.ytdlpInstalled)
                            Text(engine.ytdlpFormat).font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.secondary).lineLimit(2)
                        }
                        Divider().opacity(0.15)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Desteklenen siteler").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                            Text("YouTube · Vimeo · Twitter/X · Instagram · Facebook · TikTok · Dailymotion · Twitch · Reddit · Bilibili · SoundCloud · Rumble")
                                .font(.caption).foregroundStyle(.secondary).lineSpacing(3)
                        }
                    }.padding(4)
                } label: {
                    Label("yt-dlp — Video İndirme", systemImage: "play.rectangle.fill")
                        .font(.system(size: 13, weight: .semibold))
                }

                GroupBox("Hakkında") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Download Manager 1.0").font(.headline)
                        Text("Çok parçalı curl, yt-dlp ve ffmpeg kullanır. Çıkışta indirmeler duraklatılır.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(4)
                }
            }.padding(28)
        }.frame(width: 440)
    }
}
