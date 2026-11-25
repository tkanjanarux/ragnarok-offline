# ตรวจวงจร RO พื้นฐาน — 2026-11-25

เริ่มจาก `main` ที่ `bff04840064102a1681e36fcd891fa588ab62024` และ submodule
`eec09e4fdba188acb82d76efff2bea433e438a3d` ใช้ login/char/map ที่ build จาก
profile ใน repo เปิดเฉพาะ loopback และสร้าง SQLite บัญชี ตัวละคร เงิน และของใหม่
จาก schema/fixture ในแต่ละรอบ ปิด companion เฉพาะสนามทดสอบเพื่อไม่ให้แทรกวงจร
ไม่มีการต่อฐานข้อมูลผู้เล่นหรือ deploy/restart ระบบจริง

## ผลที่รันแล้ว

| การตรวจ | ผล | หลักฐาน |
| --- | --- | --- |
| Native packet integration โปรไฟล์ production | ผ่าน, Poring 3 ตัวก่อนพบ Jellopy | [production.jsonl](production.jsonl) |
| Native packet integration โปรไฟล์ playable | ผ่าน, Poring 4 ตัวก่อนพบ Jellopy | [playable.jsonl](playable.jsonl) |
| Portable Swift regressions | ผ่าน 32 รายการ | [BasicInventoryTests.swift](../../Packages/RagnarokGame/Tests/RagnarokGameTests/BasicInventoryTests.swift) |
| SQLite migration / ตรวจ manifest ต้นทาง | ผ่าน 4 tests / 3,228 และ 3,230 ไฟล์ | [baseline workflow](../../.github/workflows/baseline.yml) |
| Build iPhone แบบ unsigned | ใช้ workflow เดิมบน PR, ดูผลใน Checks | [iPhone workflow](../../.github/workflows/ro-foundations.yml) |
| Device acceptance | ยังไม่ได้ทดสอบบนเครื่องจริง | รายการด้านล่าง |

ทั้งสองโปรไฟล์ได้ยอดตรงกัน ก่อน/หลังอยู่ในแถวติดกันด้านล่างและมีรายการของทุกชิ้นใน JSONL
หลังออกปกติยอดที่โหลดใหม่ตรงกับสถานะก่อนออกและ SQLite เมื่อส่งฝาก 1 ชิ้นแล้วปิด
TCP ก่อนอ่านผล ทั้งสองรอบพบว่าฝากสำเร็จครั้งเดียว (กระเป๋า 3 → 2, คลัง 1 → 2)
ไม่มีการส่งคำขอเดิมหลัง reconnect และถ้าเซิร์ฟเวอร์ยังไม่ได้รับคำขอก่อนหลุด
harness ยอมรับยอดเดิมได้ ตราบใดที่เงินและของทุกชิ้นยังตรงกัน

| หลังขั้นตอน | Zeny | น้ำหนัก | ช่องกระเป๋าที่ใช้ | ช่องคลัง | Jellopy กระเป๋า/คลัง |
| --- | ---: | ---: | ---: | --- | --- |
| initial | 10,000 | 4,100 | 12 | — | 4/0 |
| kill | 10,000 | 4,100 | 12 | — | 4/0 |
| pickup | 10,000 | 4,110 | 12 | — | 5/0 |
| pickup duplicate rejected | 10,000 | 4,110 | 12 | — | 5/0 |
| sale | 10,003 | 4,100 | 12 | — | 4/0 |
| sale duplicate rejected | 10,003 | 4,100 | 12 | — | 4/0 |
| deposit | 10,003 | 4,080 | 12 | 1/600 | 2/2 |
| withdraw | 10,003 | 4,090 | 12 | 1/600 | 3/1 |
| no eligible equipment for card | 10,003 | 4,090 | 12 | 1/600 | 3/1 |
| identify cancel | 10,003 | 4,040 | 12 | 1/600 | 3/1 |
| identify success | 10,003 | 3,990 | 12 | 1/600 | 3/1 |
| identify duplicate ignored | 10,003 | 3,990 | 12 | 1/600 | 3/1 |
| identify no eligible item (raw client) | 10,003 | 3,940 | 11 | 1/600 | 3/1 |
| card cancel | 10,003 | 3,940 | 11 | 1/600 | 3/1 |
| card success | 10,003 | 3,930 | 10 | 1/600 | 3/1 |
| card duplicate ignored | 10,003 | 3,930 | 10 | 1/600 | 3/1 |
| refine cancel | 10,003 | 3,930 | 10 | 1/600 | 3/1 |
| refine missing offered material | 10,003 | 3,930 | 10 | 1/600 | 3/1 |
| refine success | 9,953 | 3,730 | 10 | 1/600 | 3/1 |
| refine failure consumes fee, ore and knife | 9,903 | 3,130 | 9 | 1/600 | 3/1 |
| deposit refined equipment | 9,903 | 2,730 | 8 | 2/600 | 3/1 |
| withdraw refined equipment | 9,903 | 3,130 | 9 | 1/600 | 3/1 |
| equip | 9,903 | 3,130 | 9 | 1/600 | 3/1 |
| normal logout | 9,903 | 3,130 | 9 | 1/600 | 3/1 |
| reconnect | 9,903 | 3,130 | 9 | 1/600 | 3/1 |
| reconnect after disconnect before reading deposit result | 9,903 | 3,120 | 9 | 1/600 | 2/2 |

`PRAGMA integrity_check` ผ่านในแต่ละ reconnect ทั้งสองโปรไฟล์มีคำเตือนเดิม
จากคำสั่ง `NOW()` ที่ใช้เขียน `charlog` บน SQLite ผลทดสอบไม่ได้รับรอง logging
ตารางนั้นและไม่ได้แก้เรื่องนี้ใน PR

## Root causes ที่แก้ฝั่งแอป

- Magnifier ได้ `ZC_AUTORUN_SKILL (0147)` จากเซิร์ฟเวอร์ แต่ `PlaySession`
  ไม่ตอบด้วยคำขอร่าย Identify จึงไม่เกิดหน้าต่างเลือกไอเทม ตอนนี้ใช้สิทธิ์ร่าย
  ครั้งเดียวจากคำขอ Magnifier ที่ผู้เล่นเริ่มเอง และรอรายการจากเซิร์ฟเวอร์
  ถ้ารู้อยู่แล้วว่าไม่มีอุปกรณ์ที่ยังไม่ระบุ แอปไม่ส่งคำขอที่อาจเสีย Magnifier เปล่า
- `ZC_USE_ITEM_ACK (01c8)` ส่งผลสำเร็จให้คนใกล้เคียงด้วย และส่งจำนวน 0
  เมื่อปฏิเสธคำขอ โค้ดเดิมใช้ slot ของคนอื่นหรือของคำขอล้มเหลวไปอัปเดตกระเป๋าตัวเอง
  และเก็บรายการที่หมดค้างไว้ ตอนนี้เช็กเจ้าของ ผลสำเร็จ และ item ID ก่อนอัปเดต
  และลบ slot เมื่อจำนวนเหลือ 0 จริง
- คลังรับ `ZC_ADD_ITEM_TO_STORE (0b44)` แต่ reducer เดิมไม่เก็บ identified,
  damaged, refine, grade และ random options จึงแสดงรายละเอียดผิดหลังฝากทันที
  ทั้งที่ reopen/reconnect อ่านค่าได้ครบ
- ขายและย้ายของใช้ปุ่มที่ส่งคำขอซ้ำได้ก่อนผลตอบกลับ โดยเฉพาะย้ายของหนึ่งชิ้นจาก
  กองที่ยังเหลือจะทำงานซ้ำในเซิร์ฟเวอร์ได้ ตอนนี้รับเพียงหนึ่งคำขอระหว่างรอผล
  ขายปลดล็อกด้วยผลขาย คลังด้วย source delta/zero-amount reject ที่ตรงกัน
  หากเซิร์ฟเวอร์ไม่ตอบ ปิดคลังแล้วรอ close ACK หรือ reconnect เพื่ออ่านสถานะใหม่
  ไม่มี timer ส่งธุรกรรมเดิมใหม่ ซื้อใช้ lock เดียวกันเพื่อไม่ให้ ACK ปนกับการตีบวก

## วิธีรันและขอบเขต

```sh
git submodule update --init --recursive
for profile in production playable; do
  python3 server/prepare.py "$profile" --output "build/server-$profile" --with-runtime-templates
  server/build.sh "$profile"
  python3 scripts/test-basic-ro-loop.py "$profile"
done
python3 scripts/test-ro-foundations.py /tmp/ro-loop-portable
docker run --rm --network none -v /tmp/ro-loop-portable:/work:ro -w /work swift:6.2 swift test --scratch-path /tmp/build
```

ถ้าเตรียม profile แล้ว ให้ใช้ `server/prepare.py … --verify` แทนการสร้างซ้ำ
ผล ledger ใช้ packet จริงจาก native server ไม่ใช่ SwiftUI หรือ Network.framework
แถวไอเทมใน JSONL เป็น `[id, amount, identified, refine, first_card, wear_state]`
น้ำหนักเป็นหน่วย wire (10 = 1 หน่วยในเกม) และคลังเป็น `[used, capacity]`
ค่า wear state ของการ์ดไม่ใช่สถานะสวมใส่ ผู้เล่นยังไม่ได้ใส่การ์ดในตอนนั้น

## เส้นทาง UI → packet ที่ตรวจจาก source และเทียบกับสนาม

| การเล่น | เส้นทางในแอป | Packet ที่ใช้ตรวจ |
| --- | --- | --- |
| โจมตี / เก็บ | Map scene → action / pickup → inventory | `0437`, `0add`, `0362 → 0b41` |
| ขาย | NPCShopView → Sell → inventory/zeny และผลขาย | `00c9 → 07fa / 00b1 / 00cb` |
| คลัง | StorageView → ฝาก/ถอน/ปิด → Storage + Inventory | `0364 / 0365`, `0b44 / 00f6`, `0193 → 00f8` |
| Identify | Inventory → Magnifier → ItemSelectionView | `0439 → 0147 → 0438 → 0177 → 0178 / 0179` |
| ใส่การ์ด | Inventory card → ItemSelectionView → ยืนยัน | `017a / 017b → 017c / 017d` |
| ตีบวก | NPC เปิด RefineView → เลือกอุปกรณ์/แร่ | `0aa0–0aa4`, `0188`, เงิน/ลบของแยก packet |
| เข้าใหม่ | Character select → โหลดเงิน / Inventory → เปิดคลัง | `006b`, `0b08 / 0b09 / 0b39 / 0b0b`, `00f2` |

การเปิดหน้าต่าง Identify ใช้ Magnifier ไปแล้วตามกติกาเซิร์ฟเวอร์ แม้กดยกเลิกใน picker
การยกเลิกใส่การ์ดเป็นฝั่ง client จึงไม่มี composition request ส่วนแร่ไม่พอและไม่มีเป้าหมาย
ที่ใช้ได้บางกรณีเป็น silent rejection ไม่ใช่ failure ACK การตีบวกที่แตกใช้เงินและแร่ตามกติกาเดิม

## ลองต่อบน iPhone จริง

ใช้ IPA ที่เซ็นแล้วและบัญชีสนามทดสอบเท่านั้น

1. ตี Poring แล้วแตะเก็บ Jellopy สองครั้ง ขายหนึ่งชิ้น ตรวจว่าขึ้นเงินและของลดหลังผล
   ฝากและถอนแบบกดเร็ว ลองปิด/เปิดคลัง ยอดช่องและรูปอุปกรณ์ต้องตรงกัน
2. ใช้ Magnifier กับของไม่ระบุ กดยกเลิกก่อนเลือก แล้วใช้ใหม่เพื่อระบุ ตรวจว่าเปิด picker
   ครั้งเดียว และไม่มีการใช้ Magnifier เมื่อไม่มีของให้ระบุ
3. เปิดการ์ดโดยมีเพียงอุปกรณ์ผิดประเภท/สวมอยู่ แล้วลองกับอุปกรณ์ถูกประเภทที่ถอดแล้ว
   กดยกเลิกก่อนยืนยัน จากนั้นใส่จริง ตรวจว่าการ์ดลดและช่องเปลี่ยนหลัง ACK
4. เปิดหน้าตีบวก ตรวจปุ่มเมื่อแร่ไม่พอ ยกเลิกก่อนยืนยัน แล้วลองของ +0 และของเสี่ยงแตก
   ตรวจค่าธรรมเนียม แร่ และผลทั้งสำเร็จ/ล้มเหลว ฝากอุปกรณ์ +1 แล้วตรวจรายละเอียดทันที
5. ตัด Wi-Fi หลังยืนยันขาย/ฝาก/ใส่การ์ด/ตีบวกทีละรายการ เข้าใหม่แล้วอ่านยอดก่อนทำต่อ
   แอปต้องไม่ส่งคำขอที่ไม่ทราบผลซ้ำเอง ตรวจเงิน น้ำหนัก ช่องคลัง และการสวมใส่หลัง reconnect

ไม่ได้ใช้ Simulator และยังไม่มีการยืนยันภาพ การสัมผัส หรือการสลับเครือข่ายบน iPhone
การ build `iphoneos` ไม่ใช่การผ่าน device acceptance ขอบเขตการตัดเน็ตของ harness
คือปิด TCP ฝั่ง client ขณะรอผลฝากของ ไม่ได้ครอบคลุม process kill, ฐานข้อมูลล่ม,
จังหวะหลุดของทุกธุรกรรม หรือ storage/upgrade ทุกแบบ
