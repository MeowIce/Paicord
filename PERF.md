# Báo cáo Phân tích Hiệu năng & Kế hoạch Tối ưu (PERF.md)

Tài liệu này tổng hợp toàn bộ kết quả điều tra nguyên nhân gốc rễ (Root Causes) gây giật lag, drop frame khi cuộn tin nhắn trong Paicord, cùng các phát hiện tối ưu hoá hiệu năng toàn diện trên toàn bộ hệ thống.

---

## 1. Nguyên nhân Gốc rễ gây Lag & Drop Frame khi Scrolling Chat

Qua điều tra chuyên sâu vào luồng render của `ChatView`, `MessageCell`, `MarkdownText` và bộ parser `Textual`, các nguyên nhân chính gây drop frame gồm:

### 1.1. GeometryReader chạy liên tục trên từng frame cuộn (`MarkdownText.swift`)
- **Vị trí**: [MarkdownText.swift](file:///Users/meowice/Documents/Paicord/Paicord/Common/Chat/Messages/Message%20Body/Markdown/MarkdownText.swift#L77-L81)
- **Vấn đề**: Mỗi tin nhắn đều đính kèm một `.background(GeometryReader { geometry in documentFrame = geometry.frame(in: .global) ... })`.
- **Hậu quả**: Khi cuộn, toạ độ global frame của mọi tin nhắn đang hiển thị thay đổi liên tục trên từng pixel. Điều này ép SwiftUI phải thực hiện tính toán layout pass và cập nhật state cho hàng chục `GeometryReader` trên mỗi frame hình (60Hz / 120Hz Promotion).
- **Mục đích thực tế**: Biến `documentFrame` chỉ được dùng để tính điểm neo popover khi người dùng bấm vào emoji/mention. Việc đo đạc toàn cục liên tục trong lúc cuộn là hoàn toàn không cần thiết.

### 1.2. Khởi tạo hai bước và thiếu Cache trong Markdown Parser (`StructuredText.swift` & `AttributedStringMarkdownParser.swift`)
- **Vị trí**: [StructuredText.swift](file:///Users/meowice/Documents/Paicord/Textual/Sources/Textual/StructuredText/StructuredText.swift#L105-L164), [AttributedStringMarkdownParser.swift](file:///Users/meowice/Documents/Paicord/Textual/Sources/Textual/MarkdownParser/AttributedStringMarkdownParser.swift#L25-L34)
- **Vấn đề**:
  1. `StructuredText` khởi tạo với `@State private var attributedString = AttributedString()` (rỗng).
  2. Khi cell cuộn vào viewport, SwiftUI render layout rỗng trước, sau đó `.onChange(of: markup, initial: true)` mới gọi `parser.attributedString(for: markup)` và gán lại state.
  3. Quá trình này gây ra **Layout Thrashing** (mỗi message cell bị đo và render 2 lần khi xuất hiện).
  4. Quá trình parse Markdown của Foundation kết hợp 8+ Regex Tokenizers của `Textual` chạy đồng bộ trên Main Thread mà không có tầng bộ nhớ đệm (Cache). Khi cuộn qua lại các tin nhắn cũ, toàn bộ quá trình parse này bị lặp lại từ đầu.

### 1.3. `RevisionSignature` kích hoạt re-parse toàn bộ tin nhắn trong kênh (`MarkdownText.swift`)
- **Vị trí**: [MarkdownText.swift](file:///Users/meowice/Documents/Paicord/Paicord/Common/Chat/Messages/Message%20Body/Markdown/MarkdownText.swift#L411-L429)
- **Vấn đề**: `RevisionSignature` trong `MarkdownText` theo dõi biến `userCount: GatewayStore.shared.user.users.count`.
- **Hậu quả**: Mỗi khi Gateway nhận thêm một user mới (ví dụ từ typing event, reaction, mention, hoặc chunk tải về), `users.count` thay đổi. Khi đó, `revision` của **tất cả** tin nhắn đang hiển thị trên màn hình đều thay đổi, kích hoạt `.onChange(of: revision)` và ép toàn bộ các cell parse lại markdown đồng thời trên Main Thread.

### 1.4. `@State isScrolling` kích hoạt re-render toàn bộ ChatView trên macOS (`ChatView.swift`)
- **Vị trí**: [ChatView.swift](file:///Users/meowice/Documents/Paicord/Paicord/Common/Chat/ChatView.swift#L133-L152)
- **Vấn đề**: `ChatView` quan sát `NSView.boundsDidChangeNotification` và liên tục gán `@State private var isScrolling = true` khi cuộn và `false` sau khi dừng.
- **Hậu quả**: Thay đổi `@State` ở cấp độ `ChatView` cha khiến toàn bộ body của `ChatView` và tất cả `MessageCell` (nhận `scrolling: isScrolling`) bị re-evaluate liên tục khi bắt đầu và kết thúc cuộn.

### 1.5. Tính toán lặp lại trong `body` của Message Cell (`Default.swift`, `MessageAuthor.swift`, `MessageCell.swift`)
- **Vị trí**: [MessageAuthor.swift](file:///Users/meowice/Documents/Paicord/Paicord/Common/Chat/Messages/MessageAuthor.swift#L59-L74), [MessageCell.swift](file:///Users/meowice/Documents/Paicord/Paicord/Common/Chat/Messages/MessageCell.swift#L39-L71)
- **Vấn đề**:
  - `MessageAuthor.Username`: Mỗi lần render lại duyệt qua danh sách roles của tác giả, gọi `compactMap { guildStore.role($0) }`, `sorted { $0.position > $1.position }`, lọc mã màu và chuyển đổi sang SwiftUI `Color`.
  - `MessageCell`: Kiểm tra mention (`userMentioned`) bằng cách quét qua mảng mentions/roles của tin nhắn và roles của user hiện tại trên mỗi body evaluation.
  - `getMessage(before:)`: Tìm kiếm chỉ mục trong `OrderedDictionary` theo key cho từng cell trong vòng lặp `ForEach`.

---

## 2. Các Khu vực Tiềm năng Tối ưu Hiệu năng Toàn diện

### 2.1. Tầng Render & Markdown (Textual / MarkdownText)
1. **Tạo Bộ nhớ đệm AttributedString (`MarkdownCache`)**:
   - Lưu trữ kết quả parse theo cặp `(content, syntaxExtensionsHash, themeId)` trong bộ nhớ đệm bộ nhớ `NSCache` hoặc LRU Cache.
   - Tránh parse lại những tin nhắn tĩnh đã hiển thị.
2. **Khởi tạo AttributedString đồng bộ trong initializer hoặc ViewModel**:
   - Tránh việc khởi tạo rỗng rồi cập nhật qua `.onChange`, giảm thiểu số pass render từ 2 xuống 1 cho mỗi message cell.
3. **Tiền biên dịch Regex (Precompiled Regexes)**:
   - Các regex trong `AttributedStringMarkdownParser.SyntaxExtension` hiện đang được khởi tạo lại trong các hàm closure mỗi khi `MarkdownText.body` chạy. Chuyển các regex pattern sang static constants.
4. **Loại bỏ `GeometryReader` toàn cục**:
   - Thay thế bằng coordinate space cục bộ hoặc tính toán toạ độ popover tại thời điểm tương tác (on tap/click).

### 2.2. Tầng Quản lý Trạng thái & Quan sát (@Observable Stores)
1. **Thu hẹp phạm vi quan sát (Granular Observation)**:
   - `ChannelStore` chứa nhiều thuộc tính thay đổi liên tục: `typingTimeoutTokens`, `reactions`, `messages`. Khi một người bắt đầu typing, timer timeout thay đổi làm `ChannelStore` thông báo cập nhật, khiến toàn bộ `ChatView` re-evaluate.
   - Tách `typingUsers` thành một observable model riêng biệt cho thanh `TypingIndicatorBar`.
2. **Cách ly cập nhật Presence trong `GuildStore`**:
   - Tương tự như `CurrentUserStore.presenceBoxes`, sử dụng `ObservableBox` cho presence trong `GuildStore` để tránh việc nhận presence update của một member làm invalidate toàn bộ `GuildStore`.

### 2.3. Tầng Sidebar & Virtualized Member List
1. **Cache màu sắc Role của Member**:
   - Lưu trữ màu hiển thị đã tính toán (`topRoleColor`) vào `MemberBox` hoặc `Guild.PartialMember` thay vì sắp xếp lại toàn bộ role hierarchy trên mỗi frame của `MemberRowView` và `MessageAuthor`.
2. **Tối ưu hoá `GuildMemberList`**:
   - [GuildMemberList.swift](file:///Users/meowice/Documents/Paicord/Paicord/Common/Member%20Sidebar/GuildMemberList.swift#L51-L60): `ForEach(0...accumulator.rowCount)` tạo ra view cho toàn bộ số hàng. Cần đảm bảo `LazyVStack` duy trì chiều cao cố định chính xác để tái sử dụng cell tối đa mà không gây nhảy thanh cuộn.

### 2.4. Tầng Tải Hình ảnh & Đa phương tiện (Nuke & Attachments)
1. **Kích thước ảnh CDN (CDN Downscaling)**:
   - Yêu cầu kích thước avatar/emoji chính xác từ Discord CDN URL (ví dụ `size=64` cho avatar tin nhắn, `size=32` cho emoji) thay vì tải ảnh gốc kích thước lớn rồi resize bằng GPU/CPU.
2. **Khởi tạo Audio Player lười (Lazy AVPlayer)**:
   - [Attachments.swift](file:///Users/meowice/Documents/Paicord/Paicord/Common/Chat/Messages/Message%20Body/Attachments/Attachments.swift#L453-L460): Tránh tạo instance `AVPlayer(url:)` và tải toàn bộ file để trích xuất waveform ngay khi cell xuất hiện; chỉ khởi tạo player và trích xuất waveform khi người dùng bấm phát hoặc khi cell thực sự hiển thị ổn định.

### 2.5. Tầng Tìm kiếm & Điều hướng (Quick Switcher)
1. **Debounce & Tối ưu hoá Index tìm kiếm (`QuickSwitcherProviderStore.swift`)**:
   - [QuickSwitcherProviderStore.swift](file:///Users/meowice/Documents/Paicord/Paicord/Stores/QuickSwitcherProviderStore.swift#L36-L162): Hàm `search(_:)` duyệt tuần tự qua tất cả guild, channel, relationship và sắp xếp mảng kết quả sau mỗi ký tự nhập.
   - Cần thêm cơ chế debounce 100-150ms và chuẩn bị sẵn index danh mục để tìm kiếm nhanh hơn khi tài khoản tham gia hàng trăm server.

---

## 3. Ma trận Đánh giá & Thứ tự Ưu tiên Tối ưu

| Hạng mục | Mức độ ảnh hưởng | Độ phức tạp | Phạm vi file |
| :--- | :--- | :--- | :--- |
| **1. Gỡ bỏ GeometryReader & tinh gọn tính toán toạ độ Popover** | Rất cao (Giảm drop frame tức thì khi cuộn) | Thấp | `MarkdownText.swift` |
| **2. Triển khai Cache cho AttributedString Markdown** | Rất cao (Giảm tải CPU Main Thread) | Trung bình | `MarkdownText.swift`, `Textual` |
| **3. Sửa cơ chế khởi tạo 2 bước trong StructuredText** | Cao (Loại bỏ Layout Thrashing) | Trung bình | `StructuredText.swift` |
| **4. Tối ưu hoá tính toán Role Color & Mention trong Cell** | Cao (Tăng tốc độ render từng cell) | Thấp | `MessageAuthor.swift`, `MessageCell.swift`, `MemberRowView.swift` |
| **5. Cô lập State Typing Indicator khỏi ChatView** | Trung bình | Thấp | `ChannelStore.swift`, `TypingIndicatorBar.swift`, `ChatView.swift` |
| **6. Trì hoãn khởi tạo AVPlayer & Waveform Extractor** | Trung bình | Trung bình | `Attachments.swift` |
| **7. Tách Presence Updates trong GuildStore** | Trung bình | Trung bình | `GuildStore.swift`, `GuildMemberList.swift` |

---

## 4. Kế hoạch Triển khai (Actionable Implementation Plan)

1. **Giai đoạn 1: Khắc phục trực tiếp Scrolling Lag trong ChatView**
   - Loại bỏ `GeometryReader` nền trong `MarkdownText.swift`, chuyển sang tính toạ độ tương đối dựa trên bounds truyền từ `onEntityTap`.
   - Cố định các `SyntaxExtension` Regex tĩnh trong `AttributedStringMarkdownParser`.
   - Tạo bộ nhớ đệm `MarkdownTextCache` cho các tin nhắn đã render.
   - Tối ưu hoá hàm tính màu tác giả (`topRoleColor`) và kiểm tra mention (`userMentioned`) để không tính toán lặp lại trong `body`.

2. **Giai đoạn 2: Tối ưu hoá Kiến trúc Render của Textual**
   - Điều chỉnh `StructuredText` để khởi tạo sẵn `AttributedString` từ cache đồng bộ, tránh bước render rỗng ban đầu.
   - Tinh chỉnh `WithAttachments` để chỉ chạy task resolve emoji khi `attributedString` thực sự chứa emoji attachment cần xử lý.

3. **Giai đoạn 3: Tối ưu hoá Memory & Media Pipelines**
   - Thêm bộ xử lý kích thước ảnh CDN cho Nuke.
   - Chuyển `AttachmentAudioPlayer` sang cơ chế lazy load khi người dùng tương tác.
   - Debounce luồng tìm kiếm `QuickSwitcherProviderStore`.
