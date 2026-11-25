"""Exercise the Your Bag filter and native staff transfer on an isolated test server."""
import time
from check_m6_profiles import api
from check_m8_gear import conserved, held, returned, transfer
from protocol import login


def inspect_bag(client, profile, token):
    client.command(f"@companion ui {token} inspect {profile} ui2 skills4")
    slots = {}
    while True:
        opcode, payload = client.packet()
        if opcode != 0x8E:
            continue
        fields = payload[4:].rstrip(b"\0").decode().split()
        if fields[:2] != ["[RCO1]", str(token)]:
            continue
        if fields[2] == "bag":
            slot, item, uid = map(int, fields[3:])
            slots.setdefault(item, []).append((slot, uid))
        if fields[2] == "end":
            return slots


client = login()
client.command("@setbattleflag companion_enable 1")
client.command("@itemreset")
rows, _, _ = api(client, "list")
client.command("@set BaseLevel 80")
for item in (1601, 1604, 1607, 1610, 1610, 1613):
    client.command(f"@item {item} 1")
time.sleep(1)
for job, career in ((9, "wizard"), (8, "priest")):
    if not any(row["job"] == job for row in rows):
        rows, _, _ = api(client, f"recruit {career}")
    profile = next(row["id"] for row in rows if row["job"] == job)
    bag = inspect_bag(client, profile, 90010 - job)
    assert 1613 in bag, "Mighty Staff uses native passive STR and SP drain bonuses"
    assert len(bag[1610]) == 2 and len({uid for _, uid in bag[1610]}) == 2
    for item in (1601, 1604, 1607, 1610, 1613):
        for slot, uid in bag[item]:
            transfer(client, profile, slot)
            gear = next(g for g in held(profile) if int(g[1]) == uid)
            conserved(uid)
            api(client, f"summon {profile}")
            api(client, f"stop {profile}")
            assert "equipped and saved" in api(client, f"equip {profile} {gear[0]}")[1]
            assert next(g for g in held(profile) if g[0] == gear[0])[2] != 0
            api(client, f"bench {profile}")
            transfer(client, profile, gear[0], False)
            returned(uid)
client.close()
print("Staff list, equip and return with the same UID passed for all five item types.")
