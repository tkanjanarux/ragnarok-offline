"""Build real packet codecs and item/cart reducers on Linux, without Apple UI/network.

No substitute packet or reducer implementations. PacketDecoder's Apple lock and
Network.framework are excluded; native app compilation covers their integration.
"""
from pathlib import Path
import shutil
import sys

root = Path(__file__).resolve().parents[1]
out = Path(sys.argv[1]).resolve()
modules = ['BinaryIO', 'RagnarokConstants', 'RagnarokPackets', 'RagnarokModels', 'RagnarokGame']
for module in modules:
    (out / 'Sources' / module).mkdir(parents=True, exist_ok=True)
(out / 'Tests/RagnarokGameTests').mkdir(parents=True, exist_ok=True)
(out / 'Package.swift').write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "ROFoundationsPortable", targets: [
 .target(name: "BinaryIO"), .target(name: "RagnarokConstants"),
 .target(name: "RagnarokPackets", dependencies: ["BinaryIO"]),
 .target(name: "RagnarokModels", dependencies: ["RagnarokConstants", "RagnarokPackets"]),
 .target(name: "RagnarokGame", dependencies: ["RagnarokModels", "RagnarokPackets"]),
 .testTarget(name: "RagnarokGameTests", dependencies: ["RagnarokGame", "RagnarokModels", "RagnarokPackets", "BinaryIO"])
])
''')
def copy(module, relative):
    path = root / f'Packages/{module}/Sources/{module}' / relative
    shutil.copy2(path, out / 'Sources' / module / path.name)
for path in (root / 'Packages/BinaryIO/Sources/BinaryIO').glob('*.swift'):
    copy('BinaryIO', path.name)
for name in ['ItemType', 'EquipPositions', 'ItemEquipAcknowledgeFlag']:
    copy('RagnarokConstants', f'Generated/{name}.swift')
for name in ['Generated/packets.swift', 'PacketProtocol.swift', 'PacketEncoder.swift',
             'Deprecated/ItemOptions.swift', 'Packets/ItemSelectionList.swift', 'Packets/EquipmentSwitch.swift']:
    copy('RagnarokPackets', name)
decoder = (root / 'Packages/RagnarokPackets/Sources/RagnarokPackets/PacketDecoder.swift').read_text()
(out / 'Sources/RagnarokPackets/PacketDecodingError.swift').write_text(
    decoder[decoder.index('public enum PacketDecodingError'):decoder.index('final public class')])
for name in ['Inventory', 'InventoryItem', 'UsedItem']:
    copy('RagnarokModels', name + '.swift')
for name in ['CartState', 'ItemSelectionState', 'RefineState', 'EquipmentSwitchState']:
    source = (root / f'Packages/RagnarokGame/Sources/RagnarokGame/Engine/{name}.swift').read_text()
    (out / f'Sources/RagnarokGame/{name}.swift').write_text(source.split('\nextension PlaySession')[0])
shutil.copy2(root / 'Packages/RagnarokGame/Tests/RagnarokGameTests/ItemFoundationTests.swift',
             out / 'Tests/RagnarokGameTests/ItemFoundationTests.swift')
print(out)
