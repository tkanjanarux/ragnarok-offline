# Cash Shop full catalogue: delivery candidate

Branch `cash-shop-full-catalogue` starts at `92eea05a557f6c9c84e166cf7c73031d09fdddaf`,
including purchase recovery `5e0d45a`, Guild, navigation, party HP and the latest
controller/X-pickup changes. App source is `b79d14ea9284753034e14f71e3123e667b03f44f`;
later closeout changes affect documentation/catalogue audit metadata only.

**85 requirements have implementation and enumerated isolated verification;
2 are explicit functional adaptations; 1 is excluded.** This is not a claim of
exhaustive per-item boundary testing or iPhone visual acceptance. **Live shop is
unchanged and deployment is pending.** See [all 88 rows](COVERAGE.md),
[exact quantities/variants/prices/evidence](coverage.json),
[summary](readiness-summary.json) and [server delivery plan](SERVER-DELIVERY.md).

## What is delivered

| Category | New listed SKUs | Result |
|---|---:|---|
| Fixed supply packs | 77 | Buy once, confirm contents, atomic exchange; choose variant before buying |
| Services and pet starter vouchers | 13 | Native guarded flows, server-authoritative result |
| Stat-free costumes | 25 | Existing concrete items, local assets, free native renderer preview |
| Utilities and pet accessories | 8 | Existing effects, species/eligibility rules |
| Total added | **123** | Plus **34 preserved =157** shop entries |

There are 96 custom definitions: 83 supply definitions and 13 vouchers. Six
request33 food definitions remain usable compatibility aliases but are not listed;
request33 selects the same six packs as27–32. Cities76 reuse Crown19630, FoxMask19618
and Turban19844; priest-themed pet75 reuses Poring71. No duplicate themed offers,
random loot boxes, fake previews or Cash grants were added.

Requests11/12 explicitly contain **12423/12426 medium HP/SP Increase Potions**,
10 per pack,135 Cash. They provide the requested capacity effect, **not literal
food**. Request88 companion fashion is **excluded**: native companion gear validation
rejects costume/shadow slots. No stat-bearing substitute is sold.

Prices use the existing local virtual-Cash scale. Bundles receive10% off the
consistent component values, rounded to whole Cash. Arrow Crafting pack22 is945;
Hunter/Priest companion packs are162/297. These revised prices were repurchased
and checked. [Pricing audit](pricing-evidence.json) includes native resale values
and arrow-conversion outputs; it is not a global external-economy arbitrage proof.
No Zeny-to-Cash conversion was introduced. Existing34 entries/prices are preserved.

## How to use after server activation

Open the existing Cash Shop. Search/filter the received catalogue, select the
named variant and inspect its quantities and price before checkout. The existing
purchase-recovery flow remains: an unknown transaction is **not automatically
retried**. Inventory and balance reconcile from server data.

- Supply packs go to inventory. Use a pack, review fixed contents, then confirm.
  Cancel preserves it; invalid capacity/weight/stack state rejects the whole exchange.
  Selection occurs **before purchase**, so there is no undisclosed random outcome.
- Costume details offer free try-on through the actual composed-sprite renderer,
  with four directions and no purchase/equip packet. Other headgear/garments/weapons
  are hidden for an unambiguous try-on. Missing required assets fail closed. This
  implementation was compiled and assets decoded; physical iPhone preview is unverified.
- Reset vouchers require a valid, alive, unencumbered town character, no conflicting
  mount/cart/falcon/cast state. They refund actual spent points and retain permanent,
  quest/basic and unspent bonuses. Gym grants the existing permanent training skill,
  capped at10. Repair only affects eligible broken equipment.
- Rename activates one credit. Return to character selection to enter a name;
  native uniqueness/name restrictions apply. Current server policy rejects rename
  while in a party/guild. Reconnect/timeout does not silently spend another credit.
- Style vouchers use valid classic/rebirth ranges: hair1–42, hair colour0–8,
  clothes colour0–3, additionally clamped by server configuration. Unsupported
  job/range or cancellation preserves the voucher.
- Card removal shows native Wise Old Woman costs and risks before confirmation:
  voucher +200,000 Zeny +25,000 per card +1,000 Star Crumbs +1 Yellow Gemstone.
  Native90% success,2% both lost,6% unprotected side lost,2% unchanged (fees still
  spent) are retained. It is **not guaranteed removal**. Rental/special/unsafe
  equipment is rejected; eligible retained equipment keeps identity/refinement.
- Pet packs give a real Poring/Spore/Lunatic egg and50 correct foods atomically.
  Buy Incubator643 separately if needed. Hatch/feed/name/accessory/return-to-egg
  use existing Pet UI. Taming kits select a real species before buying; native
  random success and lure-on-attempt rules remain, including targeting cancellation.
- Companion packs put supplies in the owner's inventory. Reserve the intended
  companion and use **Give Supplies**,1–100 per transfer. Five roles use four real
  careers: Knight Puller, Knight Spear, Hunter, Wizard, Priest. There is no automatic
  distribution, Assassin companion or new AI policy. Paid arrows/gems and HP/SP
  supplies are consumed by the existing systems; Stop retains its existing meaning.

## What was verified

Tests ran only on loopback isolated services with a schema-only database and two
synthetic accounts. Raw fixtures/logs/databases and credentials remain private.
Individual evidence files retain the binary/profile and scope where applicable;
historical transaction tests are not falsely relabelled as reruns on the final binary.

| Area | Evidence and actual observations |
|---|---|
| Cash/pack transactions | [67 original](bundle-packet-evidence.json) +[16 added](additional-bundle-packet-evidence.json) definitions: purchase, debit once, cancel, exact contents, reconnect. Six aliases are now unlisted. [Shared edges](bundle-edges-evidence.json): weight, full slots, stack/menu/disconnect/duplicate handling. Duplicate-line loss was reproduced and fixed before payment. |
| Final catalogue | [Actual packets](final-catalogue-evidence.json):157 public entries, correct lengths/prices, canonical foods listed, aliases rejected without charge. Fixture-only extra probe is excluded from public imports. Nine assembler/alias tests. |
| Consumables | [HP/SP/stats](consumable-effects-evidence.json), [cures/status/speed expiry](status-items-evidence.json), [buffs](buff-effects-evidence.json), [eligibility](eligibility-evidence.json): level59/60 Syrups and Merchant/Hunter arrows. EXP actual1000→1500; Insurance actual death loss prevention; Bubble Gum native computed drop-rate change, **not sampled drop frequency**. |
| Elements | [Resistance](resist-combat-evidence.json): incoming native elemental damage decreases. [Eight arrows/four converters](outgoing-elements-evidence.json): actual ammo consumption, casts and damage comparisons. Random criticals retained; no exact DPS/multiplier claim. |
| Services | [Six services](services-evidence.json), [limits](service-limits-evidence.json), [Gym](gym-weight-evidence.json), [rename](rename-evidence.json), [styles](styles-evidence.json). Gym capacity4200→4400 units and reconnect. Reset cancellation/invalid state keeps voucher. |
| Cards | [Guards](card-removal-evidence.json) plus [26 actual purchases](card-outcomes-evidence.json) observed all five native random outcomes; money/materials/identity checked and each outcome reconnect-tested.200 compiled probability-boundary cases; no RNG override. |
| Costumes/assets | [25 costumes](costumes-evidence.json) purchase/equip/persist/reconnect with MaxHP/SP and all six stats unchanged; script/stat/combo audit. [87 native items](native-item-audit.json),174 icon/collection BMPs decoded; [96 custom definitions](custom-icons-evidence.json) resolve10 real BMPs. Sprite/ACT/palette hashes in per-row ledger; no art committed. |
| Pets | [Final three packs](pet-packs-final-evidence.json), [six edges](pet-edges-evidence.json), [six species](pet-species-evidence.json), [final six taming species](taming-final-evidence.json). Hatch/feed/accessory/name/persistence and native Loyal bonuses. Owned Loyal fixtures are explicitly distinct from native capture tests. |
| Capture recovery | [Reproduced orphan defect](capture-defect-evidence.json), then [three actual packet cases](capture-recovery-evidence.json): disconnect after success, duplicate target and disconnect before save barrier.15 native SQLite tests per profile cover real adapter commit/replay/reconciliation/rollback. Native capture RNG unchanged. |
| Utilities/party | [Token/identify/Arrow Crafting](utilities-evidence.json), [normal wings](wings-evidence.json), [Giant Wing party actor placement](giant-wing-evidence.json) and [Stopped companion](giant-wing-stopped-evidence.json). Actual leader, second fixture member and companion actor warp, not just party-coordinate packets. |
| Companions | [Five packs](companion-supplies-evidence.json), [combat/guards](companion-combat-evidence.json): HP/SP use, paid Silver Arrow attacks, Priest Blue Gemstone revival, active-transfer/wrong-owner rejection. [Revised prices](reprice-companion-evidence.json) retested. |
| Builds | Both distinct source profiles reproduce and x86_64 Map+Char compile. [Production](production-build-manifest.json) / [playable](playable-build-manifest.json). Portable cash tests13 Swift Testing+3 XCTest locally; Actions also checks navigation/Guild/gamepad. Full iPhone Xcode27.2 build and all four Actions check jobs passed; [verified IPA delivery](DELIVERY.md). |

Not every combination of job, level, map flag, inventory composition, buff duration,
pet intimacy and disconnect timing was exhaustively tested. Giant Wing nonleader
fallback/map restrictions retain native logic but are not all packet-tested.
Costume/pet preview, touch checkout performance and controller coexistence have
source/compile/regression evidence, **not physical-device visual/hardware acceptance**.
No Simulator was run or used as a delivery gate.

## Server fixes and activation boundary

[SERVER-DELIVERY.md](SERVER-DELIVERY.md) contains reproduction, migration, backup,
matching-binary and rollback requirements. The candidate fixes duplicate cash-line
preflight, waiting item-dialog lifetime, guarded native services, atomic pet delivery
and native capture journal, plus socketless party warp placement. Matching Map/Char
and the additive journal schema must be activated together. Production/playable
remain distinct source profiles; the production map must not replace playable AI.

**No live deployment, service restart, player mutation, PR merge or RL redesign
occurred.** Only the owned isolated test instance was restarted. Publication of the
unsigned IPA to the existing static downloads folder does not activate the catalogue.

## Reproduction and attribution

Initialize the pinned submodule, install Python3/PyYAML and a native C++ toolchain.
See server delivery instructions for prepare/assemble/compile. Checks:

```
python3 scripts/cash-shop/verify-ledger.py
python3 scripts/cash-shop/test-assembly.py
python3 scripts/cash-shop/audit-prices.py
python3 scripts/cash-shop/test-card-policy.py
python3 scripts/cash-shop/test-pet-journal.py /path/to/prepared-source
```

rAthena changes retain its GPL license. roBrowserLegacy GPL3 reference commit
`2f9a9d6cf5b04a8ac7a44077080772046e15bcb7` informed layout/resource auditing and
PetAction ACT path resolution (see attribution file). No web wrapper/dependency
or extracted GRF art was added. GRF, palettes, credentials, player databases,
raw logs, build binaries and private fixture source are excluded from public Git.
