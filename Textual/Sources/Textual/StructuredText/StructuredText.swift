import SwiftUI

public struct StructuredText: View {
  @State private var attributedString = AttributedString()

  private let markup: String
  private let parser: any MarkupParser
  private let revision: AnyHashable

  public init(_ markup: String, parser: any MarkupParser, revision: some Hashable = 0) {
    self.markup = markup
    self.parser = parser
    self.revision = AnyHashable(revision)
    let cacheKey = "\(markup.hashValue)-\(AnyHashable(revision).hashValue)"
    let initialValue: AttributedString
    if let cached = MarkdownParserCache.shared.get(key: cacheKey) {
      initialValue = cached
    } else {
      let parsed = (try? parser.attributedString(for: markup)) ?? AttributedString()
      MarkdownParserCache.shared.set(parsed, for: cacheKey)
      initialValue = parsed
    }
    self._attributedString = State(initialValue: initialValue)
  }

  public var body: some View {
    WithAttachments(attributedString) {
      BlockContent(content: $0)
        .modifier(TextSelectionInteraction())
        .modifier(TextSelectionCoordination())
    }
    .coordinateSpace(.textContainer)
    .onChange(of: markup) {
      markupDidChange(markup)
    }
    .onChange(of: revision) {
      markupDidChange(markup)
    }
    .lineLimit(nil)
  }

  private func markupDidChange(_ markup: String) {
    let cacheKey = "\(markup.hashValue)-\(revision.hashValue)"
    if let cached = MarkdownParserCache.shared.get(key: cacheKey) {
      self.attributedString = cached
    } else {
      let parsed = (try? parser.attributedString(for: markup)) ?? .init()
      MarkdownParserCache.shared.set(parsed, for: cacheKey)
      self.attributedString = parsed
    }
  }
}

extension StructuredText {
  public init(
    markdown: String,
    baseURL: URL? = nil,
    syntaxExtensions: [AttributedStringMarkdownParser.SyntaxExtension] = [],
    revision: some Hashable = 0
  ) {
    self.init(
      markdown,
      parser: .markdown(
        baseURL: baseURL,
        syntaxExtensions: syntaxExtensions
      ),
      revision: revision
    )
  }
}
