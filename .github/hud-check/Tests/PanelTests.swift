import SwiftUI
import UIKit
import XCTest
@testable import ViewportCheck

@MainActor final class PanelTests: XCTestCase {
    func testPanelTranslation() async throws {
        let parent = UIViewController()
        let window = UIWindow(frame: CGRect(x:0,y:0,width:1000,height:900))
        window.rootViewController = parent
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        var boxes: [String:CGRect] = [:]
        func mark<V: View>(_ v: V, _ key: String) -> some View {
            v.onGeometryChange(for: CGRect.self) { $0.frame(in:.global) } action: { boxes[key] = $0 }
        }
        func panels(_ size: CGSize, _ gap: CGFloat, _ legacy: Bool) -> some View {
            let prefix = legacy ? "old" : "new"
            let wide = size.width >= 640
            let chat = VStack(spacing:0) {
                Color.black.frame(height:71)
                mark(Color.gray.frame(height:28),prefix+"input")
            }.frame(width:wide ? 360 : size.width-32)
            let bar = VStack(alignment:.trailing,spacing:6) {
                mark(Color.blue.frame(width:94,height:44),prefix+"actions")
                Color.green.frame(width:144,height:44)
                mark(Color.gray.frame(height:44),prefix+"slots").padding(4)
            }.frame(width:min(400,size.width-32))
            return Color.clear.frame(width:size.width,height:size.height)
                .overlay(alignment:wide ? .bottomLeading : .bottom) { mark(chat,prefix+"chat").padding(.bottom,gap) }
                .overlay(alignment:.bottomTrailing) {
                    mark(bar,prefix+"bar").padding(.trailing,16)
                        .padding(.bottom,gap + (wide ? (legacy ? 16 : 0) : 107))
                }
        }
        let host = UIHostingController(rootView: ZStack {
            GeometryReader { safe in panels(safe.size,0,true) }.ignoresSafeArea(.container,edges:.horizontal)
            MapHUDViewport { size,inset in panels(size,bottomHUDMargin(for:inset),false) }
        })
        parent.addChild(host); parent.view.addSubview(host.view); host.didMove(toParent:parent)
        for (width,height,bottom) in [(951,669,34),(466,678,34),(678,466,21),(678,466,0)] {
            host.view.frame = CGRect(x:0,y:0,width:width,height:height)
            host.additionalSafeAreaInsets = UIEdgeInsets(top:0,left:0,bottom:CGFloat(bottom),right:0)
            host.view.setNeedsLayout(); host.view.layoutIfNeeded()
            try await Task.sleep(for:.milliseconds(300))
            let inset = host.view.safeAreaInsets.bottom
            let gap = min(12,inset)
            for key in ["chat","input","bar","actions","slots"] {
                let old = try XCTUnwrap(boxes["old"+key])
                let new = try XCTUnwrap(boxes["new"+key])
                let delta = inset-gap + (width>=640 && ["bar","actions","slots"].contains(key) ? 16 : 0)
                XCTAssertEqual(new.height,old.height,accuracy:0.5)
                XCTAssertEqual(new.width,old.width,accuracy:0.5)
                XCTAssertEqual(new.minY-old.minY,delta,accuracy:0.5)
                XCTAssertEqual(new.maxY-old.maxY,delta,accuracy:0.5)
            }
            XCTAssertEqual(try XCTUnwrap(boxes["newchat"]).maxY,CGFloat(height)-gap,accuracy:0.5)
            print("PASS panels",width,height,"inset",inset,"margin",gap,"chat translation",inset-gap)
        }
    }
}
