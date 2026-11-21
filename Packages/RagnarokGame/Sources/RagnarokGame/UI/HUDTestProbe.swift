import SwiftUI
extension EnvironmentValues {
    @Entry var hudTestPrefix = ""
}
@MainActor enum HUDTestProbe {
    static var frames: [String:CGRect] = [:]
}
struct PanelMeasurement: ViewModifier {
    let key: String
    @Environment(\.hudTestPrefix) private var prefix
    func body(content: Content) -> some View {
        content.onGeometryChange(for: CGRect.self) { $0.frame(in:.global) } action: { HUDTestProbe.frames[prefix+key] = $0 }
    }
}
