#if os(iOS)
import SwiftUI
import UIKit
import XCTest
@testable import RagnarokGame

@MainActor final class HUDTranslationTests: XCTestCase {
    func testPanelTranslation() async throws {
        let parent = UIViewController()
        let window = UIWindow(frame: CGRect(x:0,y:0,width:1000,height:900))
        window.rootViewController = parent
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        func panels(_ size: CGSize, _ gap: CGFloat, _ legacy: Bool) -> some View {
            let prefix = legacy ? "old" : "new"
            let wide = size.width >= 640
            let chatWidth = wide ? (size.width >= 780 ? 360.0 : 280.0) : size.width - 32
            let chat = ChatBoxView().frame(width: chatWidth).modifier(PanelMeasurement(key:"chat"))
            let bar = ActionBarView(selectedTargetType:nil,onTargetAction:{},onSelectNextTarget:{},onDeselectTarget:{},onPickup:{},onSit:{},onShortcut:{ _ in })
                .modifier(PanelMeasurement(key:"bar"))
                .frame(maxWidth:wide ? size.width-chatWidth-32 : size.width-32,alignment:.trailing)
            return Color.clear.frame(width:size.width,height:size.height)
                .overlay(alignment:wide ? .bottomLeading : .bottom) { chat.padding(.bottom,gap) }
                .overlay(alignment:.bottomTrailing) {
                    bar.padding(.trailing,16)
                        .padding(.bottom,gap + (wide ? (legacy ? 16 : 0) : 107))
                }
                .environment(\.hudTestPrefix,prefix)
                .environment(GameContext.testing)
                .environment(PlaySession.testing)
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
                let old = try XCTUnwrap(HUDTestProbe.frames["old"+key])
                let new = try XCTUnwrap(HUDTestProbe.frames["new"+key])
                let delta = inset-gap + (width>=640 && ["bar","actions","slots"].contains(key) ? 16 : 0)
                XCTAssertEqual(new.height,old.height,accuracy:0.5)
                XCTAssertEqual(new.width,old.width,accuracy:0.5)
                XCTAssertEqual(new.minY-old.minY,delta,accuracy:0.5)
                XCTAssertEqual(new.maxY-old.maxY,delta,accuracy:0.5)
            }
            for k in ["chat","input","bar","slots","actions"] {
                print("MEASURE",width,height,k,HUDTestProbe.frames["old"+k]!,HUDTestProbe.frames["new"+k]!)
            }
            XCTAssertEqual(try XCTUnwrap(HUDTestProbe.frames["newchat"]).maxY,CGFloat(height)-gap,accuracy:0.5)
            print("PASS panels",width,height,"inset",inset,"margin",gap,"chat translation",inset-gap)
        }
    }
}

#endif
