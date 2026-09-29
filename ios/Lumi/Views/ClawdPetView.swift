import SwiftUI
import WebKit

/// Clawd-on-desk theme asset, used with permission from the theme author.
/// The SVG keeps its own pixel animation and transparent background.
struct ClawdPetView: UIViewRepresentable {
    var assetName: String = "clawd-idle-follow"

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        view.isUserInteractionEnabled = false
        view.loadAsset(named: assetName)
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        guard context.coordinator.loadedAsset != assetName else { return }
        view.loadAsset(named: assetName)
        context.coordinator.loadedAsset = assetName
    }

    func makeCoordinator() -> Coordinator { Coordinator(assetName: assetName) }

    final class Coordinator {
        var loadedAsset: String
        init(assetName: String) { loadedAsset = assetName }
    }
}

private extension WKWebView {
    func loadAsset(named name: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "svg", subdirectory: "PetAssets") else { return }
        loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }
}

