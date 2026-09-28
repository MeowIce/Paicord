#if TEXTUAL_ENABLE_TEXT_SELECTION && canImport(UIKit)
  import SwiftUI

  @available(iOS 18, *)
  typealias PlatformTextSelectionInteraction = UIKitTextSelectionInteraction

  @available(iOS 18, *)
  struct UIKitTextSelectionInteraction: ViewModifier {
    private let model: TextSelectionModel

    init(model: TextSelectionModel) {
      self.model = model
    }

    func body(content: Content) -> some View {
      content.overlayPreferenceValue(OverflowFrameKey.self) { frames in
        UIKitTextInteractionOverlay(
          model: model,
          overflowFrames: frames,
          globalOrigin: .zero
        )
      }
    }
  }
#endif
