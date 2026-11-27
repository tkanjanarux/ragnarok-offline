#!/usr/bin/env python3
"""Build/test portable production models/packets. SwiftUI and resource loading require Xcode.
Usage: python3 scripts/test-original-ui-core.py /tmp/ragoff-ui-checks
Then: docker run --rm -v /tmp/ragoff-ui-checks:/work -w /work swift:6.2 swift test -j 4
"""
from pathlib import Path
import shutil
import sys

root = Path(__file__).resolve().parents[1]
out = Path(sys.argv[1]).resolve()
if out.exists():
    raise SystemExit('Choose a new empty output directory.')
out.mkdir(parents=True)

def copy(source, target):
    destination = out / target
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(root / source, destination)

shutil.copytree(root / 'Packages/BinaryIO/Sources/BinaryIO', out / 'Sources/BinaryIO')
for name in ['PacketProtocol', 'PacketEncoder']:
    copy(f'Packages/RagnarokPackets/Sources/RagnarokPackets/{name}.swift', f'Sources/RagnarokPackets/{name}.swift')
copy('Packages/RagnarokPackets/Sources/RagnarokPackets/Generated/packets.swift', 'Sources/RagnarokPackets/packets.swift')
for name in ['CashShopRequest', 'QuestWirePacket', 'CharacterRename']:
    copy(f'Packages/RagnarokPackets/Sources/RagnarokPackets/Packets/{name}.swift', f'Sources/RagnarokPackets/{name}.swift')
# Copy the real error enum; exclude the macOS-only OSAllocatedUnfairLock decoder.
source = (root / 'Packages/RagnarokPackets/Sources/RagnarokPackets/PacketDecoder.swift').read_text()
(out / 'Sources/RagnarokPackets/PacketDecodingError.swift').write_text(source[source.index('public enum PacketDecodingError'):source.index('final public class PacketDecoder')])
for name in ['CashShop', 'QuestLog', 'QuestRichText', 'CharacterRename']:
    copy(f'Packages/RagnarokGame/Sources/RagnarokGame/Engine/{name}.swift', f'Sources/RagnarokGame/{name}.swift')
for name in ['CashShopTests', 'QuestLogTests', 'QuestRichTextTests', 'CharacterRenameTests']:
    copy(f'Packages/RagnarokGame/Tests/RagnarokGameTests/{name}.swift', f'Tests/RagnarokGameTests/{name}.swift')
for name in ['CashShopPacketTests', 'QuestActiveRequestTests', 'CharacterRenamePacketTests']:
    copy(f'Packages/RagnarokPackets/Tests/RagnarokPacketsTests/{name}.swift', f'Tests/RagnarokPacketsTests/{name}.swift')
(out / 'Package.swift').write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "OriginalUICoreChecks", targets: [
 .target(name: "BinaryIO"),
 .target(name: "RagnarokPackets", dependencies: ["BinaryIO"]),
 .target(name: "RagnarokGame", dependencies: ["RagnarokPackets"]),
 .testTarget(name: "RagnarokPacketsTests", dependencies: ["RagnarokPackets"]),
 .testTarget(name: "RagnarokGameTests", dependencies: ["RagnarokGame", "RagnarokPackets"])
])
''')
print(out)
