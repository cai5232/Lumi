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
        let html = """
        <html><head><meta name=\"viewport\" content=\"width=device-width,initial-scale=1,maximum-scale=1\"></head>
        <body style=\"margin:0;background:transparent;overflow:hidden;display:flex;align-items:center;justify-content:center\">
        <img src=\"\(url.lastPathComponent)\" style=\"width:100%;height:100%;object-fit:contain\">
        </body></html>
        """
        loadHTMLString(html, baseURL: url.deletingLastPathComponent())
    }
}

/// An in-app desktop pet. iOS does not allow a normal app to float over other apps,
/// so this stays above every Lumi screen and can be dragged anywhere in the window.
struct DraggableClawdPet: View {
    var assetName: String = "clawd-idle-follow"
    private let size: CGFloat = 112
    @AppStorage("lumi.clawd.pet.x") private var storedX = 0.0
    @AppStorage("lumi.clawd.pet.y") private var storedY = 0.0
    @State private var dragTranslation: CGSize = .zero
    @State private var isDragging = false
    @State private var isTapped = false

    private var visibleAsset: String {
        if isDragging { return "clawd-react-drag" }
        if isTapped { return "clawd-react-double-jump" }
        return assetName
    }

    var body: some View {
        GeometryReader { proxy in
            let fallbackX = proxy.size.width - size / 2 - 18
            let fallbackY = proxy.size.height - max(proxy.safeAreaInsets.bottom, 18) - 190
            let x = storedX > 0 ? storedX : fallbackX
            let y = storedY > 0 ? storedY : fallbackY
            ClawdPetView(assetName: visibleAsset)
                .frame(width: size, height: size)
                .contentShape(Rectangle())
                .position(x: clamp(x + dragTranslation.width, lower: size / 2, upper: proxy.size.width - size / 2),
                          y: clamp(y + dragTranslation.height, lower: size / 2 + proxy.safeAreaInsets.top, upper: proxy.size.height - size / 2))
                .allowsHitTesting(true)
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged {
                            isDragging = true
                            dragTranslation = $0.translation
                        }
                        .onEnded { value in
                            storedX = clamp(x + value.translation.width, lower: size / 2, upper: proxy.size.width - size / 2)
                            storedY = clamp(y + value.translation.height, lower: size / 2 + proxy.safeAreaInsets.top, upper: proxy.size.height - size / 2)
                            dragTranslation = .zero
                            isDragging = false
                        }
                )
                .simultaneousGesture(
                    TapGesture().onEnded {
                        isTapped = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { isTapped = false }
                    }
                )
                .onAppear {
                    if storedX == 0 { storedX = fallbackX }
                    if storedY == 0 { storedY = fallbackY }
                }
        }
        .ignoresSafeArea()
        .allowsHitTesting(true)
    }

    private func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }
}
