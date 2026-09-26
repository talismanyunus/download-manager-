import SwiftUI
import AppKit
import UserNotifications

// MARK: - App Entry Point
@main struct DownloadManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var engine: DownloadEngine = DownloadEngine()

    var body: some Scene {
        WindowGroup {
            RootView(engine: engine)
                .onAppear {
                    if delegate.engine == nil {
                        delegate.engine = engine
                        delegate.lateSetup()
                    }
                }
                .preferredColorScheme(.dark)
                .frame(minWidth: 1000, minHeight: 650)
                // SwiftUI background'u tamamen şeffaf yap
                .background(.clear)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Yeni indirme") {
                    NotificationCenter.default.post(name: .init("newDownload"), object: nil)
                }.keyboardShortcut("n")
            }
            CommandMenu("İndirmeler") {
                Button("Tümünü duraklat")     { engine.pauseAll() }
                Button("Tümünü devam ettir")  { engine.resumeAll() }
                Divider()
                Button("İndirme klasörünü seç…") { engine.chooseFolder() }
                Divider()
                Button("yt-dlp'yi güncelle")  { engine.updateYtdlpNow() }
            }
        }
        Settings {
            SettingsView(engine: engine).preferredColorScheme(.dark)
                .vibrancyBackground()
        }
    }
}

// MARK: - Root (Onboarding veya Ana ekran)
struct RootView: View {
    @ObservedObject var engine: DownloadEngine
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "onboardingDone")

    var body: some View {
        if showOnboarding {
            OnboardingView(engine: engine) {
                withAnimation(.easeInOut(duration: 0.3)) { showOnboarding = false }
            }
            .frame(width: 620, height: 480)
        } else {
            ContentView(engine: engine)
        }
    }
}


final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var engine: DownloadEngine?
    var httpServer: DownloadHTTPServer?
    private var floatTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Bildirim izni
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }

        // Tüm mevcut ve gelecek pencerelere vibrancy uygula
        NSApp.windows.forEach { makeWindowVibrancy($0) }

        // NotificationCenter ile yeni pencere açıldığında da uygula
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object:  nil,
            queue:   .main
        ) { [weak self] note in
            if let win = note.object as? NSWindow {
                self?.makeWindowVibrancy(win)
            }
        }

        // Ana pencere kimliği
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.windows.first { !($0 is NSPanel) }?
                .identifier = NSUserInterfaceItemIdentifier("main")
        }
    }

    private func makeWindowVibrancy(_ window: NSWindow) {
        guard !(window is NSPanel) else { return }
        applyVibrancy(to: window, material: .sidebar)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
    }

    /// onAppear'dan engine set edildikten sonra çağrılır
    func lateSetup() {
        guard let engine else { return }

        // HTTP API sunucusu
        httpServer = DownloadHTTPServer(engine: engine)
        httpServer?.start()

        // yt-dlp otomatik güncelleme
        engine.checkAndUpdateYtdlpIfNeeded()
        // Float kart artık sadece tarayıcı eklentisinden gelen indirmelerde açılıyor.
        // Uygulama içinden URL yapıştırılınca float kart ÇIKMAZ.
        // FloatWindowManager.shared.show() artık yalnızca HTTP API üzerinden çağrılıyor.
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        floatTimer?.invalidate()
        FloatWindowManager.shared.dismissAll()
        httpServer?.stop()
        guard let engine else { return .terminateNow }
        engine.prepareExit { sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for w in NSApp.windows where w.identifier?.rawValue == "main" {
                w.makeKeyAndOrderFront(nil)
            }
        }
        return true
    }
}

// MARK: - HTTP API Server
// Browser eklentisi 127.0.0.1:60315 adresine bağlanarak indirme ekler.
// POST /add   { "url":"..", "referer":"..", "filename":"..", "userAgent":".." }
// GET  /status → { "active": N, "version": "1.0" }
final class DownloadHTTPServer {
    private let port: UInt16 = 60315
    private weak var engine: DownloadEngine?
    private var serverFD: Int32 = -1
    private var running  = false
    // İki ayrı queue: biri accept loop'u, diğerleri client işleyicileri için
    private let acceptQueue = DispatchQueue(label: "dm.http.accept", qos: .background)
    private let workerQueue = DispatchQueue(label: "dm.http.worker", qos: .background,
                                            attributes: .concurrent)

    init(engine: DownloadEngine) { self.engine = engine }

    func start() {
        acceptQueue.async { [weak self] in self?.runAcceptLoop() }
    }

    func stop() {
        running = false
        if serverFD >= 0 { Darwin.close(serverFD); serverFD = -1 }
    }

    private func runAcceptLoop() {
        serverFD = socket(AF_INET, SOCK_STREAM, 0)
        guard serverFD >= 0 else { return }

        var yes: Int32 = 1
        setsockopt(serverFD, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr          = sockaddr_in()
        addr.sin_family   = sa_family_t(AF_INET)
        addr.sin_port     = port.bigEndian
        addr.sin_addr     = in_addr(s_addr: INADDR_ANY)
        addr.sin_len      = UInt8(MemoryLayout<sockaddr_in>.size)

        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(serverFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(serverFD, 16) == 0 else { Darwin.close(serverFD); return }

        running = true
        while running {
            var clientAddr = sockaddr_in()
            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            let fd = withUnsafeMutablePointer(to: &clientAddr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    accept(serverFD, $0, &len)
                }
            }
            guard fd >= 0 else { continue }
            workerQueue.async { [weak self] in self?.handle(fd: fd) }
        }
    }

    private func handle(fd: Int32) {
        defer { Darwin.close(fd) }

        // SO_RCVTIMEO ile 3 sn timeout
        var tv = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var buf = [UInt8](repeating: 0, count: 16384)
        let n   = recv(fd, &buf, buf.count - 1, 0)
        guard n > 0 else { return }
        let raw = String(bytes: buf.prefix(n), encoding: .utf8) ?? ""

        // CORS preflight
        if raw.hasPrefix("OPTIONS") {
            write(fd, "HTTP/1.1 204 No Content\r\n" +
                      "Access-Control-Allow-Origin: *\r\n" +
                      "Access-Control-Allow-Methods: POST, GET, OPTIONS\r\n" +
                      "Access-Control-Allow-Headers: Content-Type\r\n\r\n")
            return
        }

        let firstLine = raw.components(separatedBy: "\r\n").first ?? ""
        let parts     = firstLine.components(separatedBy: " ")
        let method    = parts.first ?? ""
        let path      = parts.dropFirst().first ?? "/"
        let body      = raw.components(separatedBy: "\r\n\r\n").dropFirst()
                           .joined(separator: "\r\n\r\n")

        var status      = "200 OK"
        var respBody    = ""

        switch (method, path) {
        case ("GET", "/status"), ("GET", "/status/"):
            let active = engine?.activeCount ?? 0
            respBody = "{\"ok\":true,\"active\":\(active),\"version\":\"1.0\",\"port\":60315}"

        case ("POST", "/add"), ("POST", "/add/"):
            if let data = body.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
               let urlStr = json["url"], !urlStr.isEmpty {
                let referer  = json["referer"]  ?? ""
                let filename = json["filename"] ?? ""
                let ua       = json["userAgent"] ?? ""

                DispatchQueue.main.async { [weak self] in
                    guard let engine = self?.engine else { return }
                    var headers: [String: String] = [:]
                    if !referer.isEmpty { headers["Referer"]    = referer }
                    if !ua.isEmpty      { headers["User-Agent"] = ua }
                    let added = engine.add(urlStr, headers: headers,
                                           suggestedName: filename.isEmpty ? nil : filename)
                    if added > 0, let item = engine.items.first {
                        // Float kart: sadece browser eklentisinden gelince aç
                        FloatWindowManager.shared.show(itemID: item.id, engine: engine)
                        self?.sendNotification(title: "İndirme eklendi",
                                               body: filename.isEmpty ? urlStr : filename)
                    }
                }
                respBody = "{\"ok\":true}"
            } else {
                status   = "400 Bad Request"
                respBody = "{\"ok\":false,\"error\":\"missing url\"}"
            }

        default:
            status   = "404 Not Found"
            respBody = "{\"ok\":false}"
        }

        let resp = "HTTP/1.1 \(status)\r\n" +
                   "Content-Type: application/json\r\n" +
                   "Access-Control-Allow-Origin: *\r\n" +
                   "Content-Length: \(respBody.utf8.count)\r\n" +
                   "Connection: close\r\n\r\n" +
                   respBody
        write(fd, resp)
    }

    @discardableResult
    private func write(_ fd: Int32, _ s: String) -> Int {
        s.withCString { ptr in Darwin.send(fd, ptr, strlen(ptr), 0) }
    }

    private func sendNotification(title: String, body: String) {
        let c      = UNMutableNotificationContent()
        c.title    = title
        c.body     = body.count > 80 ? String(body.prefix(80)) + "…" : body
        c.sound    = .default
        let req    = UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }
}
