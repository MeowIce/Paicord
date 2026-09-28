import SwiftUI

struct AttachmentOverlay: ViewModifier {
  private let attachments: Set<AnyAttachment>

  init(attachments: Set<AnyAttachment>) {
    self.attachments = attachments
  }

  func body(content: Content) -> some View {
    if attachments.isEmpty {
      content
    } else if #available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *) {
      content
        .overlayPreferenceValue(Text.LayoutKey.self) { value in
          if let anchoredLayout = value.first {
            GeometryReader { geometry in
              AttachmentView(
                attachments: attachments,
                origin: geometry[anchoredLayout.origin],
                layout: anchoredLayout.layout
              )
            }
          }
        }
    } else {
      content
    }
  }
}
