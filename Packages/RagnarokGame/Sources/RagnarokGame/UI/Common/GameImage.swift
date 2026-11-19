//
//  GameImage.swift
//  RagnarokGame
//
//  Created by Leon Li on 2024/9/9.
//

import RagnarokResources
import SwiftUI

struct GameImage<Content>: View where Content: View {
    var name: String
    var content: (Resources.Image) -> Content

    @Environment(GameContext.self) private var gameContext

    @State private var image: Resources.Image?

    var body: some View {
        ZStack {
            contentView
        }
            .task(id: name) {
                let components = name.split(separator: "/").map(String.init)
                let path = ResourcePath.userInterfaceDirectory.appending(components)
                image = nil
                let loaded = try? await gameContext.resourceManager.image(at: path, removesMagentaPixels: true)
                guard !Task.isCancelled else { return }
                image = loaded
            }
    }

    @ViewBuilder private var contentView: some View {
        if let image {
            content(image)
        } else {
            Color.clear
        }
    }

    init(_ name: String) where Content == Image {
        self.name = name
        self.content = { image in
            Image(decorative: image.cgImage, scale: 1)
        }
    }

    init(_ name: String, @ViewBuilder content: @escaping (Image) -> Content) {
        self.name = name
        self.content = { image in
            content(Image(decorative: image.cgImage, scale: 1))
        }
    }
}

#Preview {
    GameImage("bgi_temp.bmp") { image in
        image
            .resizable()
            .aspectRatio(contentMode: .fill)
    }
    .frame(width: 280, height: 120)
    .clipped()
    .padding()
    .environment(GameContext.testing)
}
