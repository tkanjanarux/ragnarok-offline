# Cash Shop equipment — verification in progress

Base `29f074d51221cbbe6ce1d393ebf2362041a09fd6` preserves the complete prior
[88-requirement delivery](../cash-shop-full-catalogue/DELIVERY.md), including all
controller/navigation/Guild/HP and purchase-recovery fixes. This branch adds the
19 exact requested native equipment IDs, direct +0 purchases; no cards or custom
anti-flinch. No live activation/production restart is authorized here.

Both immutable prepared profiles and read-only live renewal/import data match the
[native definitions](native-items.json). None of the19 are in the deployed34 or
the prior157-entry candidate. The assembled review catalogue has176 entries,
preserving all prior prices and all96 custom definitions unchanged. Prices in
[`candidate-equipment.json`](../../server/cash-shop/candidate-equipment.json) use
existing virtual Cash:150 entry accessory,200–500 utility/stat gear,600–900 advanced
or conditional-effect gear. No real-money prices, random options, refine roll,
rental/event ID substitution, class relaxation or currency grants to players.

Each item's authored description states native bonuses, drawbacks, slots, weight,
level/job/class and refine interactions. Variant loses1 percentage point HP/SP per
refine; Orleans protects casting under native map rules, not movement flinch;
Valkyrian Manteau selects a base-job-family effect. Rideword is probabilistic weapon
damage drain, with HP loss; not automatic restoration for support/idle characters.
Morpheus's Hood is not in this requested list: the three offered pieces alone do
not complete its four-piece set. Other omitted combo partners are not silently
included. No additional items were added to make a set look complete.

The native job/class predicates are executed by
[`export-equipment-eligibility.py`](../../scripts/cash-shop/export-equipment-eligibility.py),
producing [exact allowed job IDs](eligibility-evidence.json). The shop displays
owner job/level eligibility from this data; unknown or changed job identity falls
back to an explicit unavailable state until reconnect. It does not block gifts or
bypass server equip ACK/temporary restrictions. Companion compatibility is not
claimed from owner rules: native companion gear validation is separate.

[Asset audit](asset-evidence.json): all19 item/collection BMPs decoded; both-sex
SPR/ACT signatures/lengths located for the four headgear views. No GRF art is added
to public Git. Native format decoding and runtime equipment/effect/edge evidence
are still being collected; source/asset presence alone is not sale-readiness proof.

Integration is confined to the owned loopback synthetic fixture. A private,
read-only `@stats` probe exposes the actual calculated native runtime fields; it
does not change scripts, RNG, bonuses or combat policy and is **not** a deployment
binary. Equipment tests use group0 without `use_all_equipment` permission; only
fixture budget/probe commands are enabled. Real combat checks are separate from
computed-field evidence. Raw fixture source/data/logs stay private.

No Simulator or physical iPhone/controller verification. A full Xcode27.2 iPhone
build will be linked after success and source/hash verification. Live catalogue
is unchanged; the prior matching Char/Map/pet-journal activation requirements still
apply before this expanded catalogue can be used on the live server.
