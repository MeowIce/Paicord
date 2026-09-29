import Foundation

extension AttributedStringMarkdownParser {
  struct PatternProcessor {
    private let syntaxExtensions: [SyntaxExtension]
    private let tokenizer: PatternTokenizer

    init(syntaxExtensions: [SyntaxExtension]) {
      self.syntaxExtensions = syntaxExtensions
      self.tokenizer = PatternTokenizer(patterns: syntaxExtensions.flatMap(\.patterns))
    }

    func expand(_ attributedString: AttributedString) throws -> AttributedString {
      guard !syntaxExtensions.isEmpty else {
        return attributedString
      }

      var output = AttributedString()
      var runDiscriminator = 0

      for run in attributedString.runs {
        if run.isPreformatted {
          output.append(attributedString[run.range])
        } else {
          let text = String(attributedString[run.range].characters[...])
          let tokens = try tokenizer.tokenize(text)

          if tokens.count == 1, tokens.first?.type == .text {
            output.append(attributedString[run.range])
          } else {
            for token in tokens {
              if let syntaxExtension = syntaxExtensions.firstMatching(token.type),
                var replacement = syntaxExtension.replace(token, run.attributes)
              {
                replacement.textual.runDiscriminator = runDiscriminator
                runDiscriminator += 1
                output.append(replacement)
              } else {
                output.append(AttributedString(token.content, attributes: run.attributes))
              }
            }
          }
        }
      }

      return output
    }
  }
}

extension Array where Element == AttributedStringMarkdownParser.SyntaxExtension {
  func firstMatching(_ tokenType: PatternTokenizer.TokenType) -> Element? {
    guard tokenType != .text else {
      return nil
    }
    return first {
      $0.patterns.contains(where: { $0.tokenType == tokenType })
    }
  }
}

extension AttributedString.Runs.Run {
  fileprivate var isPreformatted: Bool {
    if self.inlinePresentationIntent?.isPreformatted ?? false {
      return true
    }

    if self.presentationIntent?.isPreformatted ?? false {
      return true
    }

    return false
  }
}

extension InlinePresentationIntent {
  fileprivate var isPreformatted: Bool {
    contains(.code) || contains(.inlineHTML) || contains(.blockHTML)
  }
}

extension PresentationIntent {
  fileprivate var isPreformatted: Bool {
    components.first?.kind.isPreformatted ?? false
  }
}

extension PresentationIntent.Kind {
  fileprivate var isPreformatted: Bool {
    switch self {
    case .codeBlock:
      return true
    default:
      return false
    }
  }
}
