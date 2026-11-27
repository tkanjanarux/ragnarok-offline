import RagnarokSprite
import SwiftUI

/// Free local try-on. This view never equips an item or sends a purchase packet.
struct CashShopCostumePreview: View {
    let itemID: UInt32
    let costume: CashShopCostume
    @Environment(PlaySession.self) private var session
    @Environment(GameContext.self) private var context
    @State private var direction = 0
    @State private var frame: CGImage?
    @State private var unavailable = false

    private var directions: [SpriteDirection] { [.south, .west, .north, .east] }
    private var configuration: ComposedSprite.Configuration {
        var result = ComposedSprite.Configuration(character: session.character)
        // Isolate the selected cosmetic so a missing part cannot be mistaken for
        // an existing equipped hat/cape. Body, hair and dyes remain the player's.
        result.headgears = costume.garment ? [] : [costume.view]
        result.garment = costume.garment ? costume.view : 0
        result.weapon = 0
        result.shield = 0
        return result
    }

    private struct Request: Hashable {
        let itemID: UInt32
        let direction: Int
        let configuration: ComposedSprite.Configuration
    }

    var body: some View {
        let request = Request(itemID: itemID, direction: direction, configuration: configuration)
        VStack(spacing: 4) {
            ZStack {
                GameStripeView()
                if let frame {
                    Image(decorative: frame, scale: 2).resizable().interpolation(.none).scaledToFit()
                        .padding(4)
                } else {
                    Text(unavailable ? "Preview unavailable for this character." : "Loading preview…")
                        .multilineTextAlignment(.center).padding(4)
                }
            }.frame(width: 130, height: 170).clipped()
            HStack(spacing: 12) {
                Button("‹") { direction = (direction + 3) % 4 }
                    .accessibilityLabel("Rotate preview left")
                Button("›") { direction = (direction + 1) % 4 }
                    .accessibilityLabel("Rotate preview right")
            }.buttonStyle(.game)
            Text("Free try-on").font(.game())
        }
        .task(id: request) {
            frame = nil
            unavailable = false
            do {
                let sprite = try await ComposedSprite(configuration: request.configuration, resourceManager: context.resourceManager)
                // Composer deliberately tolerates missing optional parts in game.
                // A shop preview must instead fail closed if the advertised part
                // is missing, including either sex/job's missing sprite/ACT.
                let expected: ComposedSprite.Part.Semantic = costume.garment ? .garment : .headgear
                guard sprite.parts.contains(where: { $0.semantic == expected }) else {
                    if !Task.isCancelled { unavailable = true }
                    return
                }
                let animation = await SpriteAnimationRenderer().render(composedSprite: sprite, actionType: .idle,
                    direction: directions[request.direction], rendersShadow: false)
                guard !Task.isCancelled else { return }
                frame = animation.firstFrame
                unavailable = frame == nil
            } catch {
                if !Task.isCancelled { unavailable = true }
            }
        }
    }
}
