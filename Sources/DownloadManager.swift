import Foundation

struct DownloadItem: Identifiable {
    enum Status { case running, done, failed(String) }
    let id: Int                      // URLSessionTask.taskIdentifier
    var name: String
    var received: Int64 = 0
    var total: Int64 = 0
    var status: Status = .running
    var progress: Double { total > 0 ? Double(received) / Double(total) : 0 }
}

final class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()

    @Published private(set) var items: [DownloadItem] = []
    var backgroundCompletionHandler: (() -> Void)?

    private var resumeData: [Int: Data] = [:]
    private var session: URLSession!

    private override init() {
        super.init()
        let c = URLSessionConfiguration.background(withIdentifier: "com.personal.dlmanager.bg")
        c.isDiscretionary = false            // start immediately, don't wait for charging/Wi-Fi
        c.sessionSendsLaunchEvents = true    // relaunch the app when downloads finish
        c.timeoutIntervalForResource = 7 * 24 * 3600
        session = URLSession(configuration: c, delegate: self, delegateQueue: nil)
        restore()
    }

    // Rebuild the list from tasks the system is still running for us.
    private func restore() {
        session.getAllTasks { tasks in
            for t in tasks {
                self.mutate(t.taskIdentifier, name: t.taskDescription ?? "download") { _ in }
            }
        }
    }

    func start(url: URL, cookies: [HTTPCookie], userAgent: String?, referer: String?, name: String?) {
        var req = URLRequest(url: url)
        if let userAgent { req.setValue(userAgent, forHTTPHeaderField: "User-Agent") }
        if let referer { req.setValue(referer, forHTTPHeaderField: "Referer") }
        for (k, v) in HTTPCookie.requestHeaderFields(with: cookies) { req.setValue(v, forHTTPHeaderField: k) }
        let label = name ?? (url.lastPathComponent.isEmpty ? "download" : url.lastPathComponent)
        let task = session.downloadTask(with: req)
        task.taskDescription = label
        task.resume()
        mutate(task.taskIdentifier, name: label) { _ in }
    }

    func canRetry(_ item: DownloadItem) -> Bool { resumeData[item.id] != nil }

    func retry(_ item: DownloadItem) {
        guard let data = resumeData[item.id] else { return }
        resumeData[item.id] = nil
        let task = session.downloadTask(withResumeData: data)
        task.taskDescription = item.name
        task.resume()
        DispatchQueue.main.async {
            self.items.removeAll { $0.id == item.id }
            self.items.insert(DownloadItem(id: task.taskIdentifier, name: item.name), at: 0)
        }
    }

    func remove(_ item: DownloadItem) {
        session.getAllTasks { tasks in
            tasks.first { $0.taskIdentifier == item.id }?.cancel()
        }
        resumeData[item.id] = nil
        DispatchQueue.main.async { self.items.removeAll { $0.id == item.id } }
    }

    private func mutate(_ id: Int, name: String, _ f: @escaping (inout DownloadItem) -> Void) {
        DispatchQueue.main.async {
            if let i = self.items.firstIndex(where: { $0.id == id }) {
                f(&self.items[i])
            } else {
                var it = DownloadItem(id: id, name: name)
                f(&it)
                self.items.insert(it, at: 0)
            }
        }
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
        mutate(t.taskIdentifier, name: t.taskDescription ?? "download") {
            $0.received = totalBytesWritten
            $0.total = totalBytesExpectedToWrite
        }
    }

    // The temp file is deleted when this returns, so move it right here.
    func urlSession(_ session: URLSession, downloadTask t: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        let fallback = t.taskDescription ?? "download"
        if let http = t.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            mutate(t.taskIdentifier, name: fallback) { $0.status = .failed("HTTP \(http.statusCode)") }
            return
        }
        let name = t.response?.suggestedFilename ?? fallback
        do {
            try FileManager.default.moveItem(at: location, to: Self.destination(for: name))
            mutate(t.taskIdentifier, name: name) { $0.name = name; $0.status = .done }
        } catch {
            mutate(t.taskIdentifier, name: fallback) { $0.status = .failed(error.localizedDescription) }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let ns = error as NSError
        if ns.code == NSURLErrorCancelled && ns.userInfo[NSURLSessionDownloadTaskResumeData] == nil { return }
        if let data = ns.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
            resumeData[task.taskIdentifier] = data
        }
        mutate(task.taskIdentifier, name: task.taskDescription ?? "download") {
            $0.status = .failed(error.localizedDescription)
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            self.backgroundCompletionHandler?()
            self.backgroundCompletionHandler = nil
        }
    }
}
