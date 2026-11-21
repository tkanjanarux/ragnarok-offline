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
        let host = UIHostingController(rootView: MapHUDViewport { size in
            GeometryReader { proxy in
                Color.clear.onGeometryChange(for: CGRect.self) { geo in geo.frame(in: .global) } action: { hud = $0 }
            }.frame(width: size.width, height: size.height)
        })
        parent.addChild(host)
        parent.view.addSubview(host.view)
        host.didMove(toParent: parent)
        for (width, height, left, right) in [(466,678,0,84), (678,466,84,0), (678,466,0,84), (466,678,0,0)] {
            host.view.frame = CGRect(x: 0, y: 0, width: width, height: height)
            host.additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: CGFloat(left), bottom: 0, right: CGFloat(right))
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(300))
            XCTAssertGreaterThanOrEqual(host.view.safeAreaInsets.left, CGFloat(left))
            XCTAssertGreaterThanOrEqual(host.view.safeAreaInsets.right, CGFloat(right))
            XCTAssertEqual(hud.minX, 0, accuracy: 0.5)
            XCTAssertEqual(hud.width, CGFloat(width), accuracy: 0.5)
        }
    }
}
