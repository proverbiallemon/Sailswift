import SwiftUI
import WebKit

/// A SwiftUI wrapper for WKWebView
struct WebView: NSViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    @Binding var canGoBack: Bool
    var onNavigate: ((URL) -> Void)?

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Only load if the URL changed
        if webView.url != url {
            webView.load(URLRequest(url: url))
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebView

        init(_ parent: WebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
            parent.canGoBack = webView.canGoBack
            if let url = webView.url {
                parent.onNavigate?(url)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
            parent.canGoBack = webView.canGoBack
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
        }
    }
}

/// View for browsing GameBanana in-app
struct GameBananaWebView: View {
    let initialURL: URL
    let onClose: () -> Void

    @State private var isLoading = true
    @State private var canGoBack = false
    @State private var currentURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 12) {
                Button(action: onClose) {
                    Label("Back to Mods", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)

                Divider().frame(height: 20)

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 20, height: 20)
                }

                Text(currentURL?.host ?? "GameBanana")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Spacer()

                Button(action: openInBrowser) {
                    Label("Open in Safari", systemImage: "safari")
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            WebView(
                url: currentURL ?? initialURL,
                isLoading: $isLoading,
                canGoBack: $canGoBack,
                onNavigate: { url in
                    currentURL = url
                }
            )
        }
        .onAppear {
            currentURL = initialURL
        }
    }

    private func openInBrowser() {
        if let url = currentURL {
            NSWorkspace.shared.open(url)
        }
    }
}
