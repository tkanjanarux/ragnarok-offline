"""Prepare portable production party/packet/projection tests; run with Swift 6.2."""
from pathlib import Path
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
output = Path(sys.argv[1]).resolve()
subprocess.run([sys.executable, str(root / 'scripts/test-original-ui-core.py'), str(output)], check=True)
for name in ['PartyOptions', 'PartyLeaderChanged']:
    shutil.copy2(root / f'Packages/RagnarokPackets/Sources/RagnarokPackets/Packets/{name}.swift',
                 output / f'Sources/RagnarokPackets/{name}.swift')
for name in ['Party', 'MinimapProjection']:
    shutil.copy2(root / f'Packages/RagnarokGame/Sources/RagnarokGame/Engine/{name}.swift',
                 output / f'Sources/RagnarokGame/{name}.swift')
for name in ['PartyTests', 'PartyMinimapTests']:
    shutil.copy2(root / f'Packages/RagnarokGame/Tests/RagnarokGameTests/{name}.swift',
                 output / f'Tests/RagnarokGameTests/{name}.swift')
