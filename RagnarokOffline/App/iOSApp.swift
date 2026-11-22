#if os(iOS)
import RagnarokGame
import SwiftUI
@main
struct CaptureApp: App {
    var body: some Scene {
        WindowGroup {
            CompanionCapture()
                .persistentSystemOverlays(.hidden)
                .statusBarHidden()
                .task {
                    try? await Task.sleep(for: .seconds(1))
                    let args = ProcessInfo.processInfo.arguments
                    if ProcessInfo.processInfo.arguments.contains("landscape"),
                       let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
                        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
                    }
                    try? await Task.sleep(for: .seconds(5))
                    guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),
                          let window = scene.windows.first(where: { $0.isKeyWindow }) else { return }
                    let base = URL.documentsDirectory.appending(path: (args.contains("gear") ? "gear" : "roster") + "-" + (args.contains("landscape") ? "landscape" : "portrait"))
                    let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                        window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                    }
                    try? image.pngData()?.write(to: base.appendingPathExtension("png"))
                    let geometry = "\(scene.interfaceOrientation.rawValue) \(window.bounds) \(window.screen.scale)"
                    try? geometry.write(to: base.appendingPathExtension("txt"), atomically: true, encoding: .utf8)
                }
        }
    }
}
#endif
