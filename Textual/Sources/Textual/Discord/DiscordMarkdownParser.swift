import Foundation

public struct DiscordMarkdownParser: MarkupParser {
  private let base: AttributedStringMarkdownParser

  public init(
    baseURL: URL? = nil,
    syntaxExtensions: [AttributedStringMarkdownParser.SyntaxExtension] = []
  ) {
    self.base = AttributedStringMarkdownParser(baseURL: baseURL, syntaxExtensions: syntaxExtensions)
  }

  public func attributedString(for input: String) throws -> AttributedString {
    let cacheKey = "discord-\(input.hashValue)"
    if let cached = MarkdownParserCache.shared.get(key: cacheKey) {
      return cached
    }
    let parsed = try base.attributedString(for: DiscordMarkdown.preprocess(input))
    let result = strippingEmphasisFlankingFixMarker(from: applyingUnderline(to: parsed))
    MarkdownParserCache.shared.set(result, for: cacheKey)
    return result
  }

  private func strippingEmphasisFlankingFixMarker(
    from attributedString: AttributedString
  ) -> AttributedString {
    guard
      attributedString.characters.contains(DiscordMarkdown.emphasisFlankingFixMarker)
    else {
      return attributedString
    }

    var output = AttributedString()
    var currentIndex = attributedString.startIndex
    while currentIndex < attributedString.endIndex {
      if let markerIndex = attributedString[currentIndex...].characters.firstIndex(
        of: DiscordMarkdown.emphasisFlankingFixMarker
      ) {
        if currentIndex < markerIndex {
          output.append(attributedString[currentIndex..<markerIndex])
        }
        currentIndex = attributedString.characters.index(after: markerIndex)
      } else {
        output.append(attributedString[currentIndex...])
        break
      }
    }
    return output
  }

  private func applyingUnderline(to attributedString: AttributedString) -> AttributedString {
    guard
      attributedString.runs.contains(where: {
        $0.inlinePresentationIntent?.contains(.inlineHTML) == true
      })
    else {
      return attributedString
    }

    var output = AttributedString()
    var insideUnderline = false

    for run in attributedString.runs {
      let isUnderlineMarker = run.inlinePresentationIntent?.contains(.inlineHTML) == true
      let text = String(attributedString[run.range].characters[...])

      if isUnderlineMarker, text == "<u>" {
        insideUnderline = true
        continue
      }
      if isUnderlineMarker, text == "</u>" {
        insideUnderline = false
        continue
      }

      guard insideUnderline else {
        output.append(attributedString[run.range])
        continue
      }

      var substring = AttributedString(attributedString[run.range])
      substring.underlineStyle = .single
      output.append(substring)
    }

    return output
  }
}

extension MarkupParser where Self == DiscordMarkdownParser {
  public static func discordMarkdown(
    baseURL: URL? = nil,
    syntaxExtensions: [AttributedStringMarkdownParser.SyntaxExtension] = []
  ) -> Self {
    .init(baseURL: baseURL, syntaxExtensions: syntaxExtensions)
  }
}
