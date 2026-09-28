import SwiftUI

@available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
struct InlineBackgroundAttribute: TextAttribute {
  var color: Color
}

@available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
extension Text.Layout.Run {
  fileprivate var inlineBackgroundColor: Color? {
    self[InlineBackgroundAttribute.self]?.color
  }
}

@available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
extension Text.Layout {
  var hasInlineBackgrounds: Bool {
    for line in self {
      for run in line {
        if run.inlineBackgroundColor != nil {
          return true
        }
      }
    }
    return false
  }
}

struct RoundedInlineBackground: ViewModifier {
  @Environment(\.roundedBackgroundStyle) private var style

  func body(content: Content) -> some View {
    if #available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *), let style {
      content
        .backgroundPreferenceValue(Text.LayoutKey.self) { value in
          if let anchoredLayout = value.first, anchoredLayout.layout.hasInlineBackgrounds {
            GeometryReader { geometry in
              RoundedInlineBackgroundView(
                style: style,
                origin: geometry[anchoredLayout.origin],
                layout: anchoredLayout.layout
              )
            }
          }
        }
    } else {
      content
    }
  }
}

@available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
private struct RoundedInlineBackgroundView: View {
  let style: RoundedBackgroundStyle
  let origin: CGPoint
  let layout: Text.Layout

  var body: some View {
    ZStack(alignment: .topLeading) {
      ForEach(Array(backgroundRuns.enumerated()), id: \.offset) { _, run in
        Rectangle()
          .fill(.clear)
          .frame(width: run.rect.width, height: run.rect.height)
          .padding(style.padding)
          .background(RoundedRectangle(cornerRadius: style.cornerRadius).fill(run.color))
          .position(x: run.rect.midX, y: run.rect.midY)
      }
    }
    .offset(x: origin.x, y: origin.y)
  }

  private var backgroundRuns: [(rect: CGRect, color: Color)] {
    var result: [(rect: CGRect, color: Color)] = []

    for line in layout {
      var pending: (rect: CGRect, color: Color)?
      for run in line {
        guard let color = run.inlineBackgroundColor else {
          if let value = pending {
            result.append(value)
            pending = nil
          }
          continue
        }

        let bounds = run.typographicBounds.rect
        if let value = pending, value.color == color {
          pending = (value.rect.union(bounds), color)
        } else {
          if let value = pending {
            result.append(value)
          }
          pending = (bounds, color)
        }
      }
      if let value = pending {
        result.append(value)
      }
    }

    return result
  }
}
