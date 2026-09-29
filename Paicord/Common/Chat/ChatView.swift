import Collections
import PaicordLib
@_spi(Advanced) import SwiftUIIntrospect
import SwiftUIX

@Observable
final class ChatScrollState {
  var position: MessageSnowflake?
}

struct ChatView: View {
  @State var vm: ChannelStore
  @Environment(\.gateway) var gw
  @Environment(\.appState) var appState
  @Environment(\.accessibilityReduceMotion) var accessibilityReduceMotion
  @Environment(\.userInterfaceIdiom) var idiom
  @Environment(\.theme) var theme

  @State private var scrollState = ChatScrollState()

  var drain: MessageDrainStore { gw.messageDrain }

  @AppStorage("Paicord.Appearance.ChatMessagesAnimated")
  var chatAnimatesMessages: Bool = false

  init(vm: ChannelStore) { self._vm = .init(initialValue: vm) }

  #if os(macOS)
    @FocusState private var isChatFocused: Bool
  #endif

  private struct MessagePair: Identifiable {
    let message: DiscordChannel.Message
    let prior: DiscordChannel.Message?
    var id: MessageSnowflake { message.id }
  }

  private struct PendingMessagePair: Identifiable {
    let message: Payloads.CreateMessage
    let priorExisting: DiscordChannel.Message?
    let priorEnqueued: Payloads.CreateMessage?
    var id: String { message.nonce?.asString ?? UUID().uuidString }
  }

  private func makePairedMessages(_ messages: OrderedDictionary<MessageSnowflake, DiscordChannel.Message>.Values) -> [MessagePair] {
    var pairs = [MessagePair]()
    pairs.reserveCapacity(messages.count)
    var prior: DiscordChannel.Message? = nil
    for msg in messages {
      pairs.append(MessagePair(message: msg, prior: prior))
      prior = msg
    }
    return pairs
  }

  private func makePairedPending(_ pending: OrderedDictionary<MessageSnowflake, Payloads.CreateMessage>.Values, lastOrdered: DiscordChannel.Message?) -> [PendingMessagePair] {
    var pairs = [PendingMessagePair]()
    pairs.reserveCapacity(pending.count)
    var priorEnqueued: Payloads.CreateMessage? = nil
    for (index, msg) in pending.enumerated() {
      if index == 0 {
        pairs.append(PendingMessagePair(message: msg, priorExisting: lastOrdered, priorEnqueued: nil))
      } else {
        pairs.append(PendingMessagePair(message: msg, priorExisting: nil, priorEnqueued: priorEnqueued))
      }
      priorEnqueued = msg
    }
    return pairs
  }

  var body: some View {
    let orderedMessages = vm.messages.values
    let pendingMessages = drain.pendingMessages[vm.channelId, default: [:]]
    let pairedMessages = makePairedMessages(orderedMessages)
    let pairedPending = makePairedPending(pendingMessages.values, lastOrdered: orderedMessages.last)

    let shouldAnimate =
      orderedMessages.last?.author?.id != gw.user.currentUser?.id
    VStack(spacing: 20) {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          if !vm.messages.isEmpty {
            if vm.hasMoreHistory && vm.hasPermission(.readMessageHistory) {
            } else {
              if vm.hasPermission(.readMessageHistory) {
                ChatHeaders.WelcomeStartOfChannelHeader()
              } else {
                ChatHeaders.NoHistoryPermissionHeader()
              }
            }
          }

          ForEach(pairedMessages) { pair in
            if messageAllowed(pair.message) {
              MessageCell(
                for: pair.message,
                prior: pair.prior,
                channel: vm
              )
            }
          }

          ForEach(pairedPending) { pair in
            if let priorEnqueued = pair.priorEnqueued {
              SendMessageCell(for: pair.message, prior: priorEnqueued)
            } else if let priorExisting = pair.priorExisting {
              SendMessageCell(for: pair.message, prior: priorExisting)
            } else {
              SendMessageCell(for: pair.message, prior: Optional<DiscordChannel.Message>.none)
            }
          }
        }
        .scrollTargetLayout()
      }
      .safeAreaPadding(.top, 1)
      #if os(macOS)
        .focusable()
        .focusEffectDisabled()
        .onTapGesture { isChatFocused = true }
        .focused($isChatFocused)
        .onKeyPress(.escape, phases: .down) { _ in
          NotificationCenter.default.post(
            name: .chatViewShouldScrollToBottom,
            object: ["channelId": vm.channelId, "immediate": true]
          )
          InputBar.inputVMs[vm.channelId]?.uploadItems = []
          return .handled
        }
      #endif
      .scrollPosition(id: Binding(get: { scrollState.position }, set: { scrollState.position = $0 }), anchor: .bottom)
      .bottomAnchored()
      .scrollClipDisabled()
      .maxHeight(.infinity)
      .overlay(alignment: .bottomTrailing) {
        ChatScrollToBottomButton(
          scrollState: scrollState,
          channelId: vm.channelId,
          lastMessages: Array(orderedMessages.suffix(10).map(\.id))
        )
      }

      if vm.hasPermission(.sendMessages) {
        InputBar(vm: vm)
          .id(vm.channelId)
      } else {
        Spacer().frame(height: 10)
      }
    }
    .animation(
      shouldAnimate && chatAnimatesMessages ? .default : nil,
      value: orderedMessages
    )
    .animation(chatAnimatesMessages ? .default : nil, value: pendingMessages)
    .scrollDismissesKeyboard(.interactively)
    .background(theme.common.secondaryBackground)
    .ignoresSafeArea(.keyboard, edges: .all)
    .toolbar {
      ToolbarItem(placement: .navigation) {
        ChannelHeader(vm: vm)
      }
    }
    .onReceive(
      NotificationCenter.default.publisher(
        for: .chatViewShouldScrollToBottom
      )
    ) { object in
      guard let info = object.object as? [String: Any],
        let channelId = info["channelId"] as? ChannelSnowflake,
        channelId == vm.channelId
      else { return }
      let isNearBottom =
        (orderedMessages.suffix(10).map(\.id)
        + pendingMessages.values.compactMap(\.nonce).map({
          MessageSnowflake($0.asString)
        }))
        .contains {
          $0 == self.scrollState.position
        }
      let immediate = (info["immediate"] as? Bool == true)
      guard isNearBottom || immediate else {
        return
      }
      let pending: MessageSnowflake? = info["id"] as? MessageSnowflake
      let resolvedId = pending ?? orderedMessages.last?.id
      withAnimation(immediate ? .default : nil) {
        self.scrollState.position = resolvedId ?? self.scrollState.position
      }
      if let resolvedId {
        acknowledge(messageId: resolvedId)
      }
    }
    .onReceive(
      NotificationCenter.default.publisher(for: .chatViewShouldScrollToID)
    ) { object in
      guard let info = object.object as? [String: Any],
        let channelId = info["channelId"] as? ChannelSnowflake,
        channelId == vm.channelId,
        let messageId = info["messageId"] as? MessageSnowflake
      else { return }
      self.scrollState.position = messageId
    }
  }

  func messageAllowed(_ msg: DiscordChannel.Message) -> Bool {
    guard let authorId = msg.author?.id else { return true }

    if let relationship = gw.user.relationships[authorId] {
      if relationship.type == .blocked || relationship.user_ignored {
        return false
      }
    }

    return true
  }

  @State var ackTask: Task<Void, Error>? = nil
  private func acknowledge(messageId: MessageSnowflake) {
    guard gw.readStates.isUnread(channelId: vm.channelId, lastMessageId: messageId) else {
      return
    }
    let channelId = vm.channelId
    ackTask?.cancel()
    ackTask = Task {
      try? await Task.sleep(for: .seconds(1.5))
      guard !Task.isCancelled else { return }
      _ = try await gw.client.acknowledgeMessage(
        channelId: channelId,
        messageId: messageId,
        payload: Payloads.AcknowledgeMessage()
      )
      gw.readStates.applyAck(channelId: channelId, messageId: messageId)
    }
  }
}

private struct ChatScrollToBottomButton: View {
  let scrollState: ChatScrollState
  let channelId: ChannelSnowflake
  let lastMessages: [MessageSnowflake]

  var body: some View {
    if let current = scrollState.position,
      !lastMessages.contains(current)
    {
      Button(action: {
        NotificationCenter.default.post(
          name: .chatViewShouldScrollToBottom,
          object: ["channelId": channelId, "immediate": true]
        )
      }) {
        #if os(macOS)
          Image(systemName: "arrow.down")
            .imageScale(.large)
            .padding(8)
        #else
          Image(systemName: "arrow.down")
            .tint(.primary)
            .imageScale(.large)
            .padding(8)
            .background(.ultraThinMaterial, in: .circle)
        #endif
      }
      #if os(macOS)
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.circle)
        .controlSize(.large)
      #else
        .buttonStyle(.borderless)
      #endif
      .padding()
      .transition(.blurReplace.animation(.default))
    }
  }
}

extension View {
  fileprivate func bottomAnchored() -> some View {
    if #available(iOS 18.0, macOS 15.0, *) {
      return
        self
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .defaultScrollAnchor(.bottom, for: .alignment)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
    } else {
      return
        self
        .defaultScrollAnchor(.bottom)
    }
  }
}

extension Notification.Name {
  static let chatViewShouldScrollToBottom = Notification.Name(
    "chatViewShouldScrollToBottom"
  )

  static let chatViewShouldScrollToID = Notification.Name(
    "chatViewShouldScrollToID"
  )
}
