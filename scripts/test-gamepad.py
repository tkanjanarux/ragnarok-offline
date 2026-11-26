from pathlib import Path
import shutil,sys
root=Path(__file__).resolve().parents[1];out=Path(sys.argv[1]).resolve()
(out/'Sources/RagnarokGame').mkdir(parents=True,exist_ok=True)
(out/'Tests/RagnarokGameTests').mkdir(parents=True,exist_ok=True)
(out/'Package.swift').write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "GamepadPortable", targets: [.target(name: "RagnarokGame"), .testTarget(name: "RagnarokGameTests", dependencies: ["RagnarokGame"])])
''')
shutil.copy2(root/'Packages/RagnarokGame/Sources/RagnarokGame/Engine/GamepadInput.swift',out/'Sources/RagnarokGame/GamepadInput.swift')
shutil.copy2(root/'Packages/RagnarokGame/Tests/RagnarokGameTests/GamepadInputTests.swift',out/'Tests/RagnarokGameTests/GamepadInputTests.swift')
print(out)

# Compile actual skill flag policy, without depending on Apple/network modules.
skill=(root/'Packages/RagnarokModels/Sources/RagnarokModels/SkillInfo.swift').read_text()
policy=skill[skill.index('extension SkillInfo {'):skill.index('extension SkillInfo: Comparable')]
flags=(root/'Packages/RagnarokConstants/Sources/RagnarokConstants/Generated/SkillInfoFlag.swift').read_text().split('extension SkillInfoFlag:')[0]
(out/'Sources/RagnarokGame/SkillInfoPolicy.swift').write_text(flags+'\nstruct SkillInfo { var flag: Int = 1; var spCost = 0; var level = 1; var skillID = 1; var attackRange = 5 }\n'+policy)

# Actual pathfinder, with only the asset-backed grid replaced by a tiny open fixture.
pathfinder=(root/'Packages/RagnarokGame/Sources/RagnarokGame/Core/PathFinder.swift').read_text()
(out/'Sources/RagnarokGame/PathFinder.swift').write_text(pathfinder)
(out/'Sources/RagnarokGame/MapGrid.swift').write_text("""
struct MapGrid {
    let width = 64, height = 64
    struct Cell { var isWalkable = true }
    subscript(_ position: SIMD2<Int>) -> Cell { Cell() }
}
""")
(out/'Tests/RagnarokGameTests/GamepadRangePathTests.swift').write_text("""
import Testing
@testable import RagnarokGame
struct GamepadRangePathTests {
    @Test func acquisitionMatchesActualAttackPathfinderDiagonalMetric() {
        let finder = PathFinder(mapGrid:MapGrid())
        let origin = SIMD2(20,20), target = SIMD2(34,34)
        #expect(finder.findPath(from:origin,to:target,within:14) == [origin])
        #expect(finder.findPath(from:origin,to:target,within:13) != [origin])
        #expect(GamepadTargetRange(attackRange:14).containsSoft(SIMD2(14,14)))
        #expect(GamepadTargetRange(attackRange:14).containsLock(SIMD2(14,14)))
        #expect(!GamepadTargetRange(attackRange:13).containsSoft(SIMD2(14,14)))
    }
    @Test func longRangeAcquisitionDoesNotRequireThirteenCellWalkToTargetFeet() {
        let finder = PathFinder(mapGrid:MapGrid()), origin = SIMD2(10,10), target = SIMD2(30,10)
        #expect(finder.canMoveStraight(from:origin,to:target))
        #expect(finder.findPath(from:origin,to:target,within:1).count > 13)
        #expect(finder.findPath(from:origin,to:target,within:20) == [origin])
        #expect(GamepadTargetRange(attackRange:20).containsLock(SIMD2(20,0)))
    }
}
""")
