import SwiftUI

struct TextFragment<Content: AttributedStringProtocol>: View {
  @Environment(\.textEnvironment) private var textEnvironment
  @State private var textBuilder: TextBuilder?

  private let content: Content

  init(_ content: Content) {
    self.content = content
  }

  var body: some View {
    let builder = currentBuilder
    taggedText(for: builder.text)
      .onGeometryChange(for: CGSize?.self, of: \.textContainerSize) { size in
        guard let size else { return }
        builder.sizeChanged(size, environment: textEnvironment)
      }
      .onChange(of: content) { _, newValue in
        self.textBuilder = TextBuilder(newValue, environment: textEnvironment)
      }
      .modifier(TextSelectionBackground())
      .modifier(RoundedInlineBackground())
      .modifier(AttachmentOverlay(attachments: content.attachments()))
      .modifier(TextLinkInteraction())
  }

  private var currentBuilder: TextBuilder {
    if let textBuilder {
      return textBuilder
    }
    return TextBuilder(content, environment: textEnvironment)
  }

  @ViewBuilder private func taggedText(for text: Text) -> some View {
    if #available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *) {
      text.customAttribute(TextFragmentAttribute())
    } else {
      text
    }
  }
}

@available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
struct TextFragmentAttribute: TextAttribute {}

@available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
extension Text.Layout {
  var isTextFragment: Bool {
    first?.first?[TextFragmentAttribute.self] != nil
  }
}

extension CoordinateSpaceProtocol where Self == NamedCoordinateSpace {
  static var textContainer: NamedCoordinateSpace {
    .named("textContainer")
  }
}

extension GeometryProxy {
  fileprivate var textContainerSize: CGSize? {
    bounds(of: .textContainer)?.size
  }
}
