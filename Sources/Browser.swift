import SwiftUI
import WebKit
import Combine

@MainActor
final class TapHandler: NSObject, WKScriptMessageHandler {
    var onTap: (() -> Void)?
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        onTap?()
    }
}

private let tapScript = """
(function(){var f=function(){try{window.webkit.messageHandlers.dlTap.postMessage(1)}catch(e){}};
['touchstart','pointerdown','click','keydown'].forEach(function(t){window.addEventListener(t,f,true)});})();
"""

@MainActor
final class Browser: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    let webView: WKWebView
    @Published var address = ""
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var loading = false
    @Published var progress: Double = 0
    @Published var banner: String?
    private var bag = Set<AnyCancellable>()
    private var lastTap = Date.distantPast

    override init() {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        let handler = TapHandler()
        cfg.userContentController.add(handler, name: "dlTap")
        cfg.userContentController.addUserScript(WKUserScript(source: tapScript, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.allowsBackForwardNavigationGestures = true
        webView = wv
        super.init()
        wv.navigationDelegate = self
        wv.uiDelegate = self
        handler.onTap = { [weak self] in self?.lastTap = Date() }

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
        wv.publisher(for: \.estimatedProgress).receive(on: DispatchQueue.main)
            .sink { [weak self] v in self?.progress = v }
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
            var headers = HTTPCookie.requestHeaderFields(with: matching)
            if let ua { headers["User-Agent"] = ua }
            if let referer { headers["Referer"] = referer }
            let ok = DownloadManager.shared.add(urlString: url.absoluteString, headers: headers, name: name)
            Haptic.success()
            self.flash(ok ? "Download started" : "Couldn't start download")
        }
    }

    func flash(_ text: String) {
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

    // MARK: Links that open in a new tab (target=_blank) and pop-ups

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = navigationAction.request.url else { return nil }
        if navigationAction.shouldPerformDownload, url.scheme != "blob", url.scheme != "data" {
            handOff(url, name: nil)
            return nil
        }
        // Follow taps, and pop-ups opened right after a tap (Google Drive's Download button does this).
        // Pop-ups with no recent tap (typical ads) are ignored.
        let recentTap = Date().timeIntervalSince(lastTap) < 2.0
        let isWeb = ["http", "https"].contains(url.scheme?.lowercased() ?? "")
        if isWeb && (navigationAction.navigationType == .linkActivated || recentTap) {
            webView.load(navigationAction.request)
        }
        return nil
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

struct BrowserView: View {
    @ObservedObject var browser: Browser
    @ObservedObject private var dm = DownloadManager.shared
    @Binding var tab: AppTab
    @State private var input = ""
    @FocusState private var editing: Bool

    private var running: [DownloadRecord] { dm.records.filter { $0.status == .running } }
    private var overall: Double {
        let got = running.reduce(Int64(0)) { $0 + $1.received }
        let all = running.reduce(Int64(0)) { $0 + $1.total }
        return all > 0 ? Double(got) / Double(all) : 0
    }

    private func go(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        Haptic.tap()
        browser.load(t)
        editing = false
    }

    private func pasteAndGo() {
        if let s = UIPasteboard.general.string, !s.isEmpty {
            input = s
            go(s)
        } else {
            Haptic.warn()
        }
    }

    private func copyAddress() {
        guard !browser.address.isEmpty else { return }
        UIPasteboard.general.string = browser.address
        Haptic.success()
        browser.flash("Link copied")
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Button { Haptic.tap(); browser.webView.goBack() } label: {
                    CircleIcon(symbol: "chevron.left", tint: browser.canGoBack ? Theme.text : Theme.sub.opacity(0.5))
                }
                .buttonStyle(PressStyle())
                .disabled(!browser.canGoBack)
                .accessibilityLabel("Back")

                addressBar

                Button { Haptic.tap(); browser.reloadOrStop() } label: {
                    CircleIcon(symbol: browser.loading ? "xmark" : "arrow.clockwise")
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel(browser.loading ? "Stop" : "Reload")
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            ZStack(alignment: .top) {
                WebViewHost(webView: browser.webView)
                if browser.loading {
                    GeometryReader { g in
                        Capsule().fill(Theme.accent)
                            .frame(width: g.size.width * CGFloat(browser.progress), height: 3)
                            .animation(.easeOut(duration: 0.3), value: browser.progress)
                    }
                    .frame(height: 3)
                    .transition(.opacity)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.border, lineWidth: 1))
            .overlay(alignment: .top) {
                if let b = browser.banner {
                    Text(b).font(.mono(12, .semibold)).foregroundColor(Theme.text)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(Theme.button))
                        .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 4)
                        .padding(.top, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .overlay(alignment: .bottom) {
                if !running.isEmpty { miniPanel.padding(10).transition(.move(edge: .bottom).combined(with: .opacity)) }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 100)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: running.isEmpty)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: browser.banner)
        .animation(.easeOut(duration: 0.2), value: browser.loading)
        .onReceive(browser.$address) { if !editing { input = $0 } }
        .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { n in
            // Select the whole address when the bar is tapped, so typing replaces it.
            if let tf = n.object as? UITextField, tf.placeholder == "Search or enter address" {
                DispatchQueue.main.async { tf.selectAll(nil) }
            }
        }
    }

    private var addressBar: some View {
        HStack(spacing: 2) {
            Image(systemName: browser.address.hasPrefix("https") ? "lock.fill" : "globe")
                .font(.system(size: 12))
                .foregroundColor(Theme.sub)
                .padding(.leading, 14)
                .padding(.trailing, 6)
            TextField("Search or enter address", text: $input)
                .font(.mono(13))
                .foregroundColor(Theme.text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.webSearch)
                .submitLabel(.go)
                .focused($editing)
                .onSubmit { go(input) }
            if editing {
                if !input.isEmpty {
                    barButton("xmark.circle.fill", "Clear address") { Haptic.tap(); input = "" }
                }
                barButton("doc.on.clipboard", "Paste and go") { pasteAndGo() }
            } else {
                barButton("doc.on.doc", "Copy link") { copyAddress() }
            }
        }
        .frame(height: 44)
        .background(Capsule().fill(Theme.button))
        .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 4)
        .animation(.easeOut(duration: 0.2), value: editing)
    }

    private func barButton(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Theme.sub)
                .frame(width: 38, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
    }

    private var miniPanel: some View {
        Button {
            Haptic.tap()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { tab = .downloads }
        } label: {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Text("\(running.count) downloading").font(.mono(13, .semibold)).foregroundColor(Theme.text)
                    Spacer(minLength: 4)
                    Tag(text: "\(Int(overall * 100))%", kind: .red)
                    Tag(text: Fmt.speed(dm.totalSpeed), icon: "bolt.fill", kind: .purple)
                    Image(systemName: "chevron.up").font(.system(size: 12, weight: .bold)).foregroundColor(Theme.sub)
                }
                ProgressBar(value: overall)
            }
            .padding(12)
            .card(22)
            .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(PressStyle())
    }
}
