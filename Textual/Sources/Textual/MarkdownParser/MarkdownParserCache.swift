import Foundation

final class AttributedStringBox: @unchecked Sendable {
  let value: AttributedString
  init(_ value: AttributedString) {
    self.value = value
  }
}

public final class MarkdownParserCache: @unchecked Sendable {
  public static let shared = MarkdownParserCache()

  private let cache = NSCache<NSString, AttributedStringBox>()

  public init(countLimit: Int = 1000) {
    cache.countLimit = countLimit
  }

  public func get(key: String) -> AttributedString? {
    cache.object(forKey: key as NSString)?.value
  }

  public func set(_ value: AttributedString, for key: String) {
    cache.setObject(AttributedStringBox(value), forKey: key as NSString)
  }

  public func clear() {
    cache.removeAllObjects()
  }
}
