import Foundation

/// A ``MarkupParser`` implementation backed by Foundation’s Markdown support.
///
/// This parser leverages Foundation’s Markdown support and preserves structure via
/// presentation intents.
///
/// This parser can process its output to expand custom emoji and math expressions into
/// inline attachments.
public struct AttributedStringMarkdownParser: MarkupParser {
  private let baseURL: URL?
  private let options: AttributedString.MarkdownParsingOptions
  private let processor: PatternProcessor

  public init(
    baseURL: URL?,
    options: AttributedString.MarkdownParsingOptions = .init(),
    syntaxExtensions: [SyntaxExtension] = []
  ) {
    self.baseURL = baseURL
    self.options = options
    self.processor = PatternProcessor(syntaxExtensions: syntaxExtensions)
  }

  public func attributedString(for input: String) throws -> AttributedString {
    let cacheKey = "\(input.hashValue)"
    if let cached = MarkdownParserCache.shared.get(key: cacheKey) {
      return cached
    }
    let parsed = try processor.expand(
      AttributedString(
        markdown: input,
        including: \.textual,
        options: options,
        baseURL: baseURL
      )
    )
    MarkdownParserCache.shared.set(parsed, for: cacheKey)
    return parsed
  }
}

extension MarkupParser where Self == AttributedStringMarkdownParser {
  /// Creates a Markdown parser configured for inline-only syntax.
  public static func inlineMarkdown(
    baseURL: URL? = nil,
    syntaxExtensions: [AttributedStringMarkdownParser.SyntaxExtension] = []
  ) -> Self {
    .init(
      baseURL: baseURL,
      options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace),
      syntaxExtensions: syntaxExtensions
    )
  }

  /// Creates a Markdown parser configured for full-document syntax.
  public static func markdown(
    baseURL: URL? = nil,
    syntaxExtensions: [AttributedStringMarkdownParser.SyntaxExtension] = []
  ) -> Self {
    .init(
      baseURL: baseURL,
      syntaxExtensions: syntaxExtensions
    )
  }
}
