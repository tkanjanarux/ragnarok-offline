import Foundation
import UIKit
import ImageIO
import CoreText

let examples = ["ลูกธนูหมดแล้วจ้า!", "SP ไม่พอจ้า", "ขอฮีลหน่อย!", "ขอบคุณที่ช่วยนะ"]
for (index, example) in examples.enumerated() {
    let descriptor = TextDescriptor(text: AttributedString(example), bubble: true)
    let image = descriptor.makeImage()!
    precondition(image.width > 80 && image.height > 36)
    let line = CTLineCreateWithAttributedString( NSAttributedString(string: example, attributes: [.font: UIFont(name: "Arial", size: 12)!]))
    let runs = CTLineGetGlyphRuns(line) as! [CTRun]
    for run in runs {
        var glyphs = [CGGlyph](repeating: 0, count: CTRunGetGlyphCount(run))
        CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
        precondition(!glyphs.contains(0), "Missing Thai glyph")
    }
    let dest = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("bubble-\(index).png")
    let writer = CGImageDestinationCreateWithURL(dest as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(writer,image,nil)
    precondition(CGImageDestinationFinalize(writer))
}
print("PASS Thai shaped glyphs and four actual chat bubble textures using iPhone UIKit")
