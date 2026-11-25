import CoreGraphics
import RagnarokResources
import RagnarokScript
import SwiftUI

struct NavigationView: View {
    var scene: MapScene
    var onClose: () -> Void
    @Environment(PlaySession.self) private var session
    @State private var mapImage: CGImage?

    var body: some View {
        GeometryReader { available in
            OriginalROPanel(title: "Navigation", width: min(320, available.size.width - 24),
                             height: min(450, available.size.height - 32), onClose: onClose) {
                NavigationContent(state: session.navigation, mapName: scene.mapName,
                    width: scene.mapGrid.width, height: scene.mapGrid.height,
                    player: scene.state.playerPosition, mapImage: mapImage)
            }
        }
        .task(id: scene.mapName) {
            mapImage = nil
            let loaded = try? await scene.resourceManager.mapImage(forMapName: NavigationData.mapKey(scene.mapName)).cgImage
            guard !Task.isCancelled else { return }
            mapImage = loaded
        }
    }
}

/// Shared by the game panel and Simulator visual fixtures; no test-only UI paths.
struct NavigationContent: View {
    var state: NavigationState
    var mapName: String
    var width: Int
    var height: Int
    var player: SIMD2<Int>
    var mapImage: CGImage?
    @State private var query = ""
    @State private var kind: NavigationDestination.Kind?
    @State private var tab: Int
    @State private var x = ""
    @State private var y = ""
    @State private var coordinateError: String?

    init(state: NavigationState, mapName: String, width: Int, height: Int,
         player: SIMD2<Int>, mapImage: CGImage?) {
        self.state = state; self.mapName = mapName; self.width = width; self.height = height
        self.player = player; self.mapImage = mapImage
        _tab = State(initialValue: state.target == nil ? 0 : 1)
    }

    private var results: [NavigationDestination] {
        state.data.search(query, kind: kind, currentMap: mapName)
    }
    var body: some View {
        VStack(spacing: 6) {
            ROTabs(choices: [(0, "Destinations"), (1, "Route")], selection: $tab)
            if tab == 0 {
                HStack(spacing: 4) {
                    Menu {
                        Button("All") { kind = nil }
                        ForEach([NavigationDestination.Kind.map, .npc, .monster], id: \.self) { choice in
                            Button(choice.rawValue) { kind = choice }
                        }
                    } label: { Text(kind?.rawValue ?? "All"); Image(systemName: "chevron.down") }
                        .frame(width: 64)
                    TextField("Search NPC, monster or map", text: $query)
                        .textFieldStyle(ROTextFieldStyle()).autocorrectionDisabled()
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        NavigationMapPreview(width: width, height: height, player: player, mapImage: mapImage,
                            path: state.map == NavigationData.mapKey(mapName) ? state.path : [], size: 160)
                            .frame(maxWidth: .infinity).background(Color.black)
                        Text("\(NavigationData.mapKey(mapName)) · X: \(player.x)  Y: \(player.y)").monospacedDigit()
                        Text("Search results: \(results.count)").foregroundStyle(Color.blue)
                        if state.loadingData { ProgressView("Loading destinations…") }
                        if state.loadedData && state.data.destinations.isEmpty {
                            Text("No destination list is available in your client files. You can choose coordinates on this map below.")
                                .foregroundStyle(.secondary)
                        } else if results.isEmpty && !state.loadingData {
                            Text("No matching destination. Try another name or map.").foregroundStyle(.secondary)
                        }
                        ForEach(Array(results.prefix(100))) { destination in
                            Button {
                                state.begin(destination); tab = 1
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(destination.name).fontWeight(.semibold)
                                    Text(detail(destination)).font(.game(size: 11)).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain).disabled(state.loadingData)
                            Divider()
                        }
                        if results.count > 100 { Text("Showing the first 100 results. Refine your search.").foregroundStyle(.secondary) }
                        Text("Coordinates on \(NavigationData.mapKey(mapName))").fontWeight(.semibold)
                        HStack {
                            TextField("X", text: $x).textFieldStyle(ROTextFieldStyle())
                            TextField("Y", text: $y).textFieldStyle(ROTextFieldStyle())
                            Button("Guide") { guideToCoordinates() }.buttonStyle(ROCompactButtonStyle()).frame(minWidth: 60, minHeight: 32)
                        }
                        if let coordinateError { Text(coordinateError).foregroundStyle(.red) }
                    }.padding(.vertical, 4)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if let target = state.target {
                            Text(target.name).fontWeight(.bold)
                            Text(detail(target)).foregroundStyle(.secondary)
                        }
                        Text(state.message).accessibilityIdentifier("navigationStatus")
                        NavigationMapPreview(width: width, height: height, player: player, mapImage: mapImage,
                            path: state.map == NavigationData.mapKey(mapName) ? state.path : [], size: 180)
                            .frame(maxWidth: .infinity)
                        Text("\(NavigationData.mapKey(mapName)) · X: \(player.x)  Y: \(player.y)")
                            .monospacedDigit().frame(maxWidth: .infinity)
                        if mapImage == nil { Text("Map image unavailable; route coordinates are still shown.").foregroundStyle(.secondary) }
                        ForEach(Array(state.legs.enumerated()), id: \.offset) { _, leg in
                            if let portal = leg.portal {
                                Text("\(leg.map) (\(portal.position.x), \(portal.position.y)) → \(portal.destinationMap)")
                            } else { Text(leg.map) }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if state.target != nil {
                HStack(spacing: 12) {
                    Button("Recalculate") { if let target = state.target { state.begin(target) } }
                    Button("Cancel route") { state.cancel() }
                }.buttonStyle(ROCompactButtonStyle()).frame(height: 30)
            }
        }.font(.game(size: 12)).padding(6)
            .scrollDismissesKeyboard(.interactively)
            .onAppear { x = String(player.x); y = String(player.y) }
    }

    private func detail(_ target: NavigationDestination) -> String {
        if let p = target.position { return "\(target.kind.rawValue) · \(target.map) · \(p.x), \(p.y)" }
        return "\(target.kind == .monster ? "Spawn map" : "Map") · \(target.map)"
    }
    private func guideToCoordinates() {
        guard let x = Int(x), let y = Int(y), x >= 0, y >= 0, x < width, y < height else {
            coordinateError = "Enter coordinates inside this map (X: 0–\(width - 1), Y: 0–\(height - 1))."; return
        }
        coordinateError = nil
        state.begin(.init(id: "point:\(mapName):\(x):\(y)", kind: .point, name: "\(x), \(y)", map: mapName, position: SIMD2(x, y)))
        tab = 1
    }
}

struct NavigationRouteOverlay: View {
    var path: [SIMD2<Int>]
    var projection: MinimapProjection
    var body: some View {
        Canvas { context, _ in
            let points = path.filter(projection.contains).map(projection.point)
            guard let first = points.first else { return }
            var line = Path(); line.move(to: first)
            for point in points.dropFirst() { line.addLine(to: point) }
            context.stroke(line, with: .color(.black.opacity(0.8)), lineWidth: 4)
            context.stroke(line, with: .color(.yellow), lineWidth: 2)
            if let last = points.last {
                let rect = CGRect(x: last.x - 4, y: last.y - 4, width: 8, height: 8)
                context.fill(Path(ellipseIn: rect), with: .color(.orange))
                context.stroke(Path(ellipseIn: rect), with: .color(.black), lineWidth: 1)
            }
        }.allowsHitTesting(false)
    }
}

struct NavigationMapPreview: View {
    var width: Int
    var height: Int
    var player: SIMD2<Int>
    var mapImage: CGImage?
    var path: [SIMD2<Int>]
    var size: Double
    var body: some View {
        let projection = MinimapProjection(width: width, height: height, size: size, player: player)
        ZStack {
            Color(white: 0.18)
            if let mapImage { Image(decorative: mapImage, scale: 1).resizable().interpolation(.none) }
            NavigationRouteOverlay(path: path, projection: projection)
            Circle().fill(.white).overlay { Circle().stroke(.black, lineWidth: 1) }
                .frame(width: 8, height: 8).position(projection.point(player))
        }.frame(width: size, height: size).clipped()
    }
}
