# Cash Shop catalogue — ส่งมอบชุด review

Branch: `cash-shop-full-catalogue` บน fork `tkanjanarux/ragnarok-offline`.
ฐาน92eea05 รวม purchase recovery5e0d45a และ Guild/navigation/HP/gamepad ล่าสุด.
App source: `b79d14ea9284753034e14f71e3123e667b03f44f`; server/evidence closeout59d6283.
Commit เอกสารหลังจากนั้นไม่เปลี่ยน source/resources/project/dependency ของ IPA.

[ดาวน์โหลด IPA](https://76-13-19-77.sslip.io/downloads/RagOff-b79d14e.ipa) · [Xcode27.2 build](https://github.com/tkanjanarux/ragnarok-offline/actions/runs/45963176587) ·
[artifact/source/hash manifest](client-artifact-manifest.json)

IPA 65,364,272 bytes, ARM64, unsigned ต้องเซ็นภายนอกก่อนติดตั้ง.
ตรวจ official artifact digest, ZIP CRC, SDK iphoneos27.2, ไม่มี embedded signing
profile/signature, metadata catalogue ภายในตรง source และดาวน์โหลด HTTPS กลับมา
ได้200พร้อม SHA-256 ตรงกัน:

```
3f051943d93d21de6ce5db1efd4937b7080a7ae1d1ca88237ddeb1be37c15921
```

## ขอบเขตทั้ง88ข้อ

| สถานะ | จำนวน | รายละเอียด |
|---|---:|---|
| มี implementation และหลักฐานทดสอบสนามแยก |85| ดูรายการ/evidence รายข้อ ไม่ใช่คำรับรองทุกเงื่อนไขหรือ device |
| ปรับชนิดของอย่างเปิดเผย |2| ข้อ11/12 ใช้ medium HP/SP Increase Potions จริง แทนอาหาร |
| ไม่ขาย/ยังไม่รองรับ |1| ข้อ88 companion costume: server ปฏิเสธ costume/shadow slots |

เพิ่ม123 SKU:77แพ็ก +13บริการ/ไข่สัตว์เลี้ยง +25costumes +8utility/accessories.
คง34รายการเดิม รวม157. อาหาร stat ซ้ำ6definitionยังใช้ได้แต่ไม่ลงร้านซ้ำ.
ข้อ33/75/76ใช้SKUร่วมอย่างชัดเจน ราคา/จำนวน/ID/AegisNameครบใน
[ตาราง88ข้อ](COVERAGE.md) และ [ledger](coverage.json).

## ผลตรวจ

- Xcode27.2 full iPhone build **success**; Actions cashshop, navigation, guild,
  gamepad checks **success** ทั้ง4job. ไม่รันหรือรอ Simulator.
- ครอบคลุม ID ของ123 SKUใหม่กับหลักฐาน transaction;83definitionแพ็กซื้อ/หักCash
  ครั้งเดียว/cancel/เปิด/จำนวนตรง/reconnect (6เป็นaliasที่ถอดจากร้านภายหลัง).
- มีผลจริง HP/SP/stat/element/EXP/death protection/native drop-rate calculation,
  reset/rename/style/repair/Gym, costume equip, pet hatch/feed/tame/accessory,
  companion supplies/arrow/gem consumption และ party actor warp ตามขอบเขตที่ระบุ.
- การ์ด26ครั้งพบครบ5outcomeเดิม; native policy200กรณี. Pet journal15 native SQL
  casesต่อprofile, packet recovery3กรณี, pet packs3และtaming6ชนิดผ่านซ้ำหลังfix.
- Assembly/alias9tests; finalcatalogue packet157รายการสาธารณะพร้อมราคา/ปฏิเสธalias
  โดยไม่หักเงิน. Fixtureมีprobeส่วนตัวอีก1ซึ่งไม่อยู่ในimportsสาธารณะ.
- Source reproduce และ Map/Char compileผ่านทั้งproduction/playableแบบx86_64;
  Mapต่างกันตามprofile. การทดสอบintegrationใช้playablecandidateในสนามแยก.
- ปิดท้ายฐานfixture integrity=ok, FK violations=0, journalค้าง0;
  syntheticcharacters2ตัว markedoffline. ไม่ได้ตรวจผู้เล่นจริงผ่านDBนี้.

หลักฐานแยก source/asset audit, packet/effect integration และ device acceptance
ใน [README](README.md). ไม่อ้าง exhaustiveทุกjob/mapflag/จังหวะdisconnectหรือทุก
buff boundary. ยังไม่มีiPhone/controllerจริงตรวจpreview,สัมผัสหรือperformance.

## วิธีลองและขั้นฝั่งserver

**ร้านจริงยังไม่ได้อัปเดต**: ติดตั้งIPAอย่างเดียวจะไม่ทำให้157รายการขึ้นร้านเดิม.
ต้อง deploy matching Map/Char + pet journal migration + mergedimports หลังreview
ตาม [SERVER-DELIVERY](SERVER-DELIVERY.md), พร้อมตรวจผู้เล่นและสำรองDBใหม่ก่อนactivation.
ไม่มีdeploy/restartproduction/playable, playerDB mutation, PRmerge หรือTestFlight.

หลังเปิดservercatalogue: เข้าCashShop เลือกvariantและดูจำนวน/ราคาก่อนซื้อ;
costumeมีpreviewฟรี; แพ็กใช้จากกระเป๋าแล้วconfirm โดยcancelไม่เสียแพ็ก.
อ่านข้อจำกัดบริการก่อนยืนยัน โดยเฉพาะcard removalมีความเสี่ยงเดิม ไม่การันตี.
Petใช้Incubator/อาหารตรงชนิด. แพ็กcompanionให้ของเข้ากระเป๋าเจ้าของก่อน:
Reserveตัวที่ต้องการแล้วGive Suppliesครั้งละ1–100 ไม่มีแจกอัตโนมัติ/AIใหม่.

เก็บGRF/art/credentials/playerDB/rawlogs/privatefixtures/buildbinariesนอกpublicGit.
สแกนdiffก่อนpushแล้ว ไม่mergePRหรือเปลี่ยนmainอัตโนมัติ.
