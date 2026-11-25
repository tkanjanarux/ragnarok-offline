"""Independent positive control: initialize one native shield before the observation window."""
from pathlib import Path

base=Path('/tests/brain_stage1/fixture.py').read_text()
setup=r"""
seed=stage/'npc/custom/qa_initial_shield.txt'
seed.write_text('-\tscript\tQA Initial Shield\t-1,{\nOnInit:\n if(attachrid(95000002)){ sc_start SC_KYRIE,120000,5; debugmes "B_SEEDED_SHIELD"; } end;\n}\n')
query('@loadnpc npc/custom/qa_initial_shield.txt','B_SEEDED_SHIELD')
"""
base=base.replace('exec(compile(source,',"""source=source.replace("query('@brainmark start'",setup+"\\nquery('@brainmark start'",1)
exec(compile(source,""")
exec(compile(base,'/tests/brain_stage1/fixture.py','exec'))
