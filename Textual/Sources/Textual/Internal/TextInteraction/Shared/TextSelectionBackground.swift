import SwiftUI

struct TextSelectionBackground: ViewModifier {
  func body(content: Content) -> some View {
    #if TEXTUAL_ENABLE_TEXT_SELECTION && canImport(AppKit) && !targetEnvironment(macCatalyst)
      if #available(macOS 15, *) {
        content.modifier(AppKitTextSelectionBackgroundBody())
      } else {
        content
      }
    #else
      content
    #endif
  }
}

#if TEXTUAL_ENABLE_TEXT_SELECTION && canImport(AppKit) && !targetEnvironment(macCatalyst)
  @available(macOS 15, *)
  private struct AppKitTextSelectionBackgroundBody: ViewModifier {
    @Environment(TextSelectionModel.self) private var textSelectionModel: TextSelectionModel?

    func body(content: Content) -> some View {
      if textSelectionModel?.selectedRange != nil {
        content
          .backgroundPreferenceValue(Text.LayoutKey.self) { value in
            if let anchoredLayout = value.first {
              GeometryReader { geometry in
                AppKitTextSelectionView(
                  layout: anchoredLayout.layout,
                  origin: geometry[anchoredLayout.origin]
                )
              }
            }
          }
      } else {
        content
      }
    }
  }
#endif
