"""Exercise ordinary RO packets against disposable, loopback-only native server processes."""

import argparse
import json
import os
import re
import shutil
import socket
import struct
import sqlite3
import subprocess
import tempfile
import time
from pathlib import Path
from contextlib import contextmanager

parser = argparse.ArgumentParser()
parser.add_argument("profile", choices=("production", "playable"))
parser.add_argument("--source", type=Path, help="Reconstructed native profile with runtime templates and bin/")
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
source = (args.source or repo / "build" / ("server-" + args.profile)).resolve()
run = Path(tempfile.mkdtemp(prefix="ragoff-" + args.profile + "-"))
print(f"Runtime and logs: {run}", flush=True)
shutil.copytree(source / "conf", run / "conf")
for part in ("db", "npc"):
    shutil.copytree(source / part, run / part)
with sqlite3.connect(run / "ragnarok.sqlite3") as db:
    for schema in ("main.sql", "logs.sql"):
        lines = (source / "sqlite-files" / schema).read_text().splitlines()
        db.executescript("\n".join("-- " + line if line.startswith("#") else line for line in lines))
    # The fresh schema omits this upstream character-setting migration.
    db.executescript((source / "sqlite-files/upgrades/upgrade_20250803.sql").read_text())
    assert db.execute("PRAGMA integrity_check").fetchone() == ("ok",)
    password = os.urandom(10).hex().encode()
    db.execute("INSERT INTO login (account_id, userid, user_pass, sex) VALUES (2000001,'loop-fixture',?,'M')", (password.decode(),))
    db.execute("""INSERT INTO char (char_id,account_id,name,class,base_level,job_level,zeny,str,agi,vit,dex,max_hp,hp,max_sp,sp,last_map,last_x,last_y,save_map,sex)
                  VALUES (150001,2000001,'LoopFixture',5,50,40,10000,90,50,50,90,1000,1000,100,100,'prontera',150,150,'prontera','M')""")
    seed = [(2302, 1, 0, 0), (4001, 1, 1, 0), (611, 3, 1, 0),
            (1011, 1, 1, 0), (1203, 1, 1, 0), (1010, 6, 1, 0), (909, 4, 1, 0)]
    seed += [(1201, 1, 1, 9)] * 5
    for item, count, identified, refine in seed:
        db.execute("INSERT INTO inventory(char_id,nameid,amount,identify,refine) VALUES (150001,?,?,?,?)", (item,count,identified,refine))
    # Keep the inter-server account local to this disposable database.
    # A fresh credential is shared by the char and map servers.
    secret = os.urandom(10).hex()
    db.execute("UPDATE login SET user_pass = ? WHERE account_id = 1 AND sex = 'S'", (secret,))

held = []
for _ in range(3):
    listener = socket.socket()
    listener.bind(("127.0.0.1", 0))
    held.append(listener)
login, char, map_port = [s.getsockname()[1] for s in held]
settings = {
    "login": {"login_port": login},
    "char": {"login_ip": "127.0.0.1", "char_ip": "127.0.0.1", "login_port": login,
             "char_port": char, "passwd": secret, "pincode_enabled": "no"},
    "map": {"char_ip": "127.0.0.1", "map_ip": "127.0.0.1", "char_port": char,
            "map_port": map_port, "passwd": secret},
}
for role, values in settings.items():
    file = run / "conf/import" / (role + "_conf.txt")
    with file.open("a") as cfg:
        cfg.write("\nbind_ip: 127.0.0.1\n")
        for key, val in values.items():
            cfg.write(f"{key}: {val}\n")
# The deployment templates enable companion features whose schema is not
# in the checkout. Disable them only in this disposable local runtime.
with (run / "conf/import/battle_conf.txt").open("a") as cfg:
    for feature in ("enable", "loadouts", "owner_progression", "supplies"):
        cfg.write(f"\ncompanion_{feature}: 0\n")
for listener in held:
    listener.close()

(run / "npc/loop-fixture.txt").write_text(
    "prontera,151,150,4\tshop\tLoop Shop\t4_F_KAFRA1,909:12\n"
    "prontera,150,151,4\tscript\tLoop Storage\t4_F_KAFRA1,{ openstorage; end; }\n"
    "prontera,149,150,4\tscript\tLoop Refiner\t4_M_DWARF,{ refineui(); end; }\n"
    'prontera,151,151,4\tscript\tLoop Spawner\t4_F_KAFRA1,{ monster "prontera",150,149,"Loop Poring",1002,1; end; }\n'
)
with (run / "npc/scripts_custom.conf").open("a") as cfg:
    cfg.write("\nnpc: npc/loop-fixture.txt\n")

processes = {}
def log(role):
    raw = (run / (role + ".log")).read_text(errors="replace")
    return re.sub(r"\x1b\[[0-9;]*[A-Za-z]", "", raw)
def wait_for(role, pattern, seconds=120):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        for name, proc in processes.items():
            if proc.poll() is not None:
                raise RuntimeError(f"{name} exited with {proc.returncode}, see {run}")
        match = re.search(pattern, log(role), re.IGNORECASE)
        if match:
            print(match.group(0), flush=True)
            return
        time.sleep(0.5)
    raise RuntimeError(f"Timed out waiting for {pattern!r} in {role}.log, see {run}")

def connect(port):
    return socket.create_connection(("127.0.0.1", port), timeout=3)

def recv_exact(sock, amount):
    buf = b""
    while len(buf) < amount:
        chunk = sock.recv(amount-len(buf))
        if not chunk:
            raise EOFError("socket closed")
        buf += chunk
    return buf

def collect(sock, duration=0.4):
    sock.settimeout(duration)
    buf = b""
    try:
        while chunk := sock.recv(65536):
            buf += chunk
    except TimeoutError:
        pass
    finally:
        sock.settimeout(3)
    return buf

generated=repo/'Packages/RagnarokPackets/Sources/RagnarokPackets/Generated'
wire=(generated/'packets.swift').read_text()
headers={key:int(val,16) for key,val in re.findall(r'public let (\w+): Int16 = (0x[0-9a-f]+)',wire)}
rules=dict(re.findall(r'public struct (\w+): [^\n]+ \{\n    public static var size: Int \{\n        (.+)',wire))
rules["ItemOptions"]="5"
def size(expr):
    expr=re.sub(r'(\w+)\.size',lambda m:str(size(rules[m[1]])),expr)
    if not re.fullmatch(r'[0-9*+() -]+',expr):
        raise ValueError(expr)
    return eval(expr, {"__builtins__": {}}, {})
lengths={}
for key, expr in re.findall(r'add_packet\((\w+), ([^,]+), ',(generated/'packetdb.swift').read_text()):
    try:
        lengths[int(key,16) if key.startswith('0x') else headers[key]]=size(expr)
    except (KeyError,ValueError):
        continue
for name, op in headers.items():
    try:
        lengths[op]=size(rules[name.replace("HEADER_", "PACKET_")])
    except (KeyError,ValueError):
        pass
lengths.update({0x2eb:13,0x283:6,0x9fe:-1,0x9ff:-1,0x9fd:-1,0x9d7:14,0xb18:4,0xb08:-1,0xb09:-1,0xb0a:-1,0xb0b:4})
def frames(data):
    offset=0
    while offset < len(data):
        op=struct.unpack_from('<H',data,offset)[0]
        if op not in lengths or (lengths[op] != -1 and lengths[op] < 2):
            raise ValueError(f'Unknown opcode at {offset}/{len(data)}: {data[offset:offset+32].hex()}')
        length=lengths[op]
        if length==-1: length=struct.unpack_from('<H',data,offset+2)[0]
        assert 2 <= length <= len(data)-offset,(hex(op),length,len(data)-offset)
        yield op,data[offset:offset+length]
        offset+=length

@contextmanager
def map_login():
    with connect(login) as sock:
        sock.sendall(struct.pack("<HI24s24sB", 0x64, 0, b"loop-fixture", password, 0))
        opcode, length = struct.unpack("<HH", recv_exact(sock, 4))
        assert opcode == 0xac4, hex(opcode)
        auth = recv_exact(sock, length-4)
        key1, account, key2 = struct.unpack_from("<III", auth)
    with connect(char) as sock:
        sock.sendall(struct.pack("<HIIIHB",0x65,account,key1,key2,0,1))
        data = collect(sock)
        assert data[:4] == struct.pack("<I",account)
        characters = require_packet(list(frames(data[4:])), 0x6b)
        cid_from_list, _, zeny = struct.unpack_from("<IQI", characters, 27)
        sock.sendall(struct.pack("<HB",0x66,0))
        data = collect(sock)
        assert data[:2] == b"\xc5\x0a",data[:40].hex()
        cid = struct.unpack_from("<I",data,2)[0]
        assert cid == cid_from_list
    sock=connect(map_port)
    sock.sendall(struct.pack("<HIIIIB",0x436,account,cid,key1,0,1)[:18] + b"\0"*4 + b"\1")
    data=collect(sock, 0.9)

    connected = list(frames(data))
    require_packet(connected, 0x2eb)
    sock.sendall(struct.pack("<H",0x7d))
    data=collect(sock, 0.9)
    packets = connected + list(frames(data))

    with sock:
        yield Client(sock, account, zeny, packets)

class Client:
    """Read selected authoritative map packets into a ledger independent of SQLite."""

    def __init__(self, sock, aid, zeny, packets):
        self.sock = sock
        self.aid = aid
        self.inventory = {}
        self.storage = {}
        self.zeny = zeny
        self.weight = None
        self.max_weight = None
        self.npcs = {}
        self.storage_slots = None
        self.apply(packets)

    def apply(self, packets):
        for op, pkt in packets:
            if op in (0xb0, 0xb1):
                stat, value = struct.unpack_from("<HI", pkt, 2)
                attr = {20: "zeny", 24: "weight", 25: "max_weight"}.get(stat)
                if attr:
                    setattr(self, attr, value)
            elif op in (0x9fe, 0x9ff):
                name = pkt[-24:].partition(b"\0")[0].decode(errors="replace")
                self.npcs[name] = struct.unpack_from("<I", pkt, 5)[0]
            elif op == 0xb08:
                if pkt[4] in (0, 2):
                    (self.storage if pkt[4] == 2 else self.inventory).clear()
            elif op in (0xb09, 0xb39):
                target = self.storage if pkt[4] == 2 else self.inventory
                stride = 34 if op == 0xb09 else 68
                assert (len(pkt)-5) % stride == 0, (op, len(pkt))
                for start in range(5, len(pkt), stride):
                    row = pkt[start:start+stride]
                    index, item = struct.unpack_from("<HI", row)
                    if op == 0xb09:
                        count, equip, card = struct.unpack_from("<HII", row, 7)
                        refine = 0
                    else:
                        count = 1
                        equip, card = struct.unpack_from("<II", row, 11)
                        refine = row[-3]
                    target[index] = [item, count, row[-1] & 1, refine, card, equip]
            elif op in (0xb41, 0xb44):
                target = self.storage if op == 0xb44 else self.inventory
                if op == 0xb41:
                    if pkt[33] != 0:
                        continue
                    index, count, item, ident = struct.unpack_from("<HHIB", pkt, 2)
                    card = struct.unpack_from("<I", pkt, 12)[0]
                else:
                    index, count, item, _, ident = struct.unpack_from("<HIIBB", pkt, 2)
                    card = struct.unpack_from("<I", pkt, 15)[0]
                if index in target:
                    assert target[index][0] == item
                    target[index][1] += count
                else:
                    target[index] = [item, count, ident, pkt[-2], card, 0]
            elif op in (0x7fa, 0xaf, 0xf6):
                index, count = (struct.unpack_from("<HH", pkt, 4) if op == 0x7fa
                                else struct.unpack_from("<HI" if op == 0xf6 else "<HH", pkt, 2))
                if count:
                    self.remove(self.storage if op == 0xf6 else self.inventory, index, count)
            elif op == 0x1c8 and pkt[-1] and (index := struct.unpack_from("<H", pkt, 2)[0]) in self.inventory:
                count = struct.unpack_from("<H", pkt, 12)[0]
                self.remove(self.inventory, index, self.inventory[index][1] - count)
            elif op == 0x179 and pkt[-1] == 0:
                self.inventory[struct.unpack_from("<H", pkt, 2)[0]][2] = 1
            elif op == 0x17d and pkt[-1] == 0:
                equip, card = struct.unpack_from("<HH", pkt, 2)
                self.inventory[equip][4] = self.inventory[card][0]
                self.remove(self.inventory, card, 1)
            elif op == 0x188:
                result, index, level = struct.unpack_from("<HHH", pkt, 2)
                if result in (0, 2):
                    self.inventory[index][3] = level
            elif op == 0x999 and pkt[-1] == 0:
                index, equip = struct.unpack_from("<HI", pkt, 2)
                self.inventory[index][5] = equip
            elif op == 0xf2:
                self.storage_slots = struct.unpack_from("<HH", pkt, 2)

    @staticmethod
    def remove(target, index, count):
        assert 0 <= count <= target[index][1], (index, count, target)
        target[index][1] -= count
        if not target[index][1]:
            del target[index]

    def index(self, item, storage=False):
        return next(index for index, row in (self.storage if storage else self.inventory).items() if row[0] == item)

    def count(self, item, storage=False):
        return sum(row[1] for row in (self.storage if storage else self.inventory).values() if row[0] == item)

    def send(self, fmt, *fields, duration=0.25):
        self.sock.sendall(struct.pack("<"+fmt, *fields))
        packets = list(frames(collect(self.sock, duration)))
        self.apply(packets)
        return packets

    def identify_list(self, magnifier):
        grant = require_packet(self.send("HHI", 0x439, magnifier, self.aid), 0x147)
        skill = struct.unpack_from("<H", grant, 2)[0]
        level = struct.unpack_from("<H", grant, 8)[0]
        assert skill == 40 and level == 1
        return self.send("HHHI", 0x438, level, skill, self.aid)

    def walk(self, x, y):
        coords = bytes((x >> 2, ((x & 3) << 6) | (y >> 4), (y & 15) << 4))
        return self.send("H3s", 0x35f, coords, duration=0.8)

    def open(self, name):
        return self.send("HIB", 0x90, self.npcs[name], 0)

    def state(self):
        return [self.zeny, self.weight, self.max_weight,
                sorted(self.inventory.values()), sorted(self.storage.values()), self.storage_slots]

    def checkpoint(self, stage):
        print(json.dumps({
            "stage": stage, "zeny": self.zeny, "weight": self.weight, "max_weight": self.max_weight,
            "inventory_slots_used": len(self.inventory), "storage_slots": self.storage_slots,
            "inventory": sorted(self.inventory.values()), "storage": sorted(self.storage.values()),
        }, separators=(",", ":")), flush=True)


def packet(packets, opcode):
    return next((pkt for op, pkt in packets if op == opcode), None)


def require_packet(packets, opcode):
    result = packet(packets, opcode)
    assert result is not None, (hex(opcode), [hex(op) for op,_ in packets])
    return result


def scenario():
    with map_login() as c:
        c.checkpoint("initial")
        jellopy = c.index(909)
        floor = None
        for i in range(6):
            spawned = c.open("Loop Spawner")
            assert any(op in (0x9fe, 0x9ff) and b"Loop Poring" in data for op, data in spawned)
            mob = c.npcs["Loop Poring"]
            # Continuous basic attack is one player action and handles a miss.
            drops = c.send("HIB", 0x437, mob, 7, duration=2.1)
            assert any(op == 0x80 and struct.unpack_from("<I", data, 2)[0] == mob and data[-1] == 1
                       for op, data in drops), "Poring did not die during the attack window"
            floor = next((data for op, data in drops if op == 0xadd and struct.unpack_from("<I", data, 6)[0] == 909), None)
            if floor:
                print(f"Jellopy dropped after {i+1} kill(s)", flush=True)
                break
        assert floor, "None of six normal Poring kills dropped Jellopy"
        c.checkpoint("kill")
        aid = struct.unpack_from("<I", floor, 2)[0]
        x, y = struct.unpack_from("<HH", floor, 13)
        c.walk(x, y)
        old_weight = c.weight
        pickup = require_packet(c.send("HI", 0x362, aid, duration=1.0), 0xb41)
        assert c.count(909) == 5 and c.weight == old_weight+10, (pickup.hex(), c.state())
        c.checkpoint("pickup")
        assert require_packet(c.send("HI", 0x362, aid), 0xb41)[33] != 0
        assert c.count(909) == 5 and c.weight == old_weight+10
        c.checkpoint("pickup duplicate rejected")
        c.walk(150, 150)
        shop = c.npcs["Loop Shop"]
        require_packet(c.open("Loop Shop"), 0xc4)
        offer = require_packet(c.send("HIB",0xc5,shop,1),0xc7)
        offers = {i: (p, o) for i,p,o in struct.iter_unpack("<HII",offer[4:])}
        price, overcharge = offers[jellopy]
        assert require_packet(c.send("HHHH",0xc9,8,jellopy,1),0xcb)[-1] == 0
        assert c.zeny == 10000+(overcharge or price) and c.count(909) == 4 and c.weight == old_weight
        c.checkpoint("sale")
        assert require_packet(c.send("HHHH",0xc9,8,jellopy,1),0xcb)[-1] == 1
        assert c.count(909) == 4 and c.zeny == 10000+(overcharge or price)
        c.checkpoint("sale duplicate rejected")

        require_packet(c.open("Loop Storage"),0xb08)
        require_packet(c.send("HHI",0x364,jellopy,2),0xb44)
        assert c.count(909) == 2 and c.count(909, True) == 2 and c.weight == old_weight-20
        c.checkpoint("deposit")
        require_packet(c.send("HHI",0x365,c.index(909,True),1),0xf6)
        assert c.count(909) == 3 and c.count(909,True) == 1 and c.weight == old_weight-10
        c.checkpoint("withdraw")
        require_packet(c.send("H",0x193),0xf8)

        shirt = c.index(2302)
        card = c.index(4001)
        before = c.state()
        assert not packet(c.send("HH", 0x17a, card), 0x17b)
        assert c.state() == before
        c.checkpoint("no eligible equipment for card")
        magnifier = c.index(611)
        require_packet(c.identify_list(magnifier),0x177)
        assert not packet(c.send("HH",0x178,0xffff),0x179)
        assert c.inventory[shirt][2] == 0
        c.checkpoint("identify cancel")
        require_packet(c.identify_list(magnifier),0x177)
        assert require_packet(c.send("HH",0x178,shirt),0x179)[-1] == 0
        assert c.inventory[shirt][2] == 1
        c.checkpoint("identify success")
        assert not packet(c.send("HH",0x178,shirt),0x179)
        c.checkpoint("identify duplicate ignored")

        assert not packet(c.identify_list(magnifier), 0x177)
        assert c.inventory[shirt][2] == 1
        c.checkpoint("identify no eligible item (raw client)")
        before = c.state()
        require_packet(c.send("HH",0x17a,card),0x17b)
        # Card-menu cancellation is client-side only. No composition request is sent.
        assert c.state() == before
        c.checkpoint("card cancel")
        require_packet(c.send("HH",0x17a,card),0x17b)
        assert require_packet(c.send("HHH",0x17c,card,shirt),0x17d)[-1] == 0
        assert c.inventory[shirt][4] == 4001 and c.count(4001) == 0
        c.checkpoint("card success")
        assert not packet(c.send("HHH",0x17c,card,shirt),0x17d)
        c.checkpoint("card duplicate ignored")

        require_packet(c.open("Loop Refiner"),0xaa0)
        knife = c.index(1203)
        require_packet(c.send("HH",0xaa1,knife),0xaa2)
        c.send("H",0xaa4)
        c.checkpoint("refine cancel")
        require_packet(c.open("Loop Refiner"),0xaa0)
        offer = require_packet(c.send("HH",0xaa1,knife),0xaa2)
        costs = {i:(chance,cost) for i,chance,cost in struct.iter_unpack("<IBI",offer[7:])}
        missing = next(material for material in costs if c.count(material) == 0)
        before = c.state()
        assert not packet(c.send("HHIB",0xaa3,knife,missing,0),0x188)
        assert c.state() == before
        c.checkpoint("refine missing offered material")
        assert costs[1010][0] == 100
        before_zeny = c.zeny
        result = require_packet(c.send("HHIB",0xaa3,knife,1010,0),0x188)
        assert struct.unpack_from("<HHH",result,2) == (0,knife,1)
        assert c.zeny == before_zeny-costs[1010][1] and c.count(1010) == 5
        c.checkpoint("refine success")
        high_knives = [i for i, row in c.inventory.items() if row[0] == 1201]
        for high in high_knives:
            offer = require_packet(c.send("HH", 0xaa1, high), 0xaa2)
            chance, cost = {i: (chance, cost) for i, chance, cost in struct.iter_unpack("<IBI", offer[7:])}[1010]
            assert 0 < chance < 100
            before_zeny, before_ore, before_weight = c.zeny, c.count(1010), c.weight
            result = require_packet(c.send("HHIB", 0xaa3, high, 1010, 0), 0x188)
            outcome, index, level = struct.unpack_from("<HHH", result, 2)
            assert index == high
            assert c.zeny == before_zeny-cost and c.count(1010) == before_ore-1
            if outcome == 1:
                assert high not in c.inventory and c.weight == before_weight-200-400
                c.checkpoint("refine failure consumes fee, ore and knife")
                break
            assert outcome == 0 and level == 10 and c.weight == before_weight-200
            c.checkpoint("normal +10 roll succeeded, next independent fixture knife")
        else:
            raise AssertionError("All independent +10 refine rolls succeeded")

        c.send("H", 0xaa4)
        c.open("Loop Storage")
        require_packet(c.send("HHI", 0x364, knife, 1), 0xb44)
        assert c.storage[c.index(1203, True)][3] == 1 and not c.count(1203)
        c.checkpoint("deposit refined equipment")
        require_packet(c.send("HHI", 0x365, c.index(1203, True), 1), 0xf6)
        assert c.inventory[c.index(1203)][3] == 1 and not c.count(1203, True)
        c.checkpoint("withdraw refined equipment")
        require_packet(c.send("H",0x193),0xf8)

        assert require_packet(c.send("HHI",0x998,shirt,16),0x999)[-1] == 0
        assert c.inventory[shirt][5] == 16
        c.checkpoint("equip")
        final = c.state()
        # Keep the source profile's 10 s logout cooldown unchanged.
        time.sleep(10.2)
        quit_ack = require_packet(c.send("HH", 0x18a, 0), 0x18b)
        assert struct.unpack_from("<H", quit_ack, 2)[0] == 0, quit_ack.hex()
        c.checkpoint("normal logout")

    wait_offline()
    with map_login() as c:
        c.open("Loop Storage")
        c.checkpoint("reconnect")
        assert c.state() == final
        assert_db(c)
        # Send once and drop the connection without reading a result. A fresh
        # login must reveal either one committed move or no move, never a replay.
        c.sock.sendall(struct.pack("<HHI", 0x364, c.index(909), 1))
    wait_offline()
    with map_login() as c:
        c.open("Loop Storage")
        c.checkpoint("reconnect after disconnect before reading deposit result")
        moved = 3-c.count(909)
        assert moved in (0, 1)
        assert c.count(909, True) == 1+moved and c.weight == final[1]-10*moved
        assert c.zeny == final[0] and c.max_weight == final[2] and c.storage_slots == final[5]
        assert sorted(row for row in c.inventory.values() if row[0] != 909) == [row for row in final[3] if row[0] != 909]
        assert sorted(row for row in c.storage.values() if row[0] != 909) == [row for row in final[4] if row[0] != 909]
        assert_db(c)


def wait_offline():
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        with sqlite3.connect(run / "ragnarok.sqlite3") as db:
            if db.execute("SELECT online FROM char WHERE char_id=150001").fetchone() == (0,):
                return
        time.sleep(0.1)
    raise AssertionError("Fixture character never became offline")


def assert_db(c):
    columns = "nameid,amount,identify,refine,card0,equip"
    with sqlite3.connect(run / "ragnarok.sqlite3") as db:
        assert db.execute("PRAGMA integrity_check").fetchone() == ("ok",)
        assert db.execute("SELECT zeny FROM char WHERE char_id=150001").fetchone() == (c.zeny,)
        for table, key, fixture, record in (
            ("inventory", "char_id", 150001, c.inventory),
            ("storage", "account_id", 2000001, c.storage),
        ):
            rows = db.execute(f"SELECT {columns} FROM {table} WHERE {key}=?", (fixture,)).fetchall()
            # The WearState of NORMALITEM_INFO reflects equip compatibility for
            # unequipped cards, not the database's equipment bitset.
            expected = [tuple(row[:5] + [0 if row[0] == 4001 else row[5]]) for row in record.values()]
            assert sorted(rows) == sorted(expected), (table, rows, expected)


try:
    for role in settings:
        with (run / (role + ".log")).open("wb") as out:
            binary = run / (role + "-server")
            binary.symlink_to(source / "bin" / binary.name)
            processes[role] = subprocess.Popen(
                ["stdbuf", "-oL", "-eL", str(binary)],
                cwd=run, stdin=subprocess.DEVNULL, stdout=out, stderr=subprocess.STDOUT)
        wait_for(role, "listening on (?:the )?port [^0-9]*[0-9]+")
    wait_for("char", r"Connected to login-server")
    wait_for("char", r"Map-Server \d+ connected: [1-9]\d* maps")
    print(f"{args.profile}: login, char, and map stack passed the map-registration smoke test (companions disabled).", flush=True)
    scenario()
    print(f"PASS: {args.profile} packet ledger and reconnect SQLite assertions", flush=True)
finally:
    for proc in reversed(list(processes.values())):
        if proc.poll() is None:
            proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
