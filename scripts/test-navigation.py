"""Compile the production route core on Linux; Lua/state/visual tests run in Xcode."""
from pathlib import Path
import shutil
import sys

root = Path(__file__).resolve().parents[1]
output = Path(sys.argv[1]).resolve()
for directory in ['Sources/RagnarokScript', 'Sources/RagnarokGame', 'Tests/RagnarokGameTests']:
    (output / directory).mkdir(parents=True, exist_ok=True)
(output / 'Package.swift').write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "NavigationPortable", targets: [
 .target(name: "RagnarokScript"),
 .target(name: "RagnarokGame", dependencies: ["RagnarokScript"]),
 .testTarget(name: "RagnarokGameTests", dependencies: ["RagnarokGame", "RagnarokScript"])
])
''')
data = (root / 'Packages/RagnarokScript/Sources/RagnarokScript/NavigationData.swift').read_text()
data = data.split('    /// Navi_Map/Npc/Mob/Link')[0] + '}\n'
data = '\n'.join(line for line in data.splitlines() if not line.startswith('import Ragnarok'))
(output / 'Sources/RagnarokScript/NavigationData.swift').write_text(data)
for name in ['NavigationRoute', 'MinimapProjection']:
    shutil.copy2(root / f'Packages/RagnarokGame/Sources/RagnarokGame/Engine/{name}.swift', output / f'Sources/RagnarokGame/{name}.swift')
tests = (root / 'Packages/RagnarokGame/Tests/RagnarokGameTests/NavigationTests.swift').read_text()
prefix = tests[tests.index('@Suite @MainActor'):tests.index('    @Test func resourceColumns')]
cases = tests[tests.index('    @Test func longRoutes'):tests.index('    func awaitCalculation')]
(output / 'Tests/RagnarokGameTests/NavigationTests.swift').write_text(
    'import Foundation\nimport RagnarokScript\nimport Testing\n@testable import RagnarokGame\n' + prefix + cases + '}\n')
print(output)
