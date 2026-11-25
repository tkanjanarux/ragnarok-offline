"""Check that both arms really used matched live fixtures and that High Orc exposure ended."""
from pathlib import Path
import gzip,json,re,sys
root=Path(sys.argv[1]);normal=json.loads((root/'normal.json').read_text());emergency=json.loads((root/'emergency.json').read_text())
assert len(normal)==40 and len(emergency)==4
for k,r in normal.items():
    assert r['build'].keys()==r['first'].keys()==r['last'].keys()
    assert len(r['first'])==6 and 179<=r['seconds']<=182
    assert r['metrics']['observed_s']>=r['seconds']-2
    assert not r['metrics'].get('probe')
    if k.endswith('native'):assert not r['metrics'].get('moves')
for k,r in emergency.items():
    assert r['maxorcs']==12 and r['metrics']['clear']==r['metrics']['probe']==1
    log=gzip.open(next((root/'emergency'/k).glob('*.gz')),'rt').read()
    probe=log.index('B_PROBE orc');clear=log.index('B_CLEAR orcs',probe)
    assert not re.search(r'B_M \d+ \d+ 1213 ',log[clear:])
    stops=list(re.finditer(r'B_STOP (\d+) (\w+) (\d+)',log))
    assert len(stops)==1 and stops[0].start()>probe
    assert 'B_REGROUP ' in log[stops[0].start():]
    assert not re.search(r'B_CAST \d+ 9500000[04] 54 ',log[stops[0].start():])
    assert max(r['deaths'].values(),default=0)<=1
print('Verified 40 complete six-actor normal windows and four bounded 12-High-Orc windows with no repeat deaths.')
