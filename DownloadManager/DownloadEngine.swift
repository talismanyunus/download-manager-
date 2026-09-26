import Foundation
import Combine
import AppKit

enum TransferState: String, Codable {
    case queued, downloading, paused, completed, failed
    var title: String {
        switch self {
        case .queued: return "Sırada"
        case .downloading: return "İndiriliyor"
        case .paused: return "Duraklatıldı"
        case .completed: return "Tamamlandı"
        case .failed: return "Hata"
        }
    }
}

struct Transfer: Identifiable, Codable {
    var id = UUID()
    var source: URL
    var name: String
    var state: TransferState = .queued
    var received: Int64 = 0
    var expected: Int64 = 0
    var created = Date()
    var destination: String
    var filePath: String?
    var resumeData: Data?
    var error: String?
    var scheduledAt: Date?
    var speed: Double = 0
    var connectionCount: Int?
    var statusDetail: String?
    var attempts: Int?
    var isStreamingSite: Bool = false   // yt-dlp ile işlenecek
    var progress: Double { expected > 0 ? min(1, Double(received) / Double(expected)) : 0 }
    var category: String {
        switch (name as NSString).pathExtension.lowercased() {
        case "mp4", "mkv", "mov", "webm", "avi": return "Video"
        case "mp3", "wav", "flac", "m4a", "aac": return "Müzik"
        case "zip", "rar", "7z", "gz", "tar": return "Arşiv"
        case "dmg", "pkg", "app", "iso": return "Uygulama"
        case "pdf", "docx", "xlsx", "txt", "csv": return "Belge"
        default: return "Diğer"
        }
    }
    var symbol: String {
        switch category {
        case "Video": return "film"
        case "Müzik": return "music.note"
        case "Arşiv": return "archivebox"
        case "Uygulama": return "app.dashed"
        case "Belge": return "doc.text"
        default: return "doc"
        }
    }
}

final class DownloadEngine: NSObject, ObservableObject {
    @Published var items: [Transfer] = []
    @Published var maxConcurrent = 3 { didSet { persist(); pump() } }
    @Published var connections = 4 { didSet { persist() } }
    @Published var speedLimitKB = 0 { didSet { persist() } }
    @Published var retryCount = 3 { didSet { persist() } }
    @Published var folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0].path { didSet { persist() } }
    @Published var globalError: String?

    // yt-dlp format seçeneği: "bestvideo+bestaudio/best", "bestvideo[height<=720]+bestaudio/best", "bestaudio/best"
    @Published var ytdlpFormat = "bestvideo+bestaudio/best" { didSet { persist() } }
    /// Çıktı dosya formatı: "mp4", "mkv", "webm", "mp3", "m4a", "original"
    @Published var outputFormat = "mp4" { didSet { persist() } }

    private var workers: [UUID: TransferWorker] = [:]
    private var samples: [UUID: (Date, Int64)] = [:]
    private var waiters: [UUID: [() -> Void]] = [:]
    private var requestHeaders: [UUID: [String: String]] = [:]
    private var timer: Timer?
    private var shuttingDown = false
    private let stateURL: URL
    private let staging: URL
    var onAdded: ((UUID) -> Void)?

    private struct Snapshot: Codable {
        var items: [Transfer]
        var folder: String
        var concurrent: Int
        var connections: Int?
        var speedLimitKB: Int?
        var retryCount: Int?
        var ytdlpFormat: String?
        var outputFormat: String?
    }

    init(storageURL: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DownloadManager", isDirectory: true)
        stateURL = storageURL ?? base.appendingPathComponent("transfers.json")
        staging = stateURL.deletingLastPathComponent().appendingPathComponent("Parts", isDirectory: true)
        super.init()
        if let data = try? Data(contentsOf: stateURL),
           let saved = try? JSONDecoder().decode(Snapshot.self, from: data) {
            items = saved.items.map { item in
                var copy = item
                if copy.state == .downloading { copy.state = .paused }
                copy.speed = 0
                return copy
            }
            folder = saved.folder
            maxConcurrent = min(8, max(1, saved.concurrent))
            connections = min(16, max(1, saved.connections ?? 4))
            speedLimitKB = max(0, saved.speedLimitKB ?? 0)
            retryCount = min(10, max(0, saved.retryCount ?? 3))
            ytdlpFormat = saved.ytdlpFormat ?? "bestvideo+bestaudio/best"
            outputFormat = saved.outputFormat ?? "mp4"
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.pump() }
    }

    var activeCount: Int { items.filter { $0.state == .downloading }.count }
    var totalSpeed: Double { items.reduce(0) { $0 + $1.speed } }
    var completedCount: Int { items.filter { $0.state == .completed }.count }

    // MARK: - yt-dlp kurulum ve otomatik güncelleme
    static let ytdlpCandidates = ["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp", "/usr/bin/yt-dlp"]

    var ytdlpPath: String? {
        Self.ytdlpCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    }

    var ytdlpInstalled: Bool { ytdlpPath != nil }

    @Published var ytdlpUpdateStatus: String = ""          // kullanıcıya gösterilecek durum
    @Published var ytdlpVersion: String = ""               // mevcut sürüm
    @Published var ytdlpInstalling: Bool = false           // kurulum devam ediyor mu

    private let updateCheckIntervalDays: Double = 3        // kaç günde bir kontrol
    private let lastUpdateCheckKey = "ytdlpLastUpdateCheck"

    /// Uygulama açılışında çağrılır. Versiyon okur, gerekirse background günceller.
    func checkAndUpdateYtdlpIfNeeded() {
        guard let path = ytdlpPath else { return }
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self else { return }
            // Mevcut versiyonu oku
            let version = self.runOutput(path, ["--version"]).trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async { self.ytdlpVersion = version.isEmpty ? "bilinmiyor" : version }

            // Son kontrolden yeterli süre geçtiyse otomatik güncelle (sessiz)
            let lastCheck = UserDefaults.standard.double(forKey: self.lastUpdateCheckKey)
            let daysSince = (Date().timeIntervalSince1970 - lastCheck) / 86400
            guard daysSince >= self.updateCheckIntervalDays || lastCheck == 0 else { return }

            DispatchQueue.main.async { self.ytdlpUpdateStatus = "Güncelleme kontrol ediliyor…" }
            self.performUpdate(silent: true)
        }
    }

    /// brew / pip3 ile yt-dlp günceller. silent=true → değişiklik yoksa kullanıcıya göstermez.
    private func performUpdate(silent: Bool) {
        let brewPaths    = ["/opt/homebrew/bin/brew",    "/usr/local/bin/brew"]
        let pip3Paths    = ["/opt/homebrew/bin/pip3",    "/usr/local/bin/pip3",    "/usr/bin/pip3"]
        let python3Paths = ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")

        var didUpdate = false

        // 1. brew upgrade yt-dlp
        if let brew = brewPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            let (code, out) = runOutputWithCode(brew, ["upgrade", "yt-dlp"])
            if code == 0 {
                didUpdate = out.lowercased().contains("upgrading")
                    || out.lowercased().contains("upgraded")
                    || out.contains("yt-dlp")
            }
        }
        // 2. pip3 install --upgrade yt-dlp
        if !didUpdate {
            for pip in pip3Paths where FileManager.default.isExecutableFile(atPath: pip) {
                let (code, _) = runOutputWithCode(pip, ["install", "--upgrade", "yt-dlp"])
                if code == 0 { didUpdate = true; break }
            }
        }
        // 3. python3 -m pip install --upgrade yt-dlp
        if !didUpdate {
            for py in python3Paths where FileManager.default.isExecutableFile(atPath: py) {
                let (code, _) = runOutputWithCode(py, ["-m", "pip", "install", "--upgrade", "yt-dlp"])
                if code == 0 { didUpdate = true; break }
            }
        }

        // Güncel versiyon oku
        let newVersion = ytdlpPath
            .map { runOutput($0, ["--version"]).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""

        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastUpdateCheckKey)

        DispatchQueue.main.async {
            if !newVersion.isEmpty { self.ytdlpVersion = newVersion }
            if silent && !didUpdate {
                self.ytdlpUpdateStatus = ""       // sessiz — zaten günceldi, gösterme
            } else {
                self.ytdlpUpdateStatus = didUpdate
                    ? "yt-dlp güncellendi → \(newVersion) ✓"
                    : "yt-dlp zaten güncel (\(newVersion))"
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    self.ytdlpUpdateStatus = ""
                }
            }
        }
    }

    /// Ayarlar butonu veya menüden manuel güncelleme / kurulum tetikler.
    func updateYtdlpNow() {
        guard ytdlpPath != nil else { installYtdlp(); return }
        guard !ytdlpInstalling else { return }
        ytdlpInstalling = true
        ytdlpUpdateStatus = "Güncelleniyor…"
        UserDefaults.standard.set(0, forKey: lastUpdateCheckKey)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.performUpdate(silent: false)
            DispatchQueue.main.async { self?.ytdlpInstalling = false }
        }
    }

    func installYtdlp() {
        guard !ytdlpInstalling else { return }
        ytdlpInstalling = true
        ytdlpUpdateStatus = "yt-dlp kuruluyor…"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            // 1. Homebrew var mı?
            let brewPaths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
            if let brew = brewPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
                DispatchQueue.main.async { self.ytdlpUpdateStatus = "brew install yt-dlp çalışıyor…" }
                let (code, out) = self.runOutputWithCode(brew, ["install", "yt-dlp"])
                if code == 0 {
                    self.finishInstall()
                    return
                }
                DispatchQueue.main.async {
                    self.ytdlpUpdateStatus = "brew başarısız, pip3 deneniyor…"
                }
            }

            // 2. pip3 fallback
            let pipPaths = ["/opt/homebrew/bin/pip3", "/usr/local/bin/pip3", "/usr/bin/pip3"]
            if let pip = pipPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
                DispatchQueue.main.async { self.ytdlpUpdateStatus = "pip3 install yt-dlp çalışıyor…" }
                let (code, _) = self.runOutputWithCode(pip, ["install", "--upgrade", "yt-dlp"])
                if code == 0 { self.finishInstall(); return }
            }

            // 3. pip3 yolu farklı olabilir — python3 -m pip dene
            let python3Paths = ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"]
            if let py = python3Paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
                DispatchQueue.main.async { self.ytdlpUpdateStatus = "python3 -m pip install yt-dlp…" }
                let (code, _) = self.runOutputWithCode(py, ["-m", "pip", "install", "--upgrade", "yt-dlp"])
                if code == 0 { self.finishInstall(); return }
            }

            // 4. Hiçbiri olmadı
            DispatchQueue.main.async {
                self.ytdlpInstalling = false
                self.ytdlpUpdateStatus = "Kurulum başarısız. Terminal: brew install yt-dlp"
            }
        }
    }

    private func finishInstall() {
        // Kurulum bitti, versiyon oku ve durumu güncelle
        let ver = Self.ytdlpCandidates
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) })
            .map { runOutput($0, ["--version"]).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        DispatchQueue.main.async {
            self.ytdlpInstalling = false
            self.ytdlpVersion    = ver.isEmpty ? "kuruldu" : ver
            self.ytdlpUpdateStatus = "yt-dlp başarıyla kuruldu ✓"
            // objectWillChange tetikle → UI banner'ı gizlensin
            self.objectWillChange.send()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                self.ytdlpUpdateStatus = ""
            }
        }
    }

    /// Process çalıştırıp (exit code, stdout+stderr) döndürür.
    private func runOutputWithCode(_ executable: String, _ args: [String]) -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = args
        // PATH'i genişlet — brew'un bağımlılıklarını bulabilsin
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError  = pipe
        p.standardInput  = FileHandle.nullDevice
        do { try p.run() } catch { return (-1, error.localizedDescription) }
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (p.terminationStatus, out)
    }

    /// Küçük yardımcı: bir process'i çalıştırıp stdout'u string döndürür.
    private func runOutput(_ executable: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        try? p.run(); p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    // MARK: - URL ekleme
    @discardableResult
    func add(_ text: String, scheduledAt: Date? = nil, headers: [String: String] = [:],
             suggestedName: String? = nil, destination: String? = nil, showWindow: Bool = false) -> Int {
        var count = 0
        for line in text.components(separatedBy: .newlines) {
            let cleaned = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { continue }
            guard let url = URL(string: cleaned), Self.validURL(url) else {
                globalError = "Geçerli bir HTTP, HTTPS, FTP veya FTPS bağlantısı girin."
                continue
            }
            let streaming = TransferWorker.isStreamingSite(url)
            // Streaming siteleri için isim "video" olarak başlasın, yt-dlp gerçek adı bulacak
            let rawName: String
            if streaming {
                rawName = suggestedName ?? "video"
            } else {
                rawName = suggestedName ?? (url.lastPathComponent.isEmpty ? "İndirme" : url.lastPathComponent)
            }
            let name = safeName(rawName)
            var item = Transfer(source: url, name: name, destination: destination ?? folder, scheduledAt: scheduledAt)
            item.isStreamingSite = streaming
            items.insert(item, at: 0)
            requestHeaders[item.id] = headers
            count += 1
            if showWindow { onAdded?(item.id) }
        }
        persist(); pump(); return count
    }

    static func validURL(_ url: URL) -> Bool {
        ["http", "https", "ftp", "ftps"].contains(url.scheme?.lowercased() ?? "") && url.host != nil
    }

    // MARK: - Queue pump
    func pump() {
        guard !shuttingDown else { return }
        while workers.count < min(8, max(1, maxConcurrent)) {
            guard let index = items.lastIndex(where: {
                $0.state == .queued && ($0.scheduledAt == nil || $0.scheduledAt! <= Date())
            }) else { break }
            start(index)
        }
    }

    private func start(_ index: Int) {
        let item = items[index], id = item.id
        items[index].state = .downloading
        items[index].error = nil
        items[index].speed = 0
        items[index].statusDetail = item.isStreamingSite ? "Video bilgisi alınıyor…" : "Bağlantı kuruluyor"
        samples[id] = (Date(), item.received)

        let worker = TransferWorker(
            source: item.source,
            directory: staging.appendingPathComponent(id.uuidString),
            connections: min(16, max(1, connections)),
            limit: max(0, speedLimitKB) * 1024,
            headers: requestHeaders[id] ?? [:],
            ytdlpFormat: ytdlpFormat,
            outputFormat: outputFormat,
            progress: { [weak self] progress in
                guard let self,
                      let i = self.items.firstIndex(where: { $0.id == id }),
                      self.items[i].state == .downloading else { return }
                if let previous = self.samples[id] {
                    let elapsed = Date().timeIntervalSince(previous.0)
                    if elapsed > 0.25 {
                        self.items[i].speed = max(0, Double(progress.received - previous.1) / elapsed)
                        self.samples[id] = (Date(), progress.received)
                    }
                }
                self.items[i].received = progress.received
                self.items[i].expected = progress.expected
                self.items[i].connectionCount = progress.connections
                self.items[i].statusDetail = progress.detail
            },
            completion: { [weak self] result in self?.finished(id, result: result) }
        )
        workers[id] = worker; worker.start(); persist()
    }

    private func finished(_ id: UUID, result: WorkerResult) {
        workers.removeValue(forKey: id); samples.removeValue(forKey: id)
        defer {
            let callbacks = waiters.removeValue(forKey: id) ?? []
            persist(); pump(); callbacks.forEach { $0() }
        }
        guard let i = items.firstIndex(where: { $0.id == id }) else { cleanup(id); return }
        items[i].speed = 0
        if result.cancelled || items[i].state == .paused { items[i].state = .paused; return }
        if let file = result.file {
            do {
                let directory = URL(fileURLWithPath: items[i].destination, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let name = safeName(result.name ?? items[i].name)
                var target = directory.appendingPathComponent(name); var suffix = 1
                while FileManager.default.fileExists(atPath: target.path) {
                    let base = (name as NSString).deletingPathExtension
                    let ext = (name as NSString).pathExtension
                    target = directory.appendingPathComponent("\(base) (\(suffix))" + (ext.isEmpty ? "" : ".\(ext)"))
                    suffix += 1
                }
                try FileManager.default.moveItem(at: file, to: target)
                items[i].filePath = target.path
                items[i].name = target.lastPathComponent
                let size = (try? FileManager.default.attributesOfItem(atPath: target.path)[.size] as? NSNumber)?.int64Value ?? 0
                items[i].received = size; items[i].expected = size
                items[i].state = .completed
                items[i].statusDetail = "Tamamlandı"
                items[i].resumeData = nil
                cleanup(id)
            } catch { items[i].state = .failed; items[i].error = error.localizedDescription }
        } else {
            let attempts = items[i].attempts ?? 0
            let message = result.error ?? "İndirme tamamlanamadı."
            let noRetry = message.contains("404") || message.contains("403")
                || message.contains("FFmpeg gerekli") || message.contains("yt-dlp bulunamadı")
            if attempts < retryCount && !noRetry {
                items[i].attempts = attempts + 1
                items[i].state = .queued
                items[i].scheduledAt = Date().addingTimeInterval(pow(2, Double(attempts + 1)))
                items[i].error = "Yeniden denenecek (\(attempts + 1)/\(retryCount)): \(message)"
            } else {
                items[i].state = .failed
                items[i].error = message
            }
        }
    }

    private func cleanup(_ id: UUID) {
        try? FileManager.default.removeItem(at: staging.appendingPathComponent(id.uuidString))
        if let path = requestHeaders[id]?["CookieFile"] { try? FileManager.default.removeItem(atPath: path) }
        requestHeaders.removeValue(forKey: id)
    }

    func pause(_ id: UUID, completion: (() -> Void)? = nil) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { completion?(); return }
        guard [.downloading, .queued, .paused].contains(items[i].state) else { completion?(); return }
        items[i].state = .paused; items[i].speed = 0
        if let worker = workers[id] {
            if let completion { waiters[id, default: []].append(completion) }
            worker.cancel()
        } else { persist(); completion?() }
    }

    func resume(_ id: UUID) {
        guard workers[id] == nil,
              let i = items.firstIndex(where: { $0.id == id }),
              [.paused, .failed].contains(items[i].state) else { return }
        items[i].state = .queued
        items[i].scheduledAt = nil
        items[i].error = nil
        items[i].attempts = 0
        persist(); pump()
    }

    func pauseAll() {
        for id in items.filter({ [.downloading, .queued].contains($0.state) }).map(\.id) { pause(id) }
    }
    func resumeAll() {
        for i in items.indices where items[i].state == .paused && workers[items[i].id] == nil {
            items[i].state = .queued
        }
        persist(); pump()
    }
    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        if let worker = workers[id] { worker.cancel() } else { cleanup(id) }
        persist(); pump()
    }
    func clearCompleted() { items.removeAll { $0.state == .completed }; persist() }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.canCreateDirectories = true; panel.prompt = "Klasör seç"
        if panel.runModal() == .OK, let url = panel.url { folder = url.path; persist() }
    }

    func reveal(_ item: Transfer) {
        if let path = item.filePath {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        }
    }

    func prepareExit(_ done: @escaping () -> Void) {
        shuttingDown = true
        let group = DispatchGroup()
        for id in Array(workers.keys) { group.enter(); pause(id) { group.leave() } }
        group.notify(queue: .main) { self.persist(); done() }
    }

    func persist() {
        do {
            try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let snapshot = Snapshot(items: items, folder: folder, concurrent: maxConcurrent,
                                    connections: connections, speedLimitKB: speedLimitKB,
                                    retryCount: retryCount, ytdlpFormat: ytdlpFormat,
                                    outputFormat: outputFormat)
            try JSONEncoder().encode(snapshot).write(to: stateURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateURL.path)
        } catch { globalError = "İndirme geçmişi kaydedilemedi: \(error.localizedDescription)" }
    }

    private func safeName(_ name: String) -> String {
        let cleaned = name.components(separatedBy: CharacterSet(charactersIn: "/\\:\0\n\r")).joined(separator: "_")
        return cleaned.isEmpty || cleaned == "." || cleaned == ".." ? "İndirme" : String(cleaned.prefix(180))
    }
}

func byteString(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    formatter.allowsNonnumericFormatting = false
    return formatter.string(fromByteCount: bytes)
}
