import SwiftUI
import WebKit
import Combine

@MainActor
final class Browser: NSObject, ObservableObject, WKNavigationDelegate, WKDownloadDelegate {
    let webView: WKWebView
    @Published var address = ""
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var loading = false
    @Published var banner: String?
    private var bag = Set<AnyCancellable>()

    override init() {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.allowsBackForwardNavigationGestures = true
        webView = wv
        super.init()
        wv.navigationDelegate = self

        wv.publisher(for: \.url).receive(on: DispatchQueue.main)
            .sink { [weak self] u in self?.address = u?.absoluteString ?? "" }
            .store(in: &bag)
        wv.publisher(for: \.canGoBack).receive(on: DispatchQueue.main)
            .sink { [weak self] v in self?.canGoBack = v }
            .store(in: &bag)
        wv.publisher(for: \.canGoForward).receive(on: DispatchQueue.main)
            .sink { [weak self] v in self?.canGoForward = v }
            .store(in: &bag)
        wv.publisher(for: \.isLoading).receive(on: DispatchQueue.main)
            .sink { [weak self] v in self?.loading = v }
            .store(in: &bag)

        load("https://www.google.com")
    }

    func load(_ text: String) {
        var t = text.trimmingCharacters(in: .whitespaces)
        if !t.contains("://") {
            if t.contains(".") && !t.contains(" ") {
                t = "https://" + t
            } else {
                t = "https://www.google.com/search?q=" + (t.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? t)
            }
        }
        if let u = URL(string: t) { webView.load(URLRequest(url: u)) }
    }

    func reloadOrStop() {
        if loading { webView.stopLoading() } else { webView.reload() }
    }

    // MARK: Hand downloads to the background session

    private func handOff(_ url: URL, name: String?) {
        let ua = webView.value(forKey: "userAgent") as? String
        let referer = webView.url?.absoluteString
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            let host = url.host ?? ""
            let matching = cookies.filter { c in
                let d = c.domain.hasPrefix(".") ? String(c.domain.dropFirst()) : c.domain
                return host == d || host.hasSuffix("." + d)
            }
            DownloadManager.shared.start(url: url, cookies: matching, userAgent: ua, referer: referer, name: name)
            self.flash("Download started")
        }
    }

    private func flash(_ text: String) {
        banner = text
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            self.banner = nil
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.allow); return }
        if action.shouldPerformDownload {
            if url.scheme == "blob" || url.scheme == "data" {
                decisionHandler(.download)
            } else {
                handOff(url, name: nil)
                decisionHandler(.cancel)
            }
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let http = response.response as? HTTPURLResponse
        let disp = http?.value(forHTTPHeaderField: "Content-Disposition")?.lowercased() ?? ""
        let isFile = !response.canShowMIMEType || disp.hasPrefix("attachment")
        if response.isForMainFrame && isFile, let url = response.response.url {
            handOff(url, name: response.response.suggestedFilename)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    // MARK: Foreground fallback (blob: / data: URLs)

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        completionHandler(DownloadManager.destination(for: suggestedFilename))
    }

    func downloadDidFinish(_ download: WKDownload) { flash("Saved (keep app open for these)") }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        flash("Download failed: \(error.localizedDescription)")
    }
}

struct WebViewHost: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct BrowserScreen: View {
    @ObservedObject var browser: Browser
    @State private var input = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button { browser.webView.goBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(!browser.canGoBack)
                Button { browser.webView.goForward() } label: { Image(systemName: "chevron.right") }
                    .disabled(!browser.canGoForward)
                TextField("Search or enter address", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.webSearch)
                    .onSubmit { browser.load(input) }
                Button { browser.reloadOrStop() } label: {
                    Image(systemName: browser.loading ? "xmark" : "arrow.clockwise")
                }
            }
            .padding(8)
            ZStack(alignment: .top) {
                WebViewHost(webView: browser.webView)
                if let b = browser.banner {
                    Text(b).padding(8).background(.thinMaterial).cornerRadius(8).padding(.top, 8)
                }
            }
        }
        .onReceive(browser.$address) { input = $0 }
    }
}
