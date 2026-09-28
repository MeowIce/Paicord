# Đặc tả Kỹ thuật: Tối ưu hoá Hiệu năng Cuộn & Dựng hình (Scrolling & Rendering Performance)

## 1. Tổng quan & Mục tiêu

Tài liệu này xác định kiến trúc và giải pháp kỹ thuật nhằm loại bỏ hiện tượng giật lag, drop frame và layout thrashing khi cuộn tin nhắn trong Paicord trên macOS và iOS/iPadOS.

### Mục tiêu Cốt lõi
1. Đảm bảo tốc độ khung hình 60fps/120fps ổn định khi cuộn danh sách tin nhắn.
2. Giảm tải tối đa thời gian chiếm dụng Main Thread của CPU khi phân tích Markdown và xây dựng layout.
3. Loại bỏ toàn bộ các chu kỳ render thừa và tính toán lặp lại trong vòng đời của từng Message Cell.
4. Giữ nguyên 100% tính năng hiện có: hiển thị Markdown Discord, emoji động, popover thông tin người dùng / emoji, tiết lộ spoiler, code highlighting.

---

## 2. Thiết kế Chi tiết Theo Từng Lớp

### Lớp 1: Đường ống Phân tích & Dựng hình Markdown (Textual & MarkdownText)

#### 1.1. Khởi tạo 1-Pass trong `StructuredText`
- **Tập tin**: `Textual/Sources/Textual/StructuredText/StructuredText.swift`
- **Giải pháp**:
  - Khởi tạo giá trị ban đầu cho `@State private var attributedString` trực tiếp trong `init(_:parser:revision:)` bằng cách gọi `(try? parser.attributedString(for: markup)) ?? .init()`.
  - Giữ nguyên `.onChange(of: markup)` và `.onChange(of: revision)` để xử lý các thay đổi động sau đó.
- **Kết quả**: Loại bỏ bước render layout với chuỗi rỗng ban đầu, giảm từ 2 lần render xuống còn 1 lần duy nhất cho mỗi cell khi xuất hiện trên màn hình.

#### 1.2. Bộ nhớ đệm AttributedString (`MarkdownParserCache`)
- **Tập tin**: `Textual/Sources/Textual/MarkdownParser/AttributedStringMarkdownParser.swift`, `Paicord/Common/Chat/Messages/Message Body/Markdown/MarkdownText.swift`
- **Giải pháp**:
  - Xây dựng lớp đệm `MarkdownParserCache` sử dụng `NSCache<NSString, AttributedStringContainer>` với cơ chế luồng an toàn.
  - Khoá bộ nhớ đệm được sinh từ chuỗi nội dung markup, theme identifier, trạng thái spoiler và cờ jumbo emoji.
  - Khi `AttributedStringMarkdownParser.attributedString(for:)` được gọi, hệ thống kiểm tra cache trước khi tiến hành phân tích cú pháp.

#### 1.3. Tiền biên dịch và Cố định Regex Tokenizer
- **Tập tin**: `Textual/Sources/Textual/Discord/DiscordSyntaxExtensions.swift`, `Textual/Sources/Textual/Internal/MarkdownParser/PatternTokenizer.swift`
- **Giải pháp**:
  - Chuyển toàn bộ các biểu thức chính quy (Regex) trong `SyntaxExtension` thành các biến tĩnh (`static let`) được biên dịch một lần.
  - Tránh khởi tạo lại cấu trúc Regex trên mỗi token phân tích cú pháp.

#### 1.4. Thu hẹp Phạm vi Quan sát `RevisionSignature`
- **Tập tin**: `Paicord/Common/Chat/Messages/Message Body/Markdown/MarkdownText.swift`
- **Giải pháp**:
  - Loại bỏ `userCount: GatewayStore.shared.user.users.count` khỏi `RevisionSignature`.
  - Cấu trúc `RevisionSignature` chỉ lưu trữ: `themeID: String`, `revealedSpoilers: Set<String>`.
  - Tránh việc sự kiện Gateway (typing indicator, reaction update, user join) kích hoạt re-parse đồng loạt tất cả tin nhắn trên màn hình.

---

### Lớp 2: Tinh giản Layout & Điều phối Cuộn (ChatView & MessageCell)

#### 2.1. Loại bỏ `GeometryReader` Toàn cục Nền
- **Tập tin**: `Paicord/Common/Chat/Messages/Message Body/Markdown/MarkdownText.swift`
- **Giải pháp**:
  - Loại bỏ modifier `.background(GeometryReader { geometry in documentFrame = geometry.frame(in: .global) ... })`.
  - Xoá bỏ biến `@State private var documentFrame: CGRect = .zero`.
  - Thay đổi cơ chế tính toạ độ neo Popover: Sử dụng toạ độ tương đối được trả về trực tiếp từ `.textual.onEntityTap { url, bounds in ... }` hoặc neo popover trực tiếp vào khung của phần tử được chạm.

#### 2.2. Loại bỏ Trạng thái `isScrolling` Toàn cục
- **Tập tin**: `Paicord/Common/Chat/ChatView.swift`, `Paicord/Common/Chat/Messages/MessageCell.swift`
- **Giải pháp**:
  - Gỡ bỏ `scrollObserver` quan sát `NSView.boundsDidChangeNotification` và `@State private var isScrolling = false` trong `ChatView.swift`.
  - Gỡ bỏ tham số `scrolling: isScrolling` truyền vào `MessageCell`.
  - Trong `MessageCell`, quản lý trạng thái hover trực tiếp thông qua `@State private var cellHighlighted = false` và modifier `.onHover`, không phụ thuộc vào trạng thái cuộn của view cha.

---

### Lớp 3: Tối ưu hoá Tính toán & Bộ đệm Dữ liệu (GuildStore & MessageAuthor)

#### 3.1. Bộ đệm Màu sắc Role Thành viên (`topRoleColor`)
- **Tập tin**: `Paicord/Stores/GuildStore.swift`, `Paicord/Common/Chat/Messages/MessageAuthor.swift`
- **Giải pháp**:
  - Bổ sung phương thức `topColor(for member: Guild.PartialMember) -> Color?` hoặc lưu trữ `topRoleColor` vào `MemberBox`.
  - Màu sắc được tính toán lại chỉ khi danh sách roles của member thay đổi hoặc cấu trúc roles của guild cập nhật, thay vì thực hiện sắp xếp mảng roles trên mỗi lần đánh giá `Username.body`.

#### 3.2. Tinh gọn Kiểm tra Mention trong `MessageCell`
- **Tập tin**: `Paicord/Common/Chat/Messages/MessageCell.swift`
- **Giải pháp**:
  - Rút ngắn điều kiện kiểm tra `userMentioned`: nếu tin nhắn không chứa mention của user hiện tại và không chứa mention role nào của user, thoát sớm mà không cần duyệt sâu vào store.

---

## 3. Xử lý Trường hợp Biên (Edge Cases)

1. **Thay đổi Kích thước Cửa sổ / Giao diện**: Do toạ độ popover được tính toán tại thời điểm người dùng click/tap thay vì cập nhật liên tục lúc cuộn, vị trí popover luôn chuẩn xác và không gây rò rỉ hiệu năng.
2. **Bộ nhớ đệm tràn**: `NSCache` tự động giải phóng bộ nhớ khi hệ thống nhận cảnh báo bộ nhớ (Memory Pressure) trên macOS/iOS.
3. **Cập nhật Theme**: Khi người dùng đổi theme, `themeID` trong `RevisionSignature` thay đổi, kích hoạt cập nhật lại `AttributedString` với màu sắc mới từ cache hoặc parse lại.

---

## 4. Kế hoạch Kiểm thử & Xác minh

1. **Xác minh Biên dịch & Kiểm tra Tĩnh**:
   - Biên dịch thành công toàn bộ dự án `Paicord` và package `Textual`.
2. **Kiểm tra Chức năng**:
   - Bấm vào emoji / mention mở popover đúng vị trí.
   - Bấm vào spoiler mở hiển thị nội dung bị che.
   - Hiển thị đúng màu role của thành viên trong danh sách tin nhắn.
3. **Kiểm tra Hiệu năng Cuộn**:
   - Cuộn nhanh trong các kênh chat có lượng tin nhắn lớn không còn hiện tượng giật cục, CPU Main Thread không bị bão hoà.
