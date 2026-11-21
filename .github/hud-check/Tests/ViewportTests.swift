import SwiftUI
import UIKit
import XCTest
@testable import ViewportCheck

@MainActor final class ViewportTests: XCTestCase {
    func testFullWidthWhenInsetsChangeSides() async throws {
        let parent = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 900, height: 900))
        window.rootViewController = parent
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        var hud: CGRect = .zero
        var original: CGRect = .zero
        var button = CGRect.zero
        let host = UIHostingController(rootView: ZStack {
            GeometryReader { outside in
                Color.clear.frame(width: outside.size.width, height: outside.size.height)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { original = $0 }
            }
            MapHUDViewport { size, inset in
                ZStack(alignment: .bottomTrailing) {
                    Color.clear
                    Color.blue.frame(width: 44, height: 28)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { button = $0 }
                        .padding(.bottom, bottomHUDControlPadding(for: inset))
                }
                .frame(width: size.width, height: size.height)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { hud = $0 }
            }
        })
        parent.addChild(host)
        parent.view.addSubview(host.view)
        host.didMove(toParent: parent)
        for (width, height, left, right, bottom) in [(951,669,0,0,34), (466,678,0,84,34), (678,466,84,0,21), (678,466,0,84,0), (466,678,0,0,8)] {
            host.view.frame = CGRect(x: 0, y: 0, width: width, height: height)
            host.additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: CGFloat(left), bottom: CGFloat(bottom), right: CGFloat(right))
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(300))
            XCTAssertGreaterThanOrEqual(host.view.safeAreaInsets.left, CGFloat(left))
            XCTAssertGreaterThanOrEqual(host.view.safeAreaInsets.right, CGFloat(right))
            print("window", width, "insets", host.view.safeAreaInsets, "previous", original, "fixed", hud)
            XCTAssertEqual(original.width, CGFloat(width) - host.view.safeAreaInsets.left - host.view.safeAreaInsets.right, accuracy: 0.5)
            XCTAssertEqual(original.minX, host.view.safeAreaInsets.left, accuracy: 0.5)
            XCTAssertEqual(hud.maxY, CGFloat(height), accuracy: 0.5)
            XCTAssertEqual(button.maxY, hud.maxY - bottomHUDControlPadding(for: host.view.safeAreaInsets.bottom), accuracy: 0.5)
            XCTAssertLessThanOrEqual(button.midY, original.maxY - 5.5)
            print("height", height, "edge", hud.maxY, "safe bottom", original.maxY, "button center", button.midY)
            XCTAssertEqual(hud.minX, 0, accuracy: 0.5)
            XCTAssertEqual(hud.width, CGFloat(width), accuracy: 0.5)
        }
    }
}
