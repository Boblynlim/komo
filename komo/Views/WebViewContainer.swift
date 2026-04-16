import SwiftUI
import WebKit

struct WebViewContainer: NSViewRepresentable {
    @ObservedObject var tab: Tab
    @EnvironmentObject var downloadManager: DownloadManager
    @EnvironmentObject var tabManager: TabManager

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        let webView = tab.webView
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        context.coordinator.currentTabID = tab.id
        context.coordinator.downloadManager = downloadManager
        context.coordinator.tabManager = tabManager
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        guard context.coordinator.currentTabID != tab.id else { return }
        context.coordinator.currentTabID = tab.id
        context.coordinator.downloadManager = downloadManager
        context.coordinator.tabManager = tabManager

        container.subviews.forEach { $0.removeFromSuperview() }

        let webView = tab.webView
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(tab: tab)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
        var tab: Tab
        var currentTabID: UUID?
        var downloadManager: DownloadManager?
        weak var tabManager: TabManager?

        init(tab: Tab) {
            self.tab = tab
        }

        // MARK: - WKNavigationDelegate

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            if let url = navigationAction.request.url {
                // Upgrade HTTP to HTTPS
                if url.scheme == "http",
                   var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                    components.scheme = "https"
                    if let httpsURL = components.url {
                        await MainActor.run {
                            webView.load(URLRequest(url: httpsURL))
                        }
                        return .cancel
                    }
                }
            }
            return .allow
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
            if let response = navigationResponse.response as? HTTPURLResponse,
               let contentType = response.value(forHTTPHeaderField: "Content-Type"),
               let contentDisposition = response.value(forHTTPHeaderField: "Content-Disposition"),
               contentDisposition.contains("attachment") || !navigationResponse.canShowMIMEType {
                return .download
            }
            if !navigationResponse.canShowMIMEType {
                return .download
            }
            return .allow
        }

        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
            download.delegate = self
        }

        func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
            download.delegate = self
        }

        // MARK: - WKUIDelegate

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

        // MARK: - WKDownloadDelegate

        func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
            let url = response.url ?? URL(string: "about:blank")!
            return downloadManager?.startDownload(download, suggestedFilename: suggestedFilename, url: url)
        }

        func downloadDidFinish(_ download: WKDownload) {
            downloadManager?.completeDownload(download)
        }

        func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
            downloadManager?.failDownload(download, error: error)
        }
    }
}
