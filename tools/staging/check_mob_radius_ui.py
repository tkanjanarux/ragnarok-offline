"""Exercise the actual chat setter and both generations of roster on an isolated map."""
from nearby_hunt_fixture import c, knight, priest, mage, wait
from protocol import login

seq = 6000
modern = "phase1 loop1 puller1 team2 radius1 hunt1"

def team(action="list", flags=modern):
    global seq
    seq += 1
    c.command(f"@companion ui {seq} {action} ui2 hunter1 voice1 bird1 {flags}")
    prefix = f"[RCO1] {seq} ".encode()
    result = None
    while True:
        packet = wait(c, lambda op, b: op == 0x8e and b[4:].startswith(prefix))
        row = packet[4 + len(prefix):].rstrip(b"\0").decode().split()
        if row[0] == "team":
            result = row[1:]
        if row[0] == "end":
            assert result is not None
            return result

assert team() == ["assist", "5", "auto", "15"]
for value, expected in [(96, 96), (5, 96), (97, 96), (47, 47), (6, 6)]:
    c.command(f"@companion mob radius {value}")
    assert team() == ["assist", "5", "auto", str(expected)]
assert team(flags="loop1 puller1 team2 hunt1") == ["assist", "5", "auto"]
assert team(flags="team2 hunt1") == ["assist", "5"]
for member in (priest, knight, mage):
    team("assist " + str(member["id"]))
assert team("mob on") == ["mob", "5", "auto", "6"]
c.command("@companion mob radius 96")
assert team() == ["mob", "5", "auto", "96"]
assert team("mob off") == ["assist", "5", "auto", "96"]
c.close()
c = login()
assert team() == ["assist", "5", "auto", "96"]
c.close()
print("PASS saved radius, legacy team frames, active update, bounds and relogin")
