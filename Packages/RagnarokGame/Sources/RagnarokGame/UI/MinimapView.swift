//
//  MinimapView.swift
//  RagnarokGame
//
//  Created by Leon Li on 2026/8/21.
//

import CoreGraphics
import RagnarokSprite
import SwiftUI

private let mapSize: CGFloat = 96
private let zoomFactors = [1, 10, 6, 3, 2]

struct MinimapView: View {
    var scene: MapScene
    var onNavigation: () -> Void = {}

    @Environment(GameContext.self) private var gameContext
    @Environment(PlaySession.self) private var session

    @State private var zoomLevel = 0
    @State private var mapImage: CGImage?

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            MinimapMapView(
                scene: scene,
                mapImage: mapImage,
                zoomFactor: zoomFactors[zoomLevel],
                showsFullMap: zoomLevel == 0
            )

            Text("X: \(scene.state.playerPosition.x)  Y: \(scene.state.playerPosition.y)")
                .font(.game(size: 10, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity)
                .background(.black.opacity(0.65))
                .accessibilityLabel("Position X \(scene.state.playerPosition.x), Y \(scene.state.playerPosition.y)")

            HStack(spacing: 0) {
                // map/map_plus0.bmp
                Button(action: zoomIn) {
                    Image(systemName: "plus")
                        .font(.game(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black, radius: 1, y: 1)
                        .frame(width: 24, height: 24)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(zoomLevel == zoomFactors.count - 1)

                // map/map_minus0.bmp
                Button(action: zoomOut) {
                    Image(systemName: "minus")
                        .font(.game(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black, radius: 1, y: 1)
                        .frame(width: 24, height: 24)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(zoomLevel == 0)
            }
            .offset(x: 6)
            if session.navigation.target != nil {
                VStack(spacing: 0) {
                    HStack(spacing: 4) {
                        Button(action: onNavigation) {
                            GameImage("basic_interface/sys_mini_off.bmp")
                                .frame(width: 44, height: 32).contentShape(Rectangle())
                        }.accessibilityLabel("Show navigation route")
                        Button { session.navigation.cancel() } label: {
                            GameImage("basic_interface/sys_close_off.bmp")
                                .frame(width: 44, height: 32).contentShape(Rectangle())
                        }.accessibilityLabel("Cancel route")
                    }.buttonStyle(.plain)
                        .background { GameTitleBar(nil, usesGameSkin: true).allowsHitTesting(false) }
                    Text(session.navigation.target?.name ?? "")
                        .font(.game(size: 10)).foregroundStyle(Color.gameLabel)
                        .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading).padding(3)
                        .background { GameStripeView() }
                }.overlay { Rectangle().strokeBorder(Color.gameBoxBorder).allowsHitTesting(false) }

            }
        }
        .frame(width: mapSize)
        .task(id: scene.mapName) {
            mapImage = nil
            let mapName = scene.mapName.split(separator: ".", maxSplits: 1).first.map(String.init) ?? scene.mapName
            let loadedImage = try? await gameContext.resourceManager.mapImage(forMapName: mapName).cgImage
            guard !Task.isCancelled else { return }
            mapImage = loadedImage
        }
    }

    private func zoomIn() {
        withAnimation(.easeInOut(duration: 0.2)) {
            zoomLevel = min(zoomLevel + 1, zoomFactors.count - 1)
        }
    }

    private func zoomOut() {
        withAnimation(.easeInOut(duration: 0.2)) {
            zoomLevel = max(zoomLevel - 1, 0)
        }
    }
}

private struct MinimapMapView: View {
    var scene: MapScene
    var mapImage: CGImage?
    var zoomFactor: Int
    var showsFullMap: Bool

    @Environment(PlaySession.self) private var session

    private var projection: MinimapProjection {
        MinimapProjection(width: scene.mapGrid.width, height: scene.mapGrid.height,
            imageWidth: Double(mapImage?.width ?? 512), imageHeight: Double(mapImage?.height ?? 512),
            zoomFactor: showsFullMap || mapImage == nil ? 1 : zoomFactor,
            player: scene.state.playerPosition)
    }

    var body: some View {
        ZStack {
            if let mapImage {
                Image(decorative: mapImage, scale: 1)
                    .resizable()
                    .interpolation(.none)
                    .frame(
                        width: projection.displaySize.width,
                        height: projection.displaySize.height
                    )
                    .position(projection.center)
            }

            if session.navigation.map == PartyMember.mapKey(scene.mapName) {
                NavigationRouteOverlay(path: session.navigation.path, projection: projection)
            }

            ForEach(session.party.members) { member in
                if member.id != session.partyAccountID, member.isOnMap(scene.mapName),
                   let position = member.position, projection.contains(position) {
                    Circle()
                        .fill(member.dead ? Color.gray : Color.cyan)
                        .overlay { Circle().stroke(.black, lineWidth: 1) }
                        .frame(width: 7, height: 7)
                        .position(projection.point(position))
                        .accessibilityLabel(member.name)
                }
            }

            MinimapArrowView()
                .rotationEffect(arrowRotation(for: scene.state.playerDirection))
                .position(projection.point(scene.state.playerPosition))
        }
        .frame(width: mapSize, height: mapSize)
        .clipped()
        .allowsHitTesting(false)
    }

    private func arrowRotation(for direction: SpriteDirection) -> Angle {
        .degrees(Double((direction.rawValue + 4) * 45))
    }
}

private struct MinimapArrowView: View {
    var body: some View {
        // map/map_arrow.bmp
        MinimapArrowShape()
            .fill(.white)
            .frame(width: 12, height: 12)
            .clipped()
            .overlay {
                Color(red: 1, green: 0, blue: 0)
                    .frame(width: 2, height: 2)
            }
    }
}

private struct MinimapArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        let corners = [
            CGPoint(x: 6, y: -2.75),
            CGPoint(x: 12.5, y: 12),
            CGPoint(x: 6, y: 7.25),
            CGPoint(x: -0.5, y: 12),
        ]

        var path = Path()
        path.addLines(corners.map { corner in
            CGPoint(
                x: rect.minX + rect.width * corner.x / 12,
                y: rect.minY + rect.height * corner.y / 12
            )
        })
        path.closeSubpath()
        return path
    }
}
