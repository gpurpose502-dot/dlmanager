import Foundation
import UIKit
import UserNotifications

final class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()

    @Published private(set) var records: [DownloadRecord] = []
    var backgroundCompletionHandler: (() -> Void)?

    private let support: URL
    private var session: URLSession!
    private var activeTask: [UUID: Int] = [:]
    private var lastSample: [UUID: (time: Date, bytes: Int64)] = [:]
    private var saveWork: DispatchWorkItem?

    private override init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DLManager", isDirectory: true)
        try? FileManager.default.createDirectory(at: base.appendingPathComponent("resume", isDirectory: true),
                                                 withIntermediateDirectories: true)
        support = base
        super.init()
        load()
        let c = URLSessionConfiguration.background(withIdentifier: "com.personal.dlmanager.bg")
        c.isDiscretionary = false
        c.sessionSendsLaunchEvents = true
        c.timeoutIntervalForResource = 7 * 24 * 3600
        session = URLSession(configuration: c, delegate: self, delegateQueue: nil)
        NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.saveNow() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.reconcile() }
    }

    // MARK: Derived values

    var active: [DownloadRecord] { records.filter { $0.status != .completed } }
    var completed: [DownloadRecord] {
        records.filter { $0.status == .completed }
            .sorted { ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast) }
    }
    var runningCount: Int { records.filter { $0.status == .running }.count }
    var totalSpeed: Double { records.filter { $0.status == .running }.reduce(0) { $0 + $1.speed } }
    var storageUsed: Int64 { records.filter { $0.status == .completed }.reduce(0) { $0 + $1.total } }

    // MARK: Public actions (call on main thread)

    @discardableResult
    func add(urlString: String, headers: [String: String] = [:], name: String? = nil) -> Bool {
        var s = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.contains("://") { s = "https://" + s }
        guard let url = URL(string: s), let host = url.host, !host.isEmpty,
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return false }
        let last = url.lastPathComponent
        let fallback = (last.isEmpty || last == "/") ? host : (last.removingPercentEncoding ?? last)
        let rec = DownloadRecord(url: url.absoluteString, headers: headers,
                                 name: name ?? fallback, nameLocked: name != nil)
        records.insert(rec, at: 0)
        startTask(for: rec, resumeData: nil)
        saveNow()
        updateBadge()
        return true
    }

    func toggle(_ id: UUID) {
        guard let r = record(id) else { return }
        if r.status == .running { pause(id) } else if r.status == .paused || r.status == .failed { resume(id) }
    }

    func pause(_ id: UUID) {
        guard let i = index(id), records[i].status == .running else { return }
        records[i].status = .paused
        records[i].speed = 0
        lastSample[id] = nil
        let key = id.uuidString
        session.getAllTasks { tasks in
            guard let t = tasks.first(where: { $0.taskDescription == key }) as? URLSessionDownloadTask else { return }
            t.cancel(byProducingResumeData: { data in
                DispatchQueue.main.async {
                    if let data { self.storeResume(data, id) }
                    self.saveNow()
                }
            })
        }
        saveNow()
        updateBadge()
    }

    func resume(_ id: UUID) {
        guard let i = index(id), records[i].status == .paused || records[i].status == .failed else { return }
        records[i].status = .running
        records[i].error = nil
        records[i].speed = 0
        lastSample[id] = nil
        let data = loadResume(id)
        if data == nil { records[i].received = 0 }
        startTask(for: records[i], resumeData: data)
        removeResume(id)
        saveNow()
        updateBadge()
    }

    func pauseAll() { for r in records where r.status == .running { pause(r.id) } }
    func resumeAll() { for r in records where r.status == .paused || r.status == .failed { resume(r.id) } }

    /// Stops the download (if any) and removes it from the list. The downloaded file is untouched.
    func cancel(_ id: UUID) {
        activeTask[id] = nil
        lastSample[id] = nil
        let key = id.uuidString
        session.getAllTasks { tasks in
            tasks.filter { $0.taskDescription == key }.forEach { $0.cancel() }
        }
        removeResume(id)
        records.removeAll { $0.id == id }
        saveNow()
        updateBadge()
    }

    func delete(_ id: UUID, withFile: Bool) {
        if withFile, let u = record(id)?.fileURL { try? FileManager.default.removeItem(at: u) }
        cancel(id)
    }

    func redownload(_ r: DownloadRecord) {
        add(urlString: r.url, headers: r.headers, name: nil)
    }

    func clearHistory(deleteFiles: Bool) {
        for r in records where r.status == .completed {
            if deleteFiles, let u = r.fileURL { try? FileManager.default.removeItem(at: u) }
        }
        records.removeAll { $0.status == .completed }
        saveNow()
    }

    func requestNotificationAuth() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    // MARK: Internals

    private func index(_ id: UUID) -> Int? { records.firstIndex { $0.id == id } }
    private func record(_ id: UUID) -> DownloadRecord? { records.first { $0.id == id } }
    private func isCurrent(_ id: UUID, _ tid: Int) -> Bool { activeTask[id] == nil || activeTask[id] == tid }

    private func onMain<T>(_ f: () -> T) -> T {
        Thread.isMainThread ? f() : DispatchQueue.main.sync(execute: f)
    }

    private func startTask(for rec: DownloadRecord, resumeData: Data?) {
        let task: URLSessionDownloadTask
        if let data = resumeData {
            task = session.downloadTask(withResumeData: data)
        } else {
            guard let url = URL(string: rec.url) else { return }
            var req = URLRequest(url: url)
            for (k, v) in rec.headers { req.setValue(v, forHTTPHeaderField: k) }
            req.allowsCellularAccess = !UserDefaults.standard.bool(forKey: "wifiOnly")
            task = session.downloadTask(with: req)
        }
        task.taskDescription = rec.id.uuidString
        activeTask[rec.id] = task.taskIdentifier
        task.resume()
    }

    private func reconcile() {
        session.getAllTasks { tasks in
            DispatchQueue.main.async {
                var live = Set<UUID>()
                for t in tasks {
                    if let d = t.taskDescription, let id = UUID(uuidString: d) {
                        live.insert(id)
                        self.activeTask[id] = t.taskIdentifier
                    }
                }
                for i in self.records.indices where self.records[i].status == .running && !live.contains(self.records[i].id) {
                    self.records[i].status = .failed
                    self.records[i].error = "Interrupted. Tap to retry."
                    self.records[i].speed = 0
                }
                self.saveNow()
                self.updateBadge()
            }
        }
    }

    private func progress(_ id: UUID, _ tid: Int, _ written: Int64, _ expected: Int64, _ suggested: String?) {
        guard let i = index(id), isCurrent(id, tid), records[i].status == .running else { return }
        activeTask[id] = tid
        records[i].received = written
        if expected > 0 { records[i].total = expected }
        if !records[i].nameLocked, let s = suggested, !s.isEmpty { records[i].name = s }
        let now = Date()
        if let last = lastSample[id] {
            let dt = now.timeIntervalSince(last.time)
            if dt >= 0.5 {
                let inst = Double(written - last.bytes) / dt
                let prev = records[i].speed
                records[i].speed = prev > 0 ? prev * 0.6 + inst * 0.4 : max(inst, 0)
                lastSample[id] = (now, written)
            }
        } else {
            lastSample[id] = (now, written)
        }
        scheduleSave()
    }

    private func complete(_ id: UUID, name: String, size: Int64) {
        guard let i = index(id) else { return }
        records[i].status = .completed
        records[i].fileName = name
        records[i].name = name
        records[i].received = size
        records[i].total = size
        records[i].speed = 0
        records[i].error = nil
        records[i].finishedAt = Date()
        activeTask[id] = nil
        lastSample[id] = nil
        removeResume(id)
        saveNow()
        updateBadge()
        notify(title: "Download complete", body: name)
        Haptic.success()
    }

    private func fail(_ id: UUID, _ tid: Int, _ message: String, resume: Data?) {
        guard let i = index(id), isCurrent(id, tid) else { return }
        if let d = resume { storeResume(d, id) }
        records[i].status = .failed
        records[i].error = message
        records[i].speed = 0
        activeTask[id] = nil
        lastSample[id] = nil
        saveNow()
        updateBadge()
        notify(title: "Download failed", body: records[i].name)
        Haptic.warn()
    }

    // MARK: Persistence

    private var recordsURL: URL { support.appendingPathComponent("records.json") }

    private func load() {
        guard let data = try? Data(contentsOf: recordsURL),
              let list = try? JSONDecoder().decode([DownloadRecord].self, from: data) else { return }
        records = list
    }

    func saveNow() {
        saveWork?.cancel()
        saveWork = nil
        if let data = try? JSONEncoder().encode(records) {
            try? data.write(to: recordsURL, options: .atomic)
        }
    }

    private func scheduleSave() {
        if saveWork != nil { return }
        let w = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: w)
    }

    private func resumeURL(_ id: UUID) -> URL { support.appendingPathComponent("resume/\(id.uuidString).bin") }
    private func storeResume(_ d: Data, _ id: UUID) { try? d.write(to: resumeURL(id), options: .atomic) }
    private func loadResume(_ id: UUID) -> Data? { try? Data(contentsOf: resumeURL(id)) }
    private func removeResume(_ id: UUID) { try? FileManager.default.removeItem(at: resumeURL(id)) }

    // MARK: Notifications and badge

    private func notify(title: String, body: String) {
        guard UserDefaults.standard.object(forKey: "notify") as? Bool ?? true else { return }
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    private func updateBadge() {
        UIApplication.shared.applicationIconBadgeNumber = runningCount
    }

    static func destination(for name: String) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let clean = name.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        let base = (clean as NSString).deletingPathExtension
        let ext = (clean as NSString).pathExtension
        var url = docs.appendingPathComponent(clean)
        var n = 1
        while FileManager.default.fileExists(atPath: url.path) {
            let candidate = ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)"
            url = docs.appendingPathComponent(candidate)
            n += 1
        }
        return url
    }
}

extension DownloadManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask t: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard let id = UUID(uuidString: t.taskDescription ?? "") else { return }
        let tid = t.taskIdentifier
        let suggested = t.response?.suggestedFilename
        DispatchQueue.main.async {
            self.progress(id, tid, totalBytesWritten, totalBytesExpectedToWrite, suggested)
        }
    }

    // The temp file is deleted when this returns, so move it right here.
    func urlSession(_ session: URLSession, downloadTask t: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let id = UUID(uuidString: t.taskDescription ?? "") else { return }
        let tid = t.taskIdentifier
        if let http = t.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            DispatchQueue.main.async { self.fail(id, tid, "Server replied HTTP \(http.statusCode)", resume: nil) }
            return
        }
        let info: (name: String, locked: Bool)? = onMain {
            guard let r = self.record(id), self.isCurrent(id, tid) else { return nil }
            return (r.name, r.nameLocked)
        }
        guard let info else { return }
        let suggested = t.response?.suggestedFilename
        let finalName = info.locked ? info.name : (suggested ?? info.name)
        let dest = Self.destination(for: finalName)
        do {
            try FileManager.default.moveItem(at: location, to: dest)
            let attrs = try? FileManager.default.attributesOfItem(atPath: dest.path)
            let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
            DispatchQueue.main.async { self.complete(id, name: dest.lastPathComponent, size: size) }
        } catch {
            let msg = error.localizedDescription
            DispatchQueue.main.async { self.fail(id, tid, msg, resume: nil) }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let id = UUID(uuidString: task.taskDescription ?? "") else { return }
        let ns = error as NSError
        let resume = ns.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        let tid = task.taskIdentifier
        DispatchQueue.main.async {
            // A cancel we caused (pause) is not a failure.
            if ns.code == NSURLErrorCancelled, let i = self.index(id), self.records[i].status != .running { return }
            self.fail(id, tid, ns.localizedDescription, resume: resume)
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            self.backgroundCompletionHandler?()
            self.backgroundCompletionHandler = nil
        }
    }
}
