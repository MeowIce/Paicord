# Bối cảnh Dự án Paicord

Paicord là một ứng dụng Discord client native cho macOS (14.0+) và iOS/iPadOS (17.0+), được viết hoàn toàn bằng Swift và SwiftUI. Dự án hướng tới mục tiêu tương đương tính năng với ứng dụng Discord chính thức, mang lại trải nghiệm thuần native, hiệu năng cao, hỗ trợ đa tài khoản, tuỳ biến giao diện và các cải tiến trải nghiệm người dùng.

## Cấu trúc Dự án

1. **Paicord (Ứng dụng chính)**
   - **App Lifecycle & Navigation**: Quản lý vòng đời ứng dụng (`PaicordApp`, `RootView`, `PaicordAppState`).
   - **Baseplates**:
     - `LargeBaseplate`: Dành cho macOS và iPadOS (NavigationSplitView 3 cột: Server Rail / Channel List, Chat View, Member Sidebar / Profile).
     - `SmallBaseplate`: Dành cho iPhone (SlideoverDoubleView trượt giữa TabView Home/Notifications/Profile và Chat View).
   - **State Management & Stores (`Paicord/Stores/`)**:
     - `GatewayStore`: Store trung tâm quản lý kết nối Gateway, điều phối các sub-stores và cache.
     - `CurrentUserStore`: Quản lý thông tin tài khoản hiện tại, danh sách server, DM, bạn bè, trạng thái presence, sessions, emoji/sticker.
     - `GuildStore`: Cache dữ liệu server (Roles hierarchy, Channels, Member list subscription range, Voice states).
     - `ChannelStore`: Cache tin nhắn (phân trang lịch sử, giới hạn tải trong RAM), reactions (kết hợp REST và Gateway), virtualized member list (`MemberListAccumulator`).
     - `MessageDrainStore`: Hàng đợi gửi tin nhắn và tải file đính kèm đa luồng (upload lên Cloud Attachment URL trước khi tạo tin nhắn), hỗ trợ optimistic UI và cơ chế retry khi lỗi.
     - `ReadStateStore`: Quản lý trạng thái đọc tin nhắn và số lượng mention của từng kênh.
     - `TokenStore`: Quản lý danh sách tài khoản và lưu token an toàn vào Keychain (`KeychainAccess`).
     - `PresenceStore`: Quản lý và đồng bộ trạng thái Online/Idle/DND/Invisible và Custom Activity qua các session.
     - `QuickSwitcherProviderStore`: Tìm kiếm nhanh server, kênh, DM và bạn bè (`Cmd + K`).
     - `SettingsStore` & `UserGuildSettingsStore`: Quản lý cấu hình người dùng dạng JSON và Protobuf.
   - **Chat & Message Components (`Paicord/Common/Chat/`)**:
     - `ChatView`, `InputBar`, `InputVM`: Nhập liệu văn bản, tải file/ảnh/video, chụp ảnh camera, gửi typing indicator.
     - `MessageCell`, `MessageBody`: Hiển thị tin nhắn, attachments, embeds, reactions, stickers.
   - **Theming (`Paicord/Utilities/Theming/`)**:
     - Hệ thống theme linh hoạt (Auto, Light, Dark, Custom themes qua file JSON).
   - **Permissions (`Paicord/Utilities/PermsHelper.swift`)**:
     - Tính toán phân quyền chi tiết dựa trên base permissions và channel permission overwrites.

2. **PaicordLib (Thư viện tầng mạng & Discord Core)**
   - `UserGatewayManager`: WebSocket Gateway client hỗ trợ nén `zstd-stream`, giả lập `SuperProperties` Discord client, rate limiting, heartbeat và session resume.
   - `DefaultDiscordClient`: REST API client hỗ trợ toàn bộ các API endpoint người dùng, tự động kích hoạt callback giải CAPTCHA và xác thực MFA.
   - `RemoteAuthGatewayManager`: Quản lý đăng nhập bằng mã QR (Remote Auth).
   - `DiscordModels`: Toàn bộ cấu trúc dữ liệu Discord, Snowflake, BitFields, Permissions, và Protobuf schemas (`PreloadedUserSettings`, `FrecencyUserSettings`).

3. **Textual (Bộ xử lý Markdown Discord)**
   - Phân tích và render Markdown chuyên dụng cho Discord:
     - User Mentions (`<@id>`), Channel Mentions (`<#id>`), Role Mentions (`<@&id>`), `@everyone`, `@here`.
     - Custom Emojis (`<:name:id>`, `<a:name:id>`), Jumbo Emojis, Unicode Emojis.
     - Timestamps (`<t:timestamp:format>`), Spoilers (`||spoiler||`), Subtext (`-# text`).
     - Code block syntax highlighting tích hợp Prism.js.

---

## Quy chuẩn Lập trình
- **Ghi chú trong mã nguồn**: Tuyệt đối không để lại ghi chú (comment) bên trong khối mã nguồn. Tất cả mã nguồn phải hoàn toàn sạch ghi chú. Trừ khi được yêu cầu rõ ràng.
- **Không sử dụng emoji**: Tuyệt đối không được sử dụng emoji trong code, trừ khi được yêu cầu.
## Nguyên tắc và Ràng buộc Vận hành

- **Ngôn ngữ**: Phản hồi theo đúng ngôn ngữ của câu hỏi (Tiếng Anh hoặc Tiếng Việt).
- **Xử lý Thông tin Mơ hồ**: Nếu các yêu cầu hoặc thông số kỹ thuật chưa rõ ràng, hãy yêu cầu làm rõ trước khi bắt đầu thực thi.
- **Phong cách Thực thi**: Đưa ra nhiều góc nhìn hoặc giải pháp cho các vấn đề kỹ thuật phức tạp. Giữ kết quả trực tiếp, không chứa các thành phần giao tiếp thừa, dấu gạch ngang dài, biểu tượng cảm xúc hoặc lời chào kết thúc.