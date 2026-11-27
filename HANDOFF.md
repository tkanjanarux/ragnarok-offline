# Handoff — 2026-11-25

เอกสารส่งต่องานสำหรับ canonical baseline ของโปรเจกต์ ไม่เก็บ credentials,
ข้อมูลผู้เล่น หรือรายละเอียด backup ส่วนตัวใน repo สาธารณะนี้

## จุดเริ่มต้นและ Git

- ทำงานจาก `main` ของ `tkanjanarux/ragnarok-offline` เท่านั้น
- Baseline consolidation commit: `4803d0f97a72b133d2779bb781e0507640d158e7`
- เปลี่ยน default branch เป็น `main` และลบ remote `master` แล้ว ณ วันที่เอกสารนี้
  local/remote เหลือ branch `main`; ประวัติงานเก่าเก็บด้วย archive tags
- ดู mapping ของงานเก่าใน [archives.json](docs/baseline/archives.json)
  อย่า merge archive ทั้งชุดกลับเข้า main โดยไม่ตรวจ เพราะมีงานทดลองและ UI draft
- Remote `fork` เป็น repo ผู้ใช้ ส่วน `origin` เป็น upstream ของผู้พัฒนาเดิม
  ตรวจ URL ก่อน push เสมอ ไม่แก้หรือลบ branch ของ upstream
- การรวม baseline ไม่ได้เปลี่ยนหรือ restart เซิร์ฟเวอร์ที่รันอยู่

## รุ่นแอปและเซิร์ฟเวอร์ที่ส่งมอบ

- Source แอปใน baseline ตรงกับบิลด์ `57c5a83`; เป็น unsigned IPA ต้องเซ็นภายนอก
  ไม่ได้ส่ง TestFlight/App Store ดู build run และ SHA-256 ใน
  [validation.json](docs/baseline/validation.json)
- Server closeout patch `4793697` รวมในทั้งสอง profile แล้ว
- `production` และ `playable` เป็น source คนละชุดตาม runtime ที่ deploy จริง
  ห้ามสลับ map executable กัน เพราะ companion/AI ต่างรุ่น
- Deploy closeout ทั้งสอง backend แล้วเมื่อ 2026-11-25 รวม migration ID ของ
  `mail` และ `guild`; ตรวจ integrity/FK และข้อมูลเดิมครบ 83 ตาราง
- ตรวจเวอร์ชัน/hash/ผล smoke ที่ [deployed-versions.json](docs/baseline/deployed-versions.json)
  อย่าใช้ source snapshot เก่าใน runtime directory เป็นฐาน rebuild โดยไม่ตรวจ provenance

## ฟีเจอร์ที่มีแล้ว

- Companion, Party, HP ใต้เท้าสมาชิกปาร์ตี้, จุดสมาชิกบน minimap และพิกัด X,Y
- Navigation แบบชี้ทางบน minimap/พื้นฉาก ไม่เดินอัตโนมัติ
- Identify, ใส่การ์ด, รถเข็น, Refine, สลับ/เปรียบเทียบอุปกรณ์ และหน้าต่างผลิตของ/Enchant
- Whisper/Party/Guild chat, Friends, Trade, ร้านขาย/รับซื้อ และห้องแชตทั่วไป
- Bank, RODEX, Guild รวม skills/alliance/emblem, Achievement
- Pet/Homunculus/Mercenary controls และ Settings ภาพ/เสียง/shortcut

ยึดข้อมูลและผลตอบรับ server เป็นหลัก โดยเฉพาะเงิน/ไอเทม ห้าม retry ธุรกรรมที่
ไม่ทราบผลแบบอัตโนมัติหรือแสดงสำเร็จก่อน ACK

### ข้อแก้ไขจากบันทึกช่วงพัฒนา

[RO_FOUNDATIONS.md](docs/RO_FOUNDATIONS.md) เป็น ledger ช่วงพัฒนาและยังมี
ข้อความ blocker เก่า ไม่ใช่สถานะ deploy ล่าสุด:

- RODEX: แก้ ID allocation/transaction/refund แล้ว; backend ที่อัปเดตส่ง capability
  ให้แอปเปิด Send ได้ backend เก่ายังคงปิด Send
- สร้าง Guild: แก้ ID และการใช้ Emperium ที่ inventory index 0 แล้ว
- Achievement: แก้ timestamp และการรับรางวัลซ้ำแล้ว
- Guild skills/alliance/emblem: เพิ่ม UI และทดสอบในสนามแยกแล้ว

## ข้อจำกัดและงานที่ยังไม่ทำ

- ไม่ได้ยืนยันภาพ การสัมผัส หรือเสียงบน iPhone จริง อย่าอ้างว่า device acceptance ผ่าน
- ผู้ใช้สั่ง **ไม่ต้อง Simulator** อย่าสร้าง gate รอ Simulator/ภาพ Simulator เพื่อส่งมอบ
- Attendance ไม่มี active event: แสดงตามจริง ไม่สร้าง schedule หรือของรางวัลเอง
- Clan/Reputation/Grade-special UI ยังขาด ไม่ได้อยู่ในรอบ closeout ที่อนุมัติล่าสุด
- Enchant/ผลิตของยังไม่ได้ตรวจทุกสูตร
- Navigation ค้นหา/ข้าม portal ต้องมีตาราง navigation และ GAT ใน asset ที่ตรงกัน
  หากไม่มีตาราง ใช้จุดหมายพิกัดในแมปปัจจุบันตามข้อมูลที่โหลดได้
- HP สมาชิกที่เพิ่งเข้าปาร์ตี้อาจต้องรอ HP packet แรก ห้ามเดาเลือดเต็มเมื่อไม่มีข้อมูล
- Integration tests ไม่ใช่การรับรองว่าระบบ distributed inventory ทนไฟดับ/process kill ทุกจังหวะ

## งาน AI/RL — พักไว้ตามคำสั่งผู้ใช้

ผู้ใช้ยุติงานทดลองลากมอน/RL และเลือกเล่น Assist แล้วเดินฟาร์มเป็นหลัก
ไม่ฝึกต่อ ไม่เอา policy ทดลองขึ้น runtime และไม่เริ่มงานสายนี้ใหม่โดยไม่มีคำสั่ง
Archive เก็บไว้เพื่ออ้างอิง ไม่ใช่ policy ที่ baseline build เลือกใช้
การหยุดทดลองไม่ได้สั่งเปลี่ยนค่าตัวละครหรือ mode ใน runtime โดยอัตโนมัติ

## Build และตรวจสอบ

```sh
git clone --branch main --recurse-submodules https://github.com/tkanjanarux/ragnarok-offline.git
cd ragnarok-offline
python3 scripts/test-ro-foundations.py /tmp/ro-foundations-tests
docker run --rm --network none -v /tmp/ro-foundations-tests:/work:ro -w /work swift:6.2 swift test --scratch-path /tmp/build
python3 -m unittest discover -s scripts/server-closeout -p 'test_migration.py' -v
```

- Baseline ตรวจ portable tests 27 และ migration tests 4 รายการผ่านแล้ว
- [baseline.yml](.github/workflows/baseline.yml) ตรวจ tests และ reconstruct ทั้งสอง profile
- [ro-foundations.yml](.github/workflows/ro-foundations.yml) build unsigned iPhone app
  ด้วย Xcode 27.2 ไม่มี Simulator gate; docs-only changes ไม่ต้องออก IPA ใหม่
- วิธี reconstruct/verify/build Linux server อยู่ใน [server/README.md](server/README.md)
  ใช้ `server/prepare.py` และ `server/build.sh`; ไม่ต้องพึ่ง temporary worktree เดิม
- Profile มี closeout fixes แล้ว **ห้าม apply server-fixes.patch ซ้ำ**
- Source hash ตรงไม่รับประกัน binary hash เหมือนกันเมื่อเปลี่ยน compiler/architecture

## Deploy และข้อมูลสาธารณะ

Baseline build ไม่ได้ deploy อัตโนมัติ การแก้ใหม่ต้องทดสอบก่อนและมี authorization
สำหรับ runtime นั้น ตรวจผู้เล่น สำรอง DB ด้วย SQLite backup API รวม WAL และหยุด
writers ทั้งหมดก่อน migration เก็บ binaries/config พร้อม rollback

หลังเปิดรับธุรกรรมใหม่ **ห้าม restore full DB เก่าทับ** เพราะจะทำข้อมูลผู้เล่นหาย
ใช้ binary rollback ที่เข้ากับ schema และ reconcile ธุรกรรมตามกรณี
ทดสอบเงิน/ของด้วยบัญชีเฉพาะในสนามแยก ไม่ใช้บัญชีผู้เล่นจริง

อย่า commit/push credentials, account/player DB, raw account logs, GRF/game assets,
private backups หรือ build caches ตรวจไฟล์และประวัติ/tags ที่จะเผยแพร่ด้วย
การสแกน secrets เดิมไม่ใช่ใบรับรองว่าไฟล์ใหม่ปลอดภัย คง license/attribution ของ
rAthena และ roBrowser ตามไฟล์ notices เดิม

เอกสารอ้างอิงเพิ่มเติม: [Baseline](docs/baseline/README.md),
[Navigation](docs/NAVIGATION.md), [Party/minimap](docs/PARTY_MINIMAP.md)

## UI original restore — review branch

`ui-original-restore` restores compact Options/Settings, Bank, RODEX,
Achievements and Navigation from actual reference captures. See
[review notes](docs/ui-original-restore/README.md). Built separately from main;
not automatically merged or deployed. PR #1's inventory fixes stay independent;
resolve its duplicate autorun packet case in its own review, not in this UI patch.
Do not infer iPhone visual acceptance from a successful build. No Simulator gate.

## UI navigation polish — follow-up review branch

`ui-navigation-polish` is based on `ui-original-restore` 2447080, as requested by
its iPhone feedback. See [details/tests](docs/ui-navigation-polish/README.md).
Titlebars now draw continuously with disjoint reserved hit regions. Navigation
uses a stable cursor/marker lifecycle and a dedicated textured ground-arrow
renderer; minimized controls use RO skins. Old restore run45644280441 succeeded.
Do not treat queued iPhone builds as a missing-runner failure; inspect the final
job result. No Simulator, automatic merge or gameplay deployment in this work.

## Guild original UI — follow-up review branch

`ui-guild-original` starts from navigation polish 16e8b6a, per explicit user
instruction. See [Guild layout and validation](docs/ui-guild-original/README.md).
Restores compact guild tabs/summary/roster/positions/notice and native GRF control
skins while preserving server callbacks and pending guards. Selection uses live
account/character identity; confirmations cannot cross a guild change. The
position editor remains open for server feedback. No real guild/account mutations,
Simulator, automatic merge or server deployment. No Guild screenshot was supplied;
source/assets are the reference, and physical iPhone visual acceptance is pending.

## Gamepad round 1 — separate review branch

`gamepad-round1` is based on guild original2674eea (build45690894899 success),
including navigation/HP fixes. See [mapping and limitations](docs/gamepad-round1/README.md).
Native extendedGamepad sampling, short walk requests, camera orbit, stable visible
monster lock, edge-only single attacks/shortcuts, and profile-ID Follow/Assist/Stop.
Modal/text/lifecycle/touch ownership require neutral before resuming. Movement
release is not an instant server stop; ground skills and transaction dialogs use
touch. No remapping/full inventory navigation, Simulator, hardware acceptance,
PR merge or server deployment. IPA is unsigned for external signing.

## Gamepad controls follow-up

`gamepad-round1-controls` starts at be00178, preserving guild2674eea/navigation/HP.
Primary uses touch approach/repeat; owned attack generation plus real cancellation
packets prevents stale local arrivals. Eight trigger chords use row1 slots1–8.
D-pad has team scope with acknowledged serialized existing commands, including
nearby Hunt. See updated gamepad notes for partial-batch and protocol limitations.
No server changes, accounts, Simulator, hardware acceptance, merge or deployment.

## Directional controller targeting

`gamepad-directional-target` starts from adb177d. See
[selection constants, indicators and acceptance](docs/gamepad-directional-target/README.md).
Keep explicit selection, soft preview and action lease separate. Preview must
never call selectTarget or send combat packets. Offensive acquisition uses real
skill flags; support/ground/item paths cannot inherit a monster preview. Held-stick
consumption allows a directional press without cancelling itself; reset clears it.
No Simulator/device claims, server changes, automatic PR merge or deployment.

## Controller range and dedicated pickup

`gamepad-range-loot` starts at ce304a2. [Policy/tests](docs/gamepad-range-loot/README.md):
acquisition covers the server attack-range square plus prior melee approach circles;
skill cast ranges remain independent. Optional right-stick click picks up one nearby
item while keeping explicit lock, cancelling an older attack/arrival. No remote loot,
optimistic success or held-button repeat. Preserve existing mapping/lifecycle guards.
No Simulator/hardware claims, player data, server changes, merge or deployment.

## X pickup follow-up

`gamepad-x-loot` starts at a711731. [Current mapping/tests](docs/gamepad-x-loot/README.md):
X alone now picks up using the same pipeline as optional R3. Y stays slot2; LT+A
retains slot1 and all eight trigger chords/RT precedence stay unchanged. Releasing
triggers while holding X cannot replay pickup; X+R3 emits one command. X does not
suppress camera orbit. Range/lock/cancellation/team guards stay as in the prior base.
No Simulator/hardware claims, server changes, automatic merge or deployment.

## Cash Shop full catalogue — delivery candidate, live activation pending

`cash-shop-full-catalogue` starts at92eea05, preserving purchase recovery5e0d45a,
Guild/navigation/HP/controller changes. App sourceb79d14e; closeout commits only
change docs/audit metadata. [Delivery evidence](docs/cash-shop-full-catalogue/README.md),
[88-row ledger](docs/cash-shop-full-catalogue/COVERAGE.md) and
[server plan](docs/cash-shop-full-catalogue/SERVER-DELIVERY.md) are authoritative.

85 requirements have implementation and enumerated isolated verification;11/12
explicitly use native medium Increase Potions instead of literal food.88 companion
fashion is excluded because native gear validation rejects costume/shadow slots.
123 new listed SKUs +34 preserved =157. Six duplicate stat-food definitions stay
usable but unlisted; no duplicate food offers. Arrow materials945 Cash; companion
Hunter162/Priest297, repurchased. No promise of exhaustive per-SKU boundary testing.

Both distinct native source profiles reproduce and Map+Char compile for x86_64,
PACKETVER20211103. The playable map differs from production; never replace it with
production Map. Matching journal-capable Char/Map and additive SQLite pet journal
are mandatory. Successful native capture now uses the save barrier/journal after a
reproduced orphan-egg race; native RNG is unchanged.15 native SQLite cases per
profile;3 packet capture recovery cases;3 pet packs and6 taming species rerun after
fix. Socketless Giant Fly Wing actor placement fixed without combat-policy changes.

All five native card outcomes observed in26 fixture purchases; identity/materials/
money and per-outcome reconnect checked. Final catalogue packet count/prices/alias
rejection pass. Source/assets audit is distinct from actual packet effects and from
hardware acceptance. Physical iPhone/controller/preview remains unverified; no
Simulator gate. Latest build/artifact status and hash belong in the delivery report.

No live deployment, service restart, player write, PR merge, RL redesign or currency
grant is authorized by this implementation task. Only owned isolated fixtures were
mutated. Static unsigned IPA publication is allowed. Read the deployment plan before
any later activation: fresh online/process/DB/writer identity and SQLite backups,
no old-DB restore after new writes, never downgrade/drop a nonempty pet journal.

Final catalogue appb79d14e passed Xcode27.2 run45963176587 and all four portable
workflow jobs. Unsigned IPA published and HTTPS downloaded/hash-verified; see
[delivery](docs/cash-shop-full-catalogue/DELIVERY.md) and artifact manifest. All
later changes are docs/audit-only and app-source diff is empty. Live catalogue
remains unchanged. Fixture closeout integrity/FK pass, no pending pet journal.
