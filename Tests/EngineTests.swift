import Foundation

@main struct EngineTests {
 static func wait(_ seconds: Double = 15, _ condition: () -> Bool) {
  let deadline = Date().addingTimeInterval(seconds)
  while !condition() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
  precondition(condition(), "Timed out waiting for expected state")
 }
 static func main() throws {
  setbuf(stdout, nil)
  let root = FileManager.default.temporaryDirectory.appendingPathComponent("dm-test-\(UUID())")
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let engine = DownloadEngine(storageURL: root.appendingPathComponent("state.json"))
  engine.folder = root.appendingPathComponent("files").path
  engine.maxConcurrent = 1
  precondition(engine.add("file:///etc/passwd") == 0)
  engine.globalError = nil
  engine.add("http://127.0.0.1:18764/slow")
  let first = engine.items[0].id
  wait { engine.items[0].received > 200_000 || engine.items[0].state == .failed }
  print("initial", engine.items[0].state, engine.items[0].error ?? "ok", engine.items[0].received)
  var paused = false
  engine.pause(first) { paused = true }
  wait { paused }
  precondition(engine.items[0].state == .paused)
  print("PASS pause; resume data:", engine.items[0].resumeData != nil)
  engine.resume(first)
  engine.add("http://127.0.0.1:18764/second")
  precondition(engine.activeCount == 1 && engine.items.contains { $0.state == .queued })
  wait { engine.completedCount == 2 }
  let expected = Data((0..<(256*16384)).map { UInt8($0 % 256) })
  for item in engine.items { precondition(try! Data(contentsOf: URL(fileURLWithPath: item.filePath!)) == expected) }
  precondition(Set(engine.items.compactMap(\.filePath)).count == 2)
  print("PASS resume integrity, concurrency queue, duplicate filename preservation")
  engine.add("http://127.0.0.1:18764/missing")
  wait { engine.items[0].state == .failed }
  precondition(engine.items[0].error?.contains("404") == true)
  print("PASS HTTP error handling")
  engine.add("http://127.0.0.1:18764/scheduled", scheduledAt: Date().addingTimeInterval(1))
  precondition(engine.items[0].state == .queued)
  wait { engine.completedCount == 3 }
  print("PASS scheduled download")
  engine.add("http://127.0.0.1:18764/remove")
  let removed = engine.items[0].id
  engine.remove(removed)
  precondition(!engine.items.contains { $0.id == removed })
  engine.persist()
  let restored = DownloadEngine(storageURL: root.appendingPathComponent("state.json"))
  precondition(restored.completedCount == 3 && restored.maxConcurrent == 1)
  print("PASS active removal and persistent history")
  var stopped = false
  engine.prepareExit { stopped = true }
  wait { stopped }
  print("ALL INTEGRATION TESTS PASSED")
 }
}
