#if os(iOS)
import RagnarokGame
import SwiftUI
@main
struct CaptureApp: App {
    var body: some Scene {
        WindowGroup {
            CompanionCapture()
                .task {
                    try? await Task.sleep(for: .seconds(1))
                    if ProcessInfo.processInfo.arguments.contains("landscape"),
                       let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
                        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
                    }
                }
        }
    }
}
#endif
