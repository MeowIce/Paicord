import SwiftUI

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension Text.Layout {
  var hasLinks: Bool {
    for line in self {
      for run in line {
        if run.url != nil {
          return true
        }
      }
    }
    return false
  }
}

struct TextLinkInteraction: ViewModifier {
  @Environment(\.openURL) private var openURL
  @Environment(\.textualEntityTapAction) private var entityTapAction

  func body(content: Content) -> some View {
    #if TEXTUAL_ENABLE_LINKS
      if #available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *) {
        content
          .overlayPreferenceValue(Text.LayoutKey.self) { value in
            if let anchoredLayout = value.first, anchoredLayout.layout.hasLinks {
              GeometryReader { geometry in
                Color.clear
                  .contentShape(.rect)
                  .gesture(
                    tap(
                      origin: geometry[anchoredLayout.origin],
                      layout: anchoredLayout.layout
                    )
                  )
              }
            }
          }
      } else {
        content
      }
    #else
      content
    #endif
  }

  #if TEXTUAL_ENABLE_LINKS
    @available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
    private func tap(origin: CGPoint, layout: Text.Layout) -> some Gesture {
      SpatialTapGesture()
        .onEnded { value in
          let localPoint = CGPoint(
            x: value.location.x - origin.x,
            y: value.location.y - origin.y
          )
          let runs = layout.flatMap(\.self)
          let run = runs.first { run in
            run.typographicBounds.rect.contains(localPoint)
          }
          guard let run, let url = run.url else {
            return
          }
          openURL(url)
          entityTapAction?(
            url,
            run.typographicBounds.rect.offsetBy(dx: origin.x, dy: origin.y)
          )
        }
    }
  #endif
}

private struct EntityTapActionKey: EnvironmentKey {
  static let defaultValue: (@MainActor (URL, CGRect) -> Void)? = nil
}

extension EnvironmentValues {
  var textualEntityTapAction: (@MainActor (URL, CGRect) -> Void)? {
    get { self[EntityTapActionKey.self] }
    set { self[EntityTapActionKey.self] = newValue }
  }
}
