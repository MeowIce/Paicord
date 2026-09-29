//
//  StickersView.swift
//  Paicord
//
//  Created by Lakhan Lothiyi on 11/10/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import Lottie
import PaicordLib
import SwiftUIX

extension MessageCell {
  struct StickersView: View, Equatable {
    static func == (lhs: StickersView, rhs: StickersView) -> Bool {
      lhs.stickers == rhs.stickers
    }
    var stickers: [StickerItem]
    var body: some View {
      VStack {
        ForEach(stickers) { sticker in
          let url = {
            return URL(
              string: CDNEndpoint.sticker(
                stickerId: sticker.id,
                format: sticker.format_type
              ).url + "?size=320"
            )
          }()
          if case .lottie = sticker.format_type, let url {
            LottieView {
              await LottieAnimation.loadedFrom(url: url)
            }
            .playing(loopMode: .loop)
            .frame(maxWidth: 160, maxHeight: 160)
          } else {
            NukeImage(url: url)
              .resizable()
              .scaledToFit()
              .frame(maxWidth: 160, maxHeight: 160)
          }
        }
      }
    }
  }
}
