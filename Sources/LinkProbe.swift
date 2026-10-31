import Foundation

enum LinkKind { case file, page, unreachable }

/// Reads only the response headers of a link (then cancels) to tell a real file from a web page.
final class LinkProbe: NSObject, URLSessionDataDelegate {
    private var continuation: CheckedContinuation<LinkKind, Never>?
    private var session: URLSession?

    static func check(_ url: URL) async -> LinkKind {
        await withCheckedContinuation { cont in
            let probe = LinkProbe()
            probe.continuation = cont
            let cfg = URLSessionConfiguration.ephemeral
            cfg.timeoutIntervalForRequest = 12
            let s = URLSession(configuration: cfg, delegate: probe, delegateQueue: nil)
            probe.session = s
            var req = URLRequest(url: url)
            req.setValue("Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
                         forHTTPHeaderField: "User-Agent")
            s.dataTask(with: req).resume()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        completionHandler(.cancel)
        finish(classify(response))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if error != nil { finish(.unreachable) }
    }

    private func classify(_ response: URLResponse) -> LinkKind {
        guard let http = response as? HTTPURLResponse else { return .file }
        let disp = (http.value(forHTTPHeaderField: "Content-Disposition") ?? "").lowercased()
        if disp.contains("attachment") { return .file }
        let mime = (response.mimeType ?? "").lowercased()
        if mime.hasPrefix("text/html") || mime == "application/xhtml+xml" { return .page }
        if http.statusCode >= 400 { return .page }
        return .file
    }

    private func finish(_ kind: LinkKind) {
        guard let c = continuation else { return }
        continuation = nil
        c.resume(returning: kind)
        session?.invalidateAndCancel()
        session = nil
    }
}
