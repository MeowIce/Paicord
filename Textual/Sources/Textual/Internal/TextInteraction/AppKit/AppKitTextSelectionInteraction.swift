#if TEXTUAL_ENABLE_TEXT_SELECTION && canImport(AppKit) && !targetEnvironment(macCatalyst)
  import SwiftUI

  @available(macOS 15, *)
  typealias PlatformTextSelectionInteraction = AppKitTextSelectionInteraction

  @available(macOS 15, *)
  struct AppKitTextSelectionInteraction: ViewModifier {
    @State private var cursorPushed = false

    private let model: TextSelectionModel

    init(model: TextSelectionModel) {
      self.model = model
    }

    func body(content: Content) -> some View {
      content
        .environment(model)
        .overlayPreferenceValue(OverflowFrameKey.self) { frames in
          AppKitTextInteractionOverlay(
            model: model,
            overflowFrames: frames,
            globalOrigin: .zero
          )
          .onContinuousHover { phase in
            updateCursor(for: phase, model: model)
          }
        }
    }

    private func updateCursor(for phase: HoverPhase, model: TextSelectionModel) {
      switch phase {
      case .active(let location):
        let cursor =
          model.url(for: location) != nil
          ? NSCursor.pointingHand
          : NSCursor.iBeam
        if !cursorPushed {
          cursor.push()
          cursorPushed = true
        } else {
          cursor.set()
        }
      case .ended:
        if cursorPushed {
          NSCursor.pop()
          cursorPushed = false
        }
      }
    }
  }
#endif
