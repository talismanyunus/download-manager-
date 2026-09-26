import Foundation

struct WorkerProgress {
    var received: Int64
    var expected: Int64
    var connections: Int
    var detail: String
}
struct WorkerResult {
    var file: URL?
    var name: String?
    var error: String?
    var cancelled = false
}

// MARK: - yt-dlp / HLS destekleyen siteler
// Bilinen video platformları + HLS/m3u8 kullanan film/dizi siteleri
private let ytdlpHosts: Set<String> = [
    // Büyük platformlar
    "youtube.com", "www.youtube.com", "youtu.be", "m.youtube.com",
    "vimeo.com", "www.vimeo.com",
    "twitter.com", "www.twitter.com", "x.com", "www.x.com",
    "instagram.com", "www.instagram.com",
    "facebook.com", "www.facebook.com", "fb.watch",
    "tiktok.com", "www.tiktok.com",
    "dailymotion.com", "www.dailymotion.com",
    "twitch.tv", "www.twitch.tv",
    "reddit.com", "www.reddit.com",
    "bilibili.com", "www.bilibili.com",
    "soundcloud.com", "www.soundcloud.com",
    "bandcamp.com",
    "rumble.com", "www.rumble.com",
    "odysee.com", "www.odysee.com",
    // Türk film/dizi siteleri
    "hdfilmcehennemi.com", "www.hdfilmcehennemi.com",
    "hdfilmcehennemi2.com", "www.hdfilmcehennemi2.com",
    "dizipal.com", "www.dizipal.com",
    "diziwatch.com", "www.diziwatch.com",
    "filmizlesene.com", "www.filmizlesene.com",
    "yabancidizi.com", "www.yabancidizi.com",
    "turkanime.co", "www.turkanime.co",
    "anizm.net", "www.anizm.net",
    "dizibox.me", "www.dizibox.me",
    "fullhdfilm.co", "www.fullhdfilm.co",
    "sinema1080.com", "www.sinema1080.com",
    "filmmakinesi.com", "www.filmmakinesi.com",
    "jetfilmizle.com", "www.jetfilmizle.com",
    "1080pfilmizle.pw",
    "hdfull.co",
    "dizi.tv", "www.dizi.tv",
    "puhu.tv", "www.puhu.tv",
    "gain.tv", "www.gain.tv",
    "exxen.com", "www.exxen.com",
    "blu.tv", "www.blu.tv",
    "tabii.com", "www.tabii.com",
    "mubi.com", "www.mubi.com",
    // Genel streaming / HLS siteleri
    "streamable.com", "www.streamable.com",
    "streamtape.com", "www.streamtape.com",
    "doodstream.com", "www.doodstream.com",
    "mixdrop.co", "www.mixdrop.co",
    "vidmoly.to",
    "filemoon.sx",
    "upstream.to",
    "vidcloud.co",
    "fembed.com",
    "netu.tv",
    "supervideo.tv",
    "vudeo.net",
    "okru", "ok.ru", "www.ok.ru"
]

/// Each worker owns a private staging directory. Only validated ranges are reused.
final class TransferWorker {
    let source: URL
    let directory: URL
    let connections: Int
    let limit: Int
    let headers: [String: String]
    let ytdlpFormat: String          // e.g. "bestvideo+bestaudio", "bestvideo[height<=720]+bestaudio", "bestaudio"
    let progress: (WorkerProgress) -> Void
    let completion: (WorkerResult) -> Void
    private let lock = NSLock()
    private var cancelled = false
    private var processes: [Process] = []
    private var expected: Int64 = 0
    private var detail = "Sunucu kontrol ediliyor"
    private var currentConnections = 1
    private var ticker: DispatchSourceTimer?
    private struct Metadata: Codable, Equatable {
        var url: String
        var size: Int64
        var validator: String
        var chunkSize: Int64
    }
    init(source: URL, directory: URL, connections: Int, limit: Int, headers: [String: String],
         ytdlpFormat: String = "bestvideo+bestaudio/best",
         progress: @escaping (WorkerProgress) -> Void, completion: @escaping (WorkerResult) -> Void) {
        self.source = source; self.directory = directory; self.connections = connections
        self.limit = limit; self.headers = headers; self.ytdlpFormat = ytdlpFormat
        self.progress = progress; self.completion = completion
    }
    private var stopped: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() {
        lock.lock(); cancelled = true
        for process in processes where process.isRunning { process.terminate() }
        lock.unlock()
    }
    func start() {
        DispatchQueue.global(qos: .utility).async {
            do {
                try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
                self.beginProgress()
                let result = try self.perform()
                self.ticker?.cancel()
                DispatchQueue.main.async { self.completion(self.stopped ? WorkerResult(cancelled: true) : result) }
            } catch {
                self.ticker?.cancel()
                DispatchQueue.main.async { self.completion(WorkerResult(error: error.localizedDescription, cancelled: self.stopped)) }
            }
        }
    }
    private func status(_ expected: Int64, _ count: Int, _ text: String) {
        lock.lock(); self.expected = expected; currentConnections = count; detail = text; lock.unlock()
    }
    private func beginProgress() {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now(), repeating: .milliseconds(400))
        timer.setEventHandler { [weak self] in
            guard let self, !self.stopped else { return }
            let files = (try? FileManager.default.contentsOfDirectory(at: self.directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
            let bytes = files.filter { ["part", "pending", "payload", "ytdlp"].contains($0.pathExtension) }.reduce(Int64(0)) { sum, file in
                sum + Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
            self.lock.lock(); let p = WorkerProgress(received: bytes, expected: self.expected, connections: self.currentConnections, detail: self.detail); self.lock.unlock()
            DispatchQueue.main.async { self.progress(p) }
        }
        ticker = timer; timer.resume()
    }

    // MARK: - Process runner

    /// curl'ü çalıştırır (executable = /usr/bin/curl varsayılan)
    @discardableResult private func curl(_ args: [String], log: String) throws -> Int32 {
        try run("/usr/bin/curl", args, log: log)
    }

    @discardableResult private func run(_ executable: String, _ args: [String], log: String) throws -> Int32 {
        if stopped { return -999 }
        let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = args
        let logURL = directory.appendingPathComponent(log)
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: logURL)
        defer { try? handle.close() }
        process.standardOutput = FileHandle.nullDevice; process.standardError = handle
        process.standardInput = FileHandle.nullDevice
        lock.lock()
        if cancelled { lock.unlock(); return -999 }
        do { try process.run(); processes.append(process); lock.unlock() }
        catch { lock.unlock(); throw error }
        process.waitUntilExit()
        lock.lock(); processes.removeAll { $0 === process }; lock.unlock()
        return process.terminationStatus
    }

    /// yt-dlp'yi çalıştırır ve stdout'tan progress satırlarını gerçek zamanlı okur.
    private func runYtdlp(_ executable: String, _ args: [String]) throws -> Int32 {
        if stopped { return -999 }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args

        // stderr → log dosyası
        let logURL = directory.appendingPathComponent("ytdlp.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let errHandle = try FileHandle(forWritingTo: logURL)
        process.standardError = errHandle
        process.standardInput = FileHandle.nullDevice

        // stdout → pipe (progress satırlarını parse et)
        let outPipe = Pipe()
        process.standardOutput = outPipe
        var stdoutBuf = Data()

        lock.lock()
        if cancelled { lock.unlock(); try? errHandle.close(); return -999 }
        do { try process.run(); processes.append(process); lock.unlock() }
        catch { lock.unlock(); try? errHandle.close(); throw error }

        // Arka planda stdout'u oku
        let readQueue = DispatchQueue(label: "ytdlp.stdout")
        readQueue.async { [weak self] in
            guard let self else { return }
            let fh = outPipe.fileHandleForReading
            while true {
                let chunk = fh.availableData
                if chunk.isEmpty { break }
                stdoutBuf.append(chunk)
                // Satır satır parse et
                while let newline = stdoutBuf.firstIndex(of: UInt8(ascii: "\n")) {
                    let lineData = stdoutBuf[stdoutBuf.startIndex...newline]
                    stdoutBuf = stdoutBuf[stdoutBuf.index(after: newline)...]
                    if let line = String(data: lineData, encoding: .utf8) {
                        self.parseYtdlpLine(line.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                }
            }
            try? fh.close()
        }

        process.waitUntilExit()
        try? errHandle.close()
        lock.lock(); processes.removeAll { $0 === process }; lock.unlock()
        return process.terminationStatus
    }

    /// yt-dlp --progress-template satırlarını parse ederek status günceller.
    private func parseYtdlpLine(_ line: String) {
        // Progress template: YTPROG|downloaded_bytes|total_bytes|speed|eta
        if line.hasPrefix("YTPROG|") {
            let parts = line.dropFirst(7).components(separatedBy: "|")
            guard parts.count >= 2 else { return }

            let recv  = Int64(parts[0]) ?? 0
            let total = Int64(parts[1]) ?? 0

            // Hız: float bytes/s → okunabilir string
            let speedFormatted: String
            if parts.count > 2, let speedVal = Double(parts[2]), speedVal > 0 {
                speedFormatted = byteString(Int64(speedVal)) + "/sn"
            } else {
                speedFormatted = ""
            }

            // ETA: float saniye → "X dk Y sn"
            let etaFormatted: String
            if parts.count > 3, let etaVal = Double(parts[3]), etaVal > 0 {
                let secs = Int(etaVal)
                if secs < 60        { etaFormatted = "\(secs) sn" }
                else if secs < 3600 { etaFormatted = "\(secs/60) dk \(secs%60) sn" }
                else                { etaFormatted = "\(secs/3600) sa \(secs%3600/60) dk" }
            } else {
                etaFormatted = ""
            }

            // Sadece yüzde ve kalan süre — "yt-dlp ile indiriliyor" yok
            var detail = ""
            if total > 0 {
                let pct = Int(Double(recv) / Double(total) * 100)
                detail = "\(pct)%"
            }
            if !speedFormatted.isEmpty { detail += detail.isEmpty ? speedFormatted : "  ·  \(speedFormatted)" }
            if !etaFormatted.isEmpty   { detail += "  ·  \(etaFormatted) kaldı" }

            lock.lock()
            self.expected = total
            self.detail   = detail.isEmpty ? "İndiriliyor…" : detail
            lock.unlock()

            let p = WorkerProgress(received: recv, expected: total, connections: 1,
                                   detail: self.detail)
            DispatchQueue.main.async { self.progress(p) }

        } else if line.contains("[Merger]") || line.contains("[VideoRemuxer]") {
            lock.lock(); self.detail = "Birleştiriliyor…"; lock.unlock()
        } else if line.contains("[ExtractAudio]") {
            lock.lock(); self.detail = "Ses çıkarılıyor…"; lock.unlock()
        } else if line.contains("Destination:") || line.contains("has already been downloaded") {
            lock.lock(); self.detail = "İşleniyor…"; lock.unlock()
        }
        // [download] ve diğer yt-dlp log satırlarını görmezden gel
    }

    // MARK: - curl helpers
    private func curlArgs() -> [String] {
        var args = ["--location", "--fail", "--silent", "--show-error", "--connect-timeout", "20", "--max-redirs", "10", "--proto", "=http,https,ftp,ftps", "--proto-redir", "=http,https,ftp,ftps"]
        for (name, value) in headers where !value.contains("\r") && !value.contains("\n") {
            if name.lowercased() == "referer" { args += ["--referer", value] }
            if name.lowercased() == "user-agent" { args += ["--user-agent", value] }
        }
        if let cookieFile = headers["CookieFile"] { args += ["--cookie", cookieFile] }
        return args
    }
    private func readHeaders(_ name: String) -> [String: String] {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)), let text = String(data: data, encoding: .isoLatin1) else { return [:] }
        var result: [String: String] = [:]
        for line in text.components(separatedBy: .newlines) {
            let line = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("HTTP/") { result = [":status": line.split(separator: " ").dropFirst().first.map(String.init) ?? ""] }
            else if let colon = line.firstIndex(of: ":") { result[String(line[..<colon]).lowercased()] = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces) }
        }
        return result
    }
    private func failure(_ log: String, code: Int32) -> WorkerResult {
        let text = (try? String(contentsOf: directory.appendingPathComponent(log), encoding: .utf8)) ?? ""
        return WorkerResult(error: text.isEmpty ? "İndirme başarısız (\(code))." : String(text.suffix(700)))
    }

    // MARK: - URL routing
    static func isStreamingSite(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        // Tam eşleşme veya subdomain kontrolü
        return ytdlpHosts.contains(host)
            || ytdlpHosts.contains { host.hasSuffix("." + $0) }
    }

    private func perform() throws -> WorkerResult {
        // 1. Bilinen streaming site → yt-dlp
        if Self.isStreamingSite(source) {
            return try ytdlp()
        }
        // 2. HLS/DASH manifest URL'si → ffmpeg
        let ext = source.pathExtension.lowercased()
        if ["m3u8", "mpd"].contains(ext) || source.absoluteString.contains("m3u8") {
            return try media()
        }

        // 3. Normal HTTP — HEAD ile kontrol et
        let http = ["http", "https"].contains(source.scheme?.lowercased() ?? "")
        var h: [String: String] = [:]
        var headCode: Int32 = 0
        if http {
            headCode = (try? curl(curlArgs() + [
                "--head", "--max-time", "20",
                "--dump-header", directory.appendingPathComponent("head.txt").path,
                "--url", source.absoluteString
            ], log: "head.log")) ?? -1
            h = readHeaders("head.txt")
        }
        if stopped { return WorkerResult(cancelled: true) }

        // 403/401 → yt-dlp ile dene (Referer ile belki geçer)
        let status = h[":status"] ?? ""
        if headCode != 0 || status == "403" || status == "401" || status == "429" {
            // yt-dlp --referer ile dene
            return try ytdlpWithReferer()
        }

        // Content-Type HLS ise ffmpeg'e yönlendir
        let ct = h["content-type"] ?? ""
        if ct.contains("mpegurl") || ct.contains("x-mpegurl") || ct.contains("vnd.apple.mpegurl") {
            return try media()
        }

        let size      = Int64(h["content-length"] ?? "") ?? 0
        let etag      = h["etag"].flatMap { $0.hasPrefix("W/") ? nil : $0 }
        let validator = etag ?? h["last-modified"] ?? ""
        let filename  = HTTPURLResponse(url: source, statusCode: 200,
                                         httpVersion: "HTTP/1.1", headerFields: h)?
                             .suggestedFilename ?? source.lastPathComponent

        if http && connections > 1 && size >= 2 * 1024 * 1024
            && h["accept-ranges"]?.lowercased() == "bytes"
            && !validator.isEmpty
            && (h["content-encoding"] == nil || h["content-encoding"] == "identity") {
            if let result = try segmented(size: size, validator: validator, filename: filename) {
                return result
            }
            if stopped { return WorkerResult(cancelled: true) }
        }
        let result = try single(size: size, validator: validator, filename: filename, http: http)
        // Single başarısız 403 ise yt-dlp'ye düş
        if let err = result.error, (err.contains("403") || err.contains("401")) {
            return try ytdlpWithReferer()
        }
        return result
    }

    /// 403 alan URL'leri yt-dlp + --referer ile dene
    private func ytdlpWithReferer() throws -> WorkerResult {
        let candidates = ["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp"]
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return WorkerResult(error: "403 hatası — yt-dlp ile yeniden denenemiyor (yt-dlp kurulu değil).")
        }
        status(0, 1, "403 — yt-dlp ile yeniden deneniyor…")
        let referer = headers["Referer"] ?? source.absoluteString
        var args: [String] = [
            "--no-warnings", "--no-playlist", "--socket-timeout", "30",
            "-f", ytdlpFormat,
            "--restrict-filenames",
            "--progress", "--newline",
            "--progress-template", "YTPROG|%(progress.downloaded_bytes)s|%(progress.total_bytes)s|%(progress.speed)s|%(progress.eta)s",
            "--add-header", "Referer:\(referer)",
            "-o", directory.appendingPathComponent("video.%(ext)s").path,
            source.absoluteString
        ]
        let ffmpegCandidates = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]
        if let ffmpeg = ffmpegCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            args += ["--ffmpeg-location", (ffmpeg as NSString).deletingLastPathComponent]
        }
        let code = try runYtdlp(path, args)
        if stopped { return WorkerResult(cancelled: true) }
        if code != 0 {
            let log = (try? String(contentsOf: directory.appendingPathComponent("ytdlp.log"), encoding: .utf8)) ?? ""
            return WorkerResult(error: log.isEmpty ? "İndirme başarısız." : String(log.suffix(500)))
        }
        let videoExts: Set<String> = ["mp4","mkv","webm","m4a","mp3","ts","flv","avi","mov"]
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        guard let best = files.filter({ videoExts.contains($0.pathExtension.lowercased()) })
                              .max(by: { ((try? $0.resourceValues(forKeys:[.fileSizeKey]).fileSize) ?? 0)
                                       < ((try? $1.resourceValues(forKeys:[.fileSizeKey]).fileSize) ?? 0) }) else {
            return WorkerResult(error: "Dosya bulunamadı.")
        }
        return WorkerResult(file: best, name: best.lastPathComponent)
    }

    // MARK: - yt-dlp indirme
    private func ytdlp() throws -> WorkerResult {
        let candidates = ["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp", "/usr/bin/yt-dlp"]
        guard let ytdlpPath = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return WorkerResult(error: "yt-dlp bulunamadı. Terminal: brew install yt-dlp")
        }

        let ffmpegCandidates = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]
        let ffmpegPath = ffmpegCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })

        // PATH ortam değişkenini genişlet
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")

        // Dosya adını al — 30 sn timeout, başarısız olursa template kullan
        status(0, 1, "Video bilgisi alınıyor…")
        var suggestedName: String? = nil

        if !stopped {
            let namePipe = Pipe()
            let nameProc = Process()
            nameProc.executableURL = URL(fileURLWithPath: ytdlpPath)
            nameProc.arguments = [
                "--get-filename", "--no-warnings", "--no-playlist",
                "--socket-timeout", "15",
                "-f", ytdlpFormat,
                "--restrict-filenames",
                source.absoluteString
            ]
            nameProc.standardOutput = namePipe
            nameProc.standardError  = FileHandle.nullDevice
            nameProc.standardInput  = FileHandle.nullDevice
            nameProc.environment    = env

            lock.lock()
            if !cancelled { processes.append(nameProc) }
            lock.unlock()

            if !stopped {
                try? nameProc.run()

                // 30 saniye içinde tamamlanmazsa iptal et
                let nameTimeout = DispatchWorkItem {
                    if nameProc.isRunning { nameProc.terminate() }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: nameTimeout)
                nameProc.waitUntilExit()
                nameTimeout.cancel()

                lock.lock(); processes.removeAll { $0 === nameProc }; lock.unlock()

                if nameProc.terminationStatus == 0 {
                    let data = namePipe.fileHandleForReading.readDataToEndOfFile()
                    if let raw = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .components(separatedBy: .newlines).first,
                       !raw.isEmpty, !raw.contains("ERROR") {
                        let videoExts = ["mp4","mkv","webm","m4a","mp3","flac","opus","ogg","wav","avi","mov"]
                        let hasExt = videoExts.contains(where: { raw.hasSuffix(".\($0)") })
                        suggestedName = hasExt ? raw : raw + ".mp4"
                    }
                }
            }
        }
        if stopped { return WorkerResult(cancelled: true) }

        let outputTemplate: String
        if let name = suggestedName {
            outputTemplate = directory.appendingPathComponent(name).path
        } else {
            outputTemplate = directory.appendingPathComponent("video.%(ext)s").path
        }

        status(0, 1, "İndiriliyor…")

        // Progress template: YTPROG|downloaded_bytes|total_bytes|speed_bytes_per_sec|eta_seconds
        let progressTemplate = "YTPROG|%(progress.downloaded_bytes)s|%(progress.total_bytes)s|%(progress.speed)s|%(progress.eta)s"

        var args: [String] = [
            "--no-warnings", "--no-playlist",
            "--socket-timeout", "30",
            "-f", ytdlpFormat,
            "--restrict-filenames",
            "--progress", "--newline",
            "--progress-template", progressTemplate,
            "-o", outputTemplate
        ]

        if let ffmpeg = ffmpegPath {
            args += ["--ffmpeg-location", (ffmpeg as NSString).deletingLastPathComponent]
        }
        if limit > 0 { args += ["--limit-rate", "\(limit)"] }
        args.append(source.absoluteString)

        let code = try runYtdlp(ytdlpPath, args)
        if stopped { return WorkerResult(cancelled: true) }

        if code != 0 {
            let logText = (try? String(contentsOf: directory.appendingPathComponent("ytdlp.log"),
                                       encoding: .utf8)) ?? ""
            let errMsg = logText.isEmpty
                ? "İndirme başarısız (kod: \(code))."
                : String(logText.suffix(600))
            return WorkerResult(error: errMsg)
        }

        // İndirilen dosyayı bul
        let videoExts: Set<String> = ["mp4","mkv","webm","avi","mov","flv","m4a","mp3","aac","opus","wav","flac","ogg"]
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        let best = files
            .filter { videoExts.contains($0.pathExtension.lowercased()) }
            .max { a, b in
                let sa = (try? a.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                let sb = (try? b.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return sa < sb
            }

        guard let outputFile = best else {
            return WorkerResult(error: "İndirme tamamlandı ama dosya bulunamadı.")
        }
        return WorkerResult(file: outputFile, name: outputFile.lastPathComponent)
    }

    // MARK: - Segmented download
    private func segmented(size: Int64, validator: String, filename: String) throws -> WorkerResult? {
        let chunk: Int64 = max(1024 * 1024, (size + 511) / 512)
        let meta = Metadata(url: source.absoluteString, size: size, validator: validator, chunkSize: chunk)
        let metaURL = directory.appendingPathComponent("ranges.json")
        let old = (try? Data(contentsOf: metaURL)).flatMap { try? JSONDecoder().decode(Metadata.self, from: $0) }
        if old != meta { try clearParts() }
        try JSONEncoder().encode(meta).write(to: metaURL, options: .atomic)
        status(size, connections, "\(connections) bağlantı · Çok parçalı indirme")
        let count = Int((size + chunk - 1) / chunk)
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = connections
        let failureLock = NSLock(); var failed = false
        for index in 0..<count {
            let lower = Int64(index) * chunk, upper = min(size - 1, lower + chunk - 1)
            let part = directory.appendingPathComponent("\(index).part")
            let existing = (try? FileManager.default.attributesOfItem(atPath: part.path)[.size] as? NSNumber)?.int64Value ?? -1
            if existing == upper - lower + 1 { continue }
            queue.addOperation {
                if self.stopped { return }
                failureLock.lock(); let skip = failed; failureLock.unlock(); if skip { return }
                do {
                    let pending = self.directory.appendingPathComponent("\(index).pending")
                    var args = self.curlArgs() + ["--range", "\(lower)-\(upper)", "--header", "If-Range: \(validator)", "--header", "Accept-Encoding: identity", "--max-filesize", "\(upper-lower+1)", "--dump-header", self.directory.appendingPathComponent("\(index).headers").path, "--output", pending.path]
                    if self.limit > 0 { args += ["--limit-rate", "\(max(1, self.limit / self.connections))"] }
                    args += ["--url", self.source.absoluteString]
                    let code = try self.curl(args, log: "\(index).log")
                    let response = self.readHeaders("\(index).headers")
                    let actual = (try? FileManager.default.attributesOfItem(atPath: pending.path)[.size] as? NSNumber)?.int64Value ?? -1
                    guard code == 0, response[":status"] == "206", response["content-range"]?.lowercased() == "bytes \(lower)-\(upper)/\(size)", actual == upper - lower + 1 else {
                        try? FileManager.default.removeItem(at: pending)
                        failureLock.lock(); failed = true; failureLock.unlock(); return
                    }
                    try? FileManager.default.removeItem(at: part)
                    try FileManager.default.moveItem(at: pending, to: part)
                } catch { failureLock.lock(); failed = true; failureLock.unlock() }
            }
        }
        queue.waitUntilAllOperationsAreFinished()
        if stopped { return WorkerResult(cancelled: true) }
        if failed { try clearParts(); return nil }
        status(size, 0, "Parçalar birleştiriliyor")
        let merged = directory.appendingPathComponent("assembled.bin")
        FileManager.default.createFile(atPath: merged.path, contents: nil)
        let output = try FileHandle(forWritingTo: merged); defer { try? output.close() }
        for index in 0..<count {
            if stopped { return WorkerResult(cancelled: true) }
            let input = try FileHandle(forReadingFrom: directory.appendingPathComponent("\(index).part"))
            defer { try? input.close() }
            while let data = try input.read(upToCount: 1024 * 1024), !data.isEmpty { try output.write(contentsOf: data) }
        }
        return WorkerResult(file: merged, name: filename)
    }
    private func clearParts() throws {
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where ["part", "pending"].contains(file.pathExtension) { try FileManager.default.removeItem(at: file) }
    }

    // MARK: - Single connection download
    private func single(size: Int64, validator: String, filename: String, http: Bool) throws -> WorkerResult {
        try clearParts()
        let output = directory.appendingPathComponent("download.payload")
        let meta = Metadata(url: source.absoluteString, size: size, validator: validator, chunkSize: 0)
        let metaURL = directory.appendingPathComponent("single.json")
        let old = (try? Data(contentsOf: metaURL)).flatMap { try? JSONDecoder().decode(Metadata.self, from: $0) }
        if old != meta || (http && validator.isEmpty) { try? FileManager.default.removeItem(at: output) }
        try JSONEncoder().encode(meta).write(to: metaURL, options: .atomic)
        status(size, 1, "Tek bağlantı" + (limit > 0 ? " · Hız sınırı etkin" : ""))
        var args = curlArgs() + ["--output", output.path, "--dump-header", directory.appendingPathComponent("single.headers").path]
        if limit > 0 { args += ["--limit-rate", "\(limit)"] }
        let offset = (try? FileManager.default.attributesOfItem(atPath: output.path)[.size] as? NSNumber)?.int64Value ?? 0
        if offset > 0 { args += ["--continue-at", "-"]; if http { args += ["--header", "If-Range: \(validator)"] } }
        var code = try curl(args + ["--url", source.absoluteString], log: "single.log")
        if stopped { return WorkerResult(cancelled: true) }
        if offset > 0 && code != 0 {
            try? FileManager.default.removeItem(at: output)
            var fresh = curlArgs() + ["--output", output.path]
            if limit > 0 { fresh += ["--limit-rate", "\(limit)"] }
            code = try curl(fresh + ["--url", source.absoluteString], log: "single.log")
        }
        if stopped { return WorkerResult(cancelled: true) }
        if code != 0 { return failure("single.log", code: code) }
        return WorkerResult(file: output, name: filename.isEmpty ? "İndirme" : filename)
    }

    // MARK: - HLS/DASH (ffmpeg)
    private func media() throws -> WorkerResult {
        guard let ffmpeg = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]
                .first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return WorkerResult(error: "HLS indirmek için ffmpeg gerekli. Terminal: brew install ffmpeg")
        }
        status(0, 1, "Video akışı indiriliyor…")
        let file = directory.appendingPathComponent("media.ts")
        var args = ["-nostdin", "-y", "-loglevel", "error",
                    "-protocol_whitelist", "file,http,https,tcp,tls,crypto,hls,applehttp",
                    "-rw_timeout", "30000000"]

        // Referer ve User-Agent — film siteleri için kritik
        let referer   = headers["Referer"]    ?? headers["referer"]    ?? ""
        let userAgent = headers["User-Agent"] ?? headers["user-agent"] ?? "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

        if !referer.isEmpty   { args += ["-referer",    referer] }
        args += ["-user_agent", userAgent]
        // headers parametresi olarak Referer'ı ekle
        if !referer.isEmpty {
            args += ["-headers", "Referer: \(referer)\r\n"]
        }

        args += ["-i", source.absoluteString,
                 "-map", "0:v:0?", "-map", "0:a:0?",
                 "-c", "copy", "-f", "mpegts", file.path]
        let code = try run(ffmpeg, args, log: "media.log")
        if stopped { return WorkerResult(cancelled: true) }
        if code != 0 { return failure("media.log", code: code) }
        // mkv çok daha uyumlu — sadece container değişimi
        let mkvFile = directory.appendingPathComponent("media.mkv")
        if let ffmpeg2 = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]
                .first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            _ = try? run(ffmpeg2, ["-nostdin", "-y", "-loglevel", "error",
                                   "-i", file.path, "-c", "copy", mkvFile.path], log: "remux.log")
            if FileManager.default.fileExists(atPath: mkvFile.path) {
                try? FileManager.default.removeItem(at: file)
                let title = source.deletingPathExtension().lastPathComponent
                return WorkerResult(file: mkvFile, name: title + ".mkv")
            }
        }
        let title = source.deletingPathExtension().lastPathComponent
        return WorkerResult(file: file, name: title + ".ts")
    }
}
