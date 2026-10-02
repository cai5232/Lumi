import ReplayKit
import SwiftUI

final class StyledBroadcastPicker: RPSystemBroadcastPickerView {
    override func layoutSubviews() {
        super.layoutSubviews()
        for subview in subviews {
            guard let button = subview as? UIButton else { continue }
            button.frame = bounds
            button.imageView?.contentMode = .scaleAspectFit
            button.tintColor = UIColor(red: 0.82, green: 0.42, blue: 0.58, alpha: 1)
        }
    }
}

struct BroadcastPickerView: UIViewRepresentable {
    let preferredExtension: String

    func makeUIView(context: Context) -> StyledBroadcastPicker {
        let picker = StyledBroadcastPicker(frame: .zero)
        picker.preferredExtension = preferredExtension
        picker.showsMicrophoneButton = false
        picker.isUserInteractionEnabled = true
        return picker
    }

    func updateUIView(_ uiView: StyledBroadcastPicker, context: Context) {
        uiView.preferredExtension = preferredExtension
    }
}
