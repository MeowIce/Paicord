# Kế hoạch Thực thi Tối ưu hoá Hiệu năng Cuộn & Dựng hình (Scrolling & Rendering Optimization)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Triệt tiêu hoàn toàn giật lag và drop frame khi cuộn danh sách tin nhắn chat trong Paicord thông qua tối ưu hoá đường ống dựng hình Textual, xoá bỏ GeometryReader toàn cục, vô hiệu hoá invalidation isScrolling và lập bộ nhớ đệm AttributedString/RoleColor.

**Architecture:** Áp dụng mô hình tối ưu 3 lớp: (1) Cải tiến Textual với khởi tạo 1-pass, bộ nhớ đệm AttributedString và static regexes; (2) Tinh giản MarkdownText và ChatView bằng cách loại bỏ GeometryReader liên tục và cơ chế quan sát cuộn gián đoạn; (3) Tối ưu hoá tầng Store và Message Cell với tính toán role color lười và kiểm tra mention nhanh.

**Tech Stack:** Swift 5.9+, SwiftUI, Textual (Swift Package), AppKit / UIKit, NSCache.

**Spec:** [2026-09-28-scrolling-performance-optimization-design.md](file:///Users/meowice/Documents/Paicord/docs/superpowers/specs/2026-09-28-scrolling-performance-optimization-design.md)

## Global Constraints

- Không để lại bất kỳ comment / ghi chú nào trong mã nguồn code (tuân thủ quy chuẩn dự án).
- Tuyệt đối không sử dụng emoji trong mã nguồn.
- Giữ nguyên 100% chức năng tương tác (popover profile/emoji, spoiler reveal, code blocks).
- Tương thích macOS 14.0+ và iOS 17.0+.

## Review Focus

1. **Popover Anchor Position**: Khi click vào emoji hoặc user mention, popover phải xuất hiện chính xác tại vị trí của ký tự đó thay vì bị lệch toạ độ.
2. **First-frame Text Layout**: Message cell mới xuất hiện trên màn hình phải có đầy đủ nội dung ngay từ frame đầu tiên, không bị giật nhấp nháy do layout rỗng.
3. **Spoiler Interaction**: Nhấp vào spoiler ẩn vẫn hiển thị đúng nội dung và không làm mất trạng thái của các spoiler khác.
4. **Gateway Invalidation Isolation**: Nhận sự kiện typing hoặc reaction từ Gateway không được kích hoạt re-parse toàn bộ danh sách tin nhắn hiển thị.
5. **Theme Switching**: Đổi theme màu trong cài đặt vẫn làm mới toàn bộ màu sắc của `AttributedString` và role colors một cách đồng bộ.

---

### Task 1: Bộ nhớ đệm AttributedString và Cố định Regex trong Textual

**Files:**
- Create: `Textual/Sources/Textual/MarkdownParser/MarkdownParserCache.swift`
- Modify: `Textual/Sources/Textual/MarkdownParser/AttributedStringMarkdownParser.swift:20-35`
- Modify: `Textual/Sources/Textual/Discord/DiscordSyntaxExtensions.swift:1-120`

**Interfaces:**
- Consumes: `MarkupParser`, `AttributedStringMarkdownParser.SyntaxExtension`
- Produces: `MarkdownParserCache.shared.get(for:syntaxHash:)`, `MarkdownParserCache.shared.set(_:for:syntaxHash:)`

- [ ] **Step 1: Tạo bộ nhớ đệm luồng an toàn `MarkdownParserCache`**

Tạo file `Textual/Sources/Textual/MarkdownParser/MarkdownParserCache.swift`:
```swift
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
```

- [ ] **Step 2: Tích hợp Cache vào `AttributedStringMarkdownParser`**

Chỉnh sửa `Textual/Sources/Textual/MarkdownParser/AttributedStringMarkdownParser.swift`:
```swift
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
```

- [ ] **Step 3: Chuyển các Regex trong `DiscordSyntaxExtensions` thành static constants**

Cố định các biểu thức chính quy tĩnh trong `Textual/Sources/Textual/Discord/DiscordSyntaxExtensions.swift`.

- [ ] **Step 4: Kiểm tra biên dịch package Textual**

Run: `swift build --package-path Textual`
Expected: Build complete.

- [ ] **Step 5: Commit**

```bash
git add Textual/Sources/Textual/MarkdownParser/MarkdownParserCache.swift Textual/Sources/Textual/MarkdownParser/AttributedStringMarkdownParser.swift Textual/Sources/Textual/Discord/DiscordSyntaxExtensions.swift
git commit -m "perf: add AttributedString cache and precompile regex tokenizers in Textual"
```

---

### Task 2: Khởi tạo 1-Pass và Tối ưu hoá Toạ độ Hit-testing trong Textual

**Files:**
- Modify: `Textual/Sources/Textual/StructuredText/StructuredText.swift:100-165`
- Modify: `Textual/Sources/Textual/Internal/TextInteraction/Shared/TextLinkInteraction.swift:50-75`

**Interfaces:**
- Consumes: `MarkdownParserCache`, `MarkupParser`
- Produces: `StructuredText.init(_:parser:revision:)` with synchronous initial value, `TextLinkInteraction` reporting local coordinate bounds.

- [ ] **Step 1: Khởi tạo `@State attributedString` đồng bộ trong `StructuredText`**

Chỉnh sửa `Textual/Sources/Textual/StructuredText/StructuredText.swift`:
```swift
  public init(_ markup: String, parser: any MarkupParser, revision: some Hashable = 0) {
    self.markup = markup
    self.parser = parser
    self.revision = AnyHashable(revision)
    let initialValue = (try? parser.attributedString(for: markup)) ?? AttributedString()
    self._attributedString = State(initialValue: initialValue)
  }
```

- [ ] **Step 2: Cập nhật `TextLinkInteraction` trả về toạ độ tương đối cục bộ**

Chỉnh sửa `Textual/Sources/Textual/Internal/TextInteraction/Shared/TextLinkInteraction.swift`:
```swift
          entityTapAction?(
            url,
            run.typographicBounds.rect.offsetBy(dx: origin.x, dy: origin.y)
          )
```

- [ ] **Step 3: Kiểm tra biên dịch package Textual**

Run: `swift build --package-path Textual`
Expected: Build complete.

- [ ] **Step 4: Commit**

```bash
git add Textual/Sources/Textual/StructuredText/StructuredText.swift Textual/Sources/Textual/Internal/TextInteraction/Shared/TextLinkInteraction.swift
git commit -m "perf: enable 1-pass StructuredText init and local coordinate hit-testing"
```

---

### Task 3: Loại bỏ GeometryReader Nền và Thu hẹp RevisionSignature trong MarkdownText

**Files:**
- Modify: `Paicord/Common/Chat/Messages/Message Body/Markdown/MarkdownText.swift:60-120`, `410-435`, `455-520`

**Interfaces:**
- Consumes: `StructuredText`, `TextLinkInteraction` (local bounds)
- Produces: `MarkdownText.body` without `GeometryReader` background or `documentFrame` state.

- [ ] **Step 1: Loại bỏ `documentFrame` và `GeometryReader` trong `MarkdownText`**

Xoá bỏ `@State private var documentFrame: CGRect = .zero`.
Loại bỏ:
```swift
    .background(
      GeometryReader { geometry in
        documentFrame = geometry.frame(in: .global)
        return Color.clear
      }
    )
```

- [ ] **Step 2: Cập nhật `handleTap` sử dụng toạ độ tương đối trực tiếp**

Trong `MarkdownText.swift`, thay thế việc trừ `documentFrame` bằng việc sử dụng trực tiếp `bounds`:
```swift
        tapLocalPoint = (
          CGPoint(x: bounds.minX, y: bounds.minY),
          CGSize(width: bounds.width, height: bounds.height)
        )
```

- [ ] **Step 3: Thu hẹp `RevisionSignature`**

Loại bỏ `userCount` khỏi `RevisionSignature`:
```swift
  private struct RevisionSignature: Hashable {
    let themeID: String
    let revealedSpoilers: Set<String>
  }

  private var revision: RevisionSignature {
    RevisionSignature(
      themeID: theme.id,
      revealedSpoilers: revealedSpoilers
    )
  }
```

- [ ] **Step 4: Commit**

```bash
git add "Paicord/Common/Chat/Messages/Message Body/Markdown/MarkdownText.swift"
git commit -m "perf: remove continuous GeometryReader and narrow RevisionSignature in MarkdownText"
```

---

### Task 4: Loại bỏ `isScrolling` và Invalidation Vòng lặp Cuộn trong ChatView & MessageCell

**Files:**
- Modify: `Paicord/Common/Chat/ChatView.swift:60-75`, `125-155`
- Modify: `Paicord/Common/Chat/Messages/MessageCell.swift:20-40`, `105-115`

**Interfaces:**
- Consumes: `MessageCell` without `scrolling` parameter
- Produces: Direct hover state management in `MessageCell` without parent scroll invalidations.

- [ ] **Step 1: Loại bỏ quan sát `boundsDidChangeNotification` và `@State isScrolling` trong `ChatView`**

Chỉnh sửa `Paicord/Common/Chat/ChatView.swift`:
- Gỡ bỏ `@State private var isScrolling = false` và `scrollObserver` / `scrollStopWorkItem`.
- Gọi `MessageCell(for: msg, prior: prior, channel: vm)`.

- [ ] **Step 2: Tinh gọn `MessageCell` không nhận `scrolling`**

Chỉnh sửa `Paicord/Common/Chat/Messages/MessageCell.swift`:
- Xoá thuộc tính `var isScrolling: Bool`.
- Đơn giản hoá background hover:
```swift
    #if os(macOS)
      .onHover { self.cellHighlighted = $0 }
      .background(
        cellHighlighted
          ? Color(NSColor.secondaryLabelColor).opacity(0.1) : .clear
      )
    #endif
```

- [ ] **Step 3: Commit**

```bash
git add Paicord/Common/Chat/ChatView.swift Paicord/Common/Chat/Messages/MessageCell.swift
git commit -m "perf: remove isScrolling state and scroll bounds observer"
```

---

### Task 5: Bộ nhớ đệm Role Color và Tối ưu hoá MessageAuthor / MessageCell

**Files:**
- Modify: `Paicord/Stores/GuildStore.swift:50-100`
- Modify: `Paicord/Common/Chat/Messages/MessageAuthor.swift:55-75`
- Modify: `Paicord/Common/Chat/Messages/MessageCell.swift:38-62`

**Interfaces:**
- Consumes: `GuildStore.roleBoxes`
- Produces: `GuildStore.memberTopColor(_:) -> Color?`, fast `userMentioned` in `MessageCell`.

- [ ] **Step 1: Bổ sung phương thức tính và cache màu sắc role trong `GuildStore`**

Chỉnh sửa `Paicord/Stores/GuildStore.swift`:
```swift
  func memberTopColor(for member: Guild.PartialMember) -> Color? {
    guard let roles = member.roles, !roles.isEmpty else { return nil }
    for roleID in roles {
      if let r = roleBoxes[roleID]?.value, r.color.value != 0 {
        return r.color.asColor()
      }
    }
    return nil
  }
```

- [ ] **Step 2: Sử dụng `memberTopColor` trong `MessageAuthor`**

Chỉnh sửa `Paicord/Common/Chat/Messages/MessageAuthor.swift`:
```swift
          if let guildStore, let userID = message.author?.id {
            let member = guildStore.member(userID) ?? message.member
            let color = member.flatMap { guildStore.memberTopColor(for: $0) }
            Text(
              member?.nick ?? message.author?.global_name ?? message.author?.username ?? "Unknown"
            )
            .foregroundStyle(color ?? .primary)
          }
```

- [ ] **Step 3: Tối ưu hoá kiểm tra `userMentioned` trong `MessageCell`**

Chỉnh sửa `Paicord/Common/Chat/Messages/MessageCell.swift`:
```swift
  var userMentioned: Bool {
    if !message.mention_everyone && message.mentions.isEmpty && message.mention_roles.isEmpty {
      return false
    }
    if message.mention_everyone { return true }
    let gw = GatewayStore.shared
    guard let currentUserID = gw.user.currentUser?.id else { return false }
    if message.mentions.contains(where: { $0.id == currentUserID }) {
      return true
    }
    if !message.mention_roles.isEmpty, let userRoles = channelStore.guildStore?.member(currentUserID)?.roles {
      let roleSet = Set(userRoles)
      return message.mention_roles.contains(where: { roleSet.contains($0) })
    }
    return false
  }
```

- [ ] **Step 4: Commit**

```bash
git add Paicord/Stores/GuildStore.swift Paicord/Common/Chat/Messages/MessageAuthor.swift Paicord/Common/Chat/Messages/MessageCell.swift
git commit -m "perf: cache role top color and optimize mention checks"
```

---

### Task 6: Kiểm tra Tổng thể & Xác minh Toàn diện

**Files:**
- Touch: Toàn bộ các files đã cập nhật trong Task 1 - Task 5.

- [ ] **Step 1: Chạy kiểm tra biên dịch Textual và PaicordLib**

Run: `swift test --package-path Textual`
Run: `swift test --package-path PaicordLib`
Expected: Tất cả bài test vượt qua thành công.

- [ ] **Step 2: Kiểm tra linting và formatting**

Đảm bảo không có comment nào trong mã nguồn code và không có emoji trong code.

- [ ] **Step 3: Commit hoàn tất**

```bash
git commit --allow-empty -m "chore: complete scrolling performance optimization milestone"
```
