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
