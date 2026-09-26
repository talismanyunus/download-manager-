import SwiftUI
import AppKit

private let ac = appAccent
private let bg = Color.clear
private let pn = glassSurface

// MARK: - Onboarding
struct OnboardingView: View {
    @ObservedObject var engine: DownloadEngine
    var onDone: () -> Void

    @State private var step = 0
    @State private var selectedBrowser: Browser? = nil
    @State private var pathCopied = false

    var body: some View {
        ZStack {
            VisualEffectBackground().ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                if step == 0 { welcomeStep }
                else         { extensionStep }
            }
        }
        .frame(width: 660, height: 520)
        .preferredColorScheme(.dark)
    }

    // MARK: Üst bant
    private var topBar: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable().frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text("Download Manager").font(.system(size: 17, weight: .bold))
                Text("Kurulum").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(0..<2, id: \.self) { i in
                    Capsule()
                        .fill(i == step ? ac : .white.opacity(0.12))
                        .frame(width: i == step ? 22 : 8, height: 6)
                        .animation(.spring(response: 0.3), value: step)
                }
            }
        }
        .padding(.horizontal, 40).padding(.vertical, 18)
        .background(pn)
    }

    // MARK: Adım 0 — Hoşgeldin
    private var welcomeStep: some View {
        VStack(spacing: 26) {
            Spacer()
            ZStack {
                Circle().fill(ac.opacity(0.08)).frame(width: 96, height: 96)
                Image(systemName: "arrow.down.to.line.compact")
                    .font(.system(size: 40, weight: .light)).foregroundStyle(ac)
            }
            VStack(spacing: 8) {
                Text("Download Manager'a hoş geldin")
                    .font(.system(size: 23, weight: .bold))
                Text("YouTube, Vimeo, direkt linkler — her şeyi hızlı indir.\nTarayıcı eklentisiyle videolar otomatik yakalanır.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).lineSpacing(4)
            }
            HStack(spacing: 12) {
                featureCard("bolt.fill",           "Çok parçalı",    "16 bağlantıya kadar", .cyan)
                featureCard("play.rectangle.fill", "Video siteleri", "yt-dlp entegrasyonu", ac)
                featureCard("puzzlepiece.fill",    "Tarayıcı",       "Chrome & Firefox",    .purple)
            }
            Spacer()
            Button { withAnimation(.spring(response: 0.35)) { step = 1 } } label: {
                HStack { Text("Devam et"); Image(systemName: "arrow.right") }
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(.black)
                    .padding(.horizontal, 32).padding(.vertical, 13)
                    .background(ac, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain).padding(.bottom, 28)
        }
        .padding(.horizontal, 50)
    }

    private func featureCard(_ icon: String, _ title: String, _ sub: String, _ color: Color) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 20)).foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            Text(title).font(.system(size: 12, weight: .semibold))
            Text(sub).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .background(pn, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.05)))
    }

    // MARK: Adım 1 — Eklenti kurulumu
    private var extensionStep: some View {
        VStack(spacing: 0) {
            // Tarayıcı seçimi
            VStack(spacing: 6) {
                Text("Tarayıcı Eklentisi")
                    .font(.system(size: 20, weight: .bold)).padding(.top, 22)
                Text("Tarayıcını seç, adımları takip et.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .padding(.bottom, 14)

            // Tarayıcı satırları
            VStack(spacing: 6) {
                ForEach(Browser.allCases) { browser in
                    browserRow(browser)
                }
            }
            .padding(.horizontal, 30)

            Divider().opacity(0.1).padding(.vertical, 14)

            // Seçili tarayıcı için adım adım talimat
            if let b = selectedBrowser {
                installGuide(for: b)
                    .padding(.horizontal, 30)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                Text("Tarayıcına tıkla, adımlar burada çıkar.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .padding(.bottom, 8)
            }

            Spacer()

            HStack(spacing: 12) {
                Button { finish() } label: {
                    Text("Daha sonra")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                        .padding(.horizontal, 20).padding(.vertical, 10)
                        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)

                Button { finish() } label: {
                    HStack { Text("Uygulamaya geç"); Image(systemName: "checkmark") }
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(.black)
                        .padding(.horizontal, 22).padding(.vertical, 10)
                        .background(ac, in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 24)
        }
    }

    // MARK: Tarayıcı satırı
    private func browserRow(_ browser: Browser) -> some View {
        let selected = selectedBrowser == browser
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedBrowser = browser
                pathCopied = false
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(browser.color.opacity(selected ? 0.25 : 0.12))
                        .frame(width: 38, height: 38)
                    Text(String(browser.displayName.prefix(1)))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(browser.color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(browser.displayName)
                        .font(.system(size: 13, weight: .semibold))
                    Text(browser.isInstalled ? "Kurulu" : "Bulunamadı")
                        .font(.system(size: 10))
                        .foregroundStyle(browser.isInstalled ? .secondary : .tertiary)
                }
                Spacer()
                if selected {
                    Image(systemName: "chevron.down.circle.fill")
                        .foregroundStyle(ac).font(.system(size: 14))
                } else if browser.isInstalled {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary).font(.system(size: 11))
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(
                selected ? ac.opacity(0.07) : pn,
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selected ? ac.opacity(0.3) : .white.opacity(0.05), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .opacity(browser.isInstalled ? 1 : 0.4)
        .disabled(!browser.isInstalled)
    }

    // MARK: Kurulum talimatları
    @ViewBuilder
    private func installGuide(for browser: Browser) -> some View {
        let extPath = extensionPath()
        VStack(alignment: .leading, spacing: 10) {
            // Chrome / Brave / Edge
            if browser != .firefox {
                chromiumGuide(browser: browser, extPath: extPath)
            } else {
                firefoxGuide(extPath: extPath)
            }
        }
        .padding(14)
        .background(pn, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ac.opacity(0.15), lineWidth: 1))
    }

    // Chrome / Brave / Edge kurulum rehberi
    private func chromiumGuide(browser: Browser, extPath: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("\(browser.displayName) Eklenti Kurulumu", systemImage: "puzzlepiece.fill")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(ac)

            stepRow(1, "Uzantılar sayfasını aç", action: {
                let scheme: String
                switch browser {
                case .brave: scheme = "brave"
                case .edge:  scheme = "edge"
                default:     scheme = "chrome"
                }
                openInBrowser(browser: browser, url: "\(scheme)://extensions")
            }, buttonLabel: "Aç")

            stepRow(2, "Sağ üstteki \"Geliştirici modu\" toggle'ını AÇ", action: nil, buttonLabel: nil)

            stepRow(3, "\"Paketlenmemiş öğe yükle\" butonuna tıkla", action: nil, buttonLabel: nil)

            // Klasör yolu — kopyala + Finder'da göster
            VStack(alignment: .leading, spacing: 6) {
                Text("4.  Bu klasörü seç:").font(.system(size: 11)).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text(extPath.isEmpty ? "BrowserExtension klasörü bulunamadı" : extPath)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))

                    VStack(spacing: 6) {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(extPath, forType: .string)
                            pathCopied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { pathCopied = false }
                        } label: {
                            Label(pathCopied ? "Kopyalandı ✓" : "Kopyala",
                                  systemImage: pathCopied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(pathCopied ? .black : .black)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(pathCopied ? ac : ac, in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)

                        Button {
                            if !extPath.isEmpty {
                                NSWorkspace.shared.activateFileViewerSelecting(
                                    [URL(fileURLWithPath: extPath)]
                                )
                            }
                        } label: {
                            Label("Finder", systemImage: "folder")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // Firefox kurulum rehberi
    private func firefoxGuide(extPath: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Firefox Eklenti Kurulumu", systemImage: "puzzlepiece.fill")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(ac)

            stepRow(1, "Firefox'ta about:debugging sayfasını aç", action: {
                openInBrowser(browser: .firefox, url: "about:debugging#/runtime/this-firefox")
            }, buttonLabel: "Aç")

            stepRow(2, "\"Bu Firefox\" → \"Geçici Eklenti Yükle\" tıkla", action: nil, buttonLabel: nil)

            VStack(alignment: .leading, spacing: 6) {
                Text("3.  Bu dosyayı seç:").font(.system(size: 11)).foregroundStyle(.secondary)
                let manifestPath = extPath.isEmpty ? "" : extPath + "/manifest.json"
                HStack(spacing: 8) {
                    Text(manifestPath.isEmpty ? "manifest.json bulunamadı" : manifestPath)
                        .font(.system(size: 10, design: .monospaced))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))

                    VStack(spacing: 6) {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(manifestPath, forType: .string)
                            pathCopied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { pathCopied = false }
                        } label: {
                            Label(pathCopied ? "✓" : "Kopyala", systemImage: "doc.on.doc")
                                .font(.system(size: 10, weight: .semibold)).foregroundStyle(.black)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(ac, in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)

                        Button {
                            if !manifestPath.isEmpty {
                                NSWorkspace.shared.activateFileViewerSelecting(
                                    [URL(fileURLWithPath: manifestPath)]
                                )
                            }
                        } label: {
                            Label("Finder", systemImage: "folder")
                                .font(.system(size: 10)).foregroundStyle(.primary)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Text("⚠️ Firefox'ta geçici eklentiler tarayıcı kapanınca silinir. Her açılışta tekrar yüklemen gerekebilir.")
                .font(.system(size: 10)).foregroundStyle(.orange).lineSpacing(3)
        }
    }

    private func stepRow(_ n: Int, _ text: String, action: (() -> Void)?, buttonLabel: String?) -> some View {
        HStack(spacing: 10) {
            Text("\(n).")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(ac)
                .frame(width: 18, alignment: .leading)
            Text(text)
                .font(.system(size: 11))
                .frame(maxWidth: .infinity, alignment: .leading)
            if let action, let label = buttonLabel {
                Button(action: action) {
                    Text(label)
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.black)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(ac, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Yardımcılar
    /// Tarayıcıyı doğrudan binary ile başlatır; zaten açıksa yeni sekme olarak açar.
    private func openInBrowser(browser: Browser, url: String) {
        // Önce open -a ile dene (en basit, mevcut pencereye yeni sekme açar)
        let appPath = browser.appPath
        guard !appPath.isEmpty else { return }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.arguments = [url]
        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: appPath),
            configuration: cfg
        ) { _, _ in }
    }

    private func extensionPath() -> String {
        let devPath = (NSHomeDirectory() as NSString)
            .appendingPathComponent("Desktop/download manager/BrowserExtension")
        if FileManager.default.fileExists(atPath: devPath) { return devPath }
        let bundleSibling = ((Bundle.main.bundlePath as NSString).deletingLastPathComponent)
            .appending("/BrowserExtension")
        if FileManager.default.fileExists(atPath: bundleSibling) { return bundleSibling }
        return Bundle.main.path(forResource: "BrowserExtension", ofType: nil) ?? ""
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: "onboardingDone")
        onDone()
    }
}

// MARK: - Browser enum
enum Browser: String, CaseIterable, Identifiable {
    case chrome = "Chrome", firefox = "Firefox", brave = "Brave", edge = "Edge"
    var id: String { rawValue }
    var displayName: String { rawValue }
    var color: Color {
        switch self {
        case .chrome:  return Color(red: 0.26, green: 0.52, blue: 0.96)
        case .firefox: return Color(red: 0.98, green: 0.55, blue: 0.15)
        case .brave:   return Color(red: 0.96, green: 0.38, blue: 0.22)
        case .edge:    return Color(red: 0.0,  green: 0.48, blue: 0.72)
        }
    }
    var appNames: [String] {
        switch self {
        case .chrome:  return ["Google Chrome", "Chromium"]
        case .firefox: return ["Firefox", "Firefox Developer Edition", "Firefox Nightly"]
        case .brave:   return ["Brave Browser"]
        case .edge:    return ["Microsoft Edge"]
        }
    }
    var appPath: String {
        let dirs = ["/Applications", "\(NSHomeDirectory())/Applications"]
        for dir in dirs {
            for name in appNames {
                let p = "\(dir)/\(name).app"
                if FileManager.default.fileExists(atPath: p) { return p }
            }
        }
        return ""
    }
    var isInstalled: Bool { !appPath.isEmpty }
}
