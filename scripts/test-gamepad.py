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
