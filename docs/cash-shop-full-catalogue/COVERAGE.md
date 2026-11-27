# Cash Shop: all 88 requirements

85 requirements have implementation and enumerated isolated tests; 11/12 are explicit potion adaptations; 88 is excluded. Live catalogue remains unchanged.

Ready means ready for deployment review, not exhaustive testing or device acceptance. See [limits and usage](README.md), [deployment plan](SERVER-DELIVERY.md), and [full specifications/evidence](coverage.json).

| # | Requirement | Exact sale ID / AegisName / Cash | Status | Effect evidence / limitation |
|---|---|---|---|---|
| 1 | White Syrup 100/200 | 2000010 RO_Catalogue_1_0 (900); 2000011 RO_Catalogue_1_1 (1800) | isolated_verified_pending_deploy | [consumable-effects](consumable-effects-evidence.json) |
| 2 | Blue Syrup pack | 2000020 RO_Catalogue_2_0 (900) | isolated_verified_pending_deploy | [consumable-effects](consumable-effects-evidence.json) |
| 3 | White Slim Potion pack | 2000030 RO_Catalogue_3_0 (450) | isolated_verified_pending_deploy | [consumable-effects](consumable-effects-evidence.json) |
| 4 | Blue Potion large box | 2000040 RO_Catalogue_4_0 (450) | isolated_verified_pending_deploy | [consumable-effects](consumable-effects-evidence.json) |
| 5 | Panacea pack | 2000050 RO_Catalogue_5_0 (90) | isolated_verified_pending_deploy | [status-items](status-items-evidence.json) |
| 6 | Holy Water pack | 2000060 RO_Catalogue_6_0 (36) | isolated_verified_pending_deploy | [status-items](status-items-evidence.json) |
| 7 | Fire resistance potion | 2000070 RO_Catalogue_7_0 (90) | isolated_verified_pending_deploy | [status-items](status-items-evidence.json), [resist-combat](resist-combat-evidence.json) |
| 8 | Water resistance potion | 2000080 RO_Catalogue_8_0 (90) | isolated_verified_pending_deploy | [status-items](status-items-evidence.json), [resist-combat](resist-combat-evidence.json) |
| 9 | Wind resistance potion | 2000090 RO_Catalogue_9_0 (90) | isolated_verified_pending_deploy | [status-items](status-items-evidence.json), [resist-combat](resist-combat-evidence.json) |
| 10 | Earth resistance potion | 2000100 RO_Catalogue_10_0 (90) | isolated_verified_pending_deploy | [status-items](status-items-evidence.json), [resist-combat](resist-combat-evidence.json) |
| 11 | MaxHP food | 2000110 RO_Catalogue_11_0 (135) | adapted_pending_deploy | Functional MaxHP/MaxSP booster uses the existing medium increase potion, explicitly named in shop details; not represented as literal food. [consumable-effects](consumable-effects-evidence.json), [buff-effects](buff-effects-evidence.json) |
| 12 | MaxSP food | 2000120 RO_Catalogue_12_0 (135) | adapted_pending_deploy | Functional MaxHP/MaxSP booster uses the existing medium increase potion, explicitly named in shop details; not represented as literal food. [consumable-effects](consumable-effects-evidence.json), [buff-effects](buff-effects-evidence.json) |
| 13 | Normal arrow box | 2000130 RO_Catalogue_13_0 (45) | isolated_verified_pending_deploy | [outgoing-elements](outgoing-elements-evidence.json) |
| 14 | Silver Arrow | 2000140 RO_Catalogue_14_0 (45) | isolated_verified_pending_deploy | [outgoing-elements](outgoing-elements-evidence.json) |
| 15 | Fire Arrow | 2000150 RO_Catalogue_15_0 (45) | isolated_verified_pending_deploy | [outgoing-elements](outgoing-elements-evidence.json) |
| 16 | Crystal Arrow | 2000160 RO_Catalogue_16_0 (45) | isolated_verified_pending_deploy | [outgoing-elements](outgoing-elements-evidence.json) |
| 17 | Wind Arrow | 2000170 RO_Catalogue_17_0 (45) | isolated_verified_pending_deploy | [outgoing-elements](outgoing-elements-evidence.json) |
| 18 | Stone Arrow | 2000180 RO_Catalogue_18_0 (45) | isolated_verified_pending_deploy | [outgoing-elements](outgoing-elements-evidence.json) |
| 19 | Shadow Arrow | 2000190 RO_Catalogue_19_0 (45) | isolated_verified_pending_deploy | [outgoing-elements](outgoing-elements-evidence.json) |
| 20 | Immaterial Arrow | 2000200 RO_Catalogue_20_0 (45) | isolated_verified_pending_deploy | [outgoing-elements](outgoing-elements-evidence.json) |
| 21 | Selectable mixed elemental arrows | 2000210 RO_Catalogue_21_0 (90); 2000211 RO_Catalogue_21_1 (90); 2000212 RO_Catalogue_21_2 (90); 2000213 RO_Catalogue_21_3 (90); 2000214 RO_Catalogue_21_4 (90); 2000215 RO_Catalogue_21_5 (90) | isolated_verified_pending_deploy | [outgoing-elements](outgoing-elements-evidence.json) |
| 22 | Arrow Crafting materials | 2000220 RO_Catalogue_22_0 (945) | isolated_verified_pending_deploy | [outgoing-elements](outgoing-elements-evidence.json), [utilities](utilities-evidence.json) |
| 23 | Fire Converter | 2000230 RO_Catalogue_23_0 (90) | isolated_verified_pending_deploy | [status-items](status-items-evidence.json), [outgoing-elements](outgoing-elements-evidence.json) |
| 24 | Water Converter | 2000240 RO_Catalogue_24_0 (90) | isolated_verified_pending_deploy | [status-items](status-items-evidence.json), [outgoing-elements](outgoing-elements-evidence.json) |
| 25 | Wind Converter | 2000250 RO_Catalogue_25_0 (90) | isolated_verified_pending_deploy | [status-items](status-items-evidence.json), [outgoing-elements](outgoing-elements-evidence.json) |
| 26 | Earth Converter | 2000260 RO_Catalogue_26_0 (90) | isolated_verified_pending_deploy | [status-items](status-items-evidence.json), [outgoing-elements](outgoing-elements-evidence.json) |
| 27 | STR moderate food | 2000270 RO_Catalogue_27_0 (90) | isolated_verified_pending_deploy | [consumable-effects](consumable-effects-evidence.json), [buff-effects](buff-effects-evidence.json) |
| 28 | AGI moderate food | 2000280 RO_Catalogue_28_0 (90) | isolated_verified_pending_deploy | [consumable-effects](consumable-effects-evidence.json), [buff-effects](buff-effects-evidence.json) |
| 29 | VIT moderate food | 2000290 RO_Catalogue_29_0 (90) | isolated_verified_pending_deploy | [consumable-effects](consumable-effects-evidence.json), [buff-effects](buff-effects-evidence.json) |
| 30 | INT moderate food | 2000300 RO_Catalogue_30_0 (90) | isolated_verified_pending_deploy | [consumable-effects](consumable-effects-evidence.json), [buff-effects](buff-effects-evidence.json) |
| 31 | DEX moderate food | 2000310 RO_Catalogue_31_0 (90) | isolated_verified_pending_deploy | [consumable-effects](consumable-effects-evidence.json), [buff-effects](buff-effects-evidence.json) |
| 32 | LUK moderate food | 2000320 RO_Catalogue_32_0 (90) | isolated_verified_pending_deploy | [consumable-effects](consumable-effects-evidence.json), [buff-effects](buff-effects-evidence.json) |
| 33 | Selectable stat food | 2000270 RO_Catalogue_27_0 (90); 2000280 RO_Catalogue_28_0 (90); 2000290 RO_Catalogue_29_0 (90); 2000300 RO_Catalogue_30_0 (90); 2000310 RO_Catalogue_31_0 (90); 2000320 RO_Catalogue_32_0 (90) | isolated_verified_pending_deploy | [consumable-effects](consumable-effects-evidence.json), [buff-effects](buff-effects-evidence.json) |
| 34 | Speed Potion | 2000340 RO_Catalogue_34_0 (90) | isolated_verified_pending_deploy | [status-items](status-items-evidence.json) |
| 35 | Neuralizer | 2000350 RO_Catalogue_Skill_Reset (500) | isolated_verified_pending_deploy | [services](services-evidence.json), [service-limits](service-limits-evidence.json) |
| 36 | Stat reset voucher | 2000360 RO_Catalogue_Stat_Reset (500) | isolated_verified_pending_deploy | [services](services-evidence.json), [service-limits](service-limits-evidence.json) |
| 37 | Full skill/stat reset pack | 2000370 RO_Catalogue_Full_Reset (900) | isolated_verified_pending_deploy | [services](services-evidence.json), [service-limits](service-limits-evidence.json) |
| 38 | Gym Pass | 2000380 RO_Catalogue_Gym (100) | isolated_verified_pending_deploy | [services](services-evidence.json), [service-limits](service-limits-evidence.json), [gym-weight](gym-weight-evidence.json) |
| 39 | Token of Siegfried | 7621 Token_Of_Siegfried (20) | isolated_verified_pending_deploy | [utilities](utilities-evidence.json) |
| 40 | Giant Fly Wing | 12212 Giant_Fly_Wing (10) | isolated_verified_pending_deploy | [giant-wing](giant-wing-evidence.json), [giant-wing-stopped](giant-wing-stopped-evidence.json) |
| 41 | Magnifier pack | 2000410 RO_Catalogue_41_0 (90) | isolated_verified_pending_deploy | [utilities](utilities-evidence.json) |
| 42 | Portable repair service | 2000420 RO_Catalogue_Repair (100) | isolated_verified_pending_deploy | [services](services-evidence.json), [service-limits](service-limits-evidence.json) |
| 43 | Hairstyle voucher | 2000430 RO_Catalogue_Hairstyle (100) | isolated_verified_pending_deploy | [styles](styles-evidence.json) |
| 44 | Hair/clothes color voucher | 2000440 RO_Catalogue_Hair_Dye (100); 2000441 RO_Catalogue_Clothes_Dye (100) | isolated_verified_pending_deploy | [styles](styles-evidence.json) |
| 45 | Character rename voucher | 2000450 RO_Catalogue_Rename (500) | isolated_verified_pending_deploy | [services](services-evidence.json), [service-limits](service-limits-evidence.json), [rename](rename-evidence.json) |
| 46 | Card removal voucher | 2000460 RO_Catalogue_Card_Removal (100) | isolated_verified_pending_deploy | [card-removal](card-removal-evidence.json), [card-outcomes](card-outcomes-evidence.json) |
| 47 | Costume Poring hat | 19587 C_King_Poring_Hat (250) | isolated_verified_pending_deploy | [costumes](costumes-evidence.json) |
| 48 | Costume rabbit hat | 19876 C_Rabbit_Ear_Hat (250) | isolated_verified_pending_deploy | [costumes](costumes-evidence.json) |
| 49 | Costume cat hat | 19843 C_Cat_Hairband (250) | isolated_verified_pending_deploy | [costumes](costumes-evidence.json) |
| 50 | Costume goggles | 19578 C_Goggle (250) | isolated_verified_pending_deploy | [costumes](costumes-evidence.json) |
| 51 | Costume scarf | 19605 C_Gang_Scarf (250) | isolated_verified_pending_deploy | [costumes](costumes-evidence.json) |
| 52 | Costume backpack | 20513 C_EXE_Backpack (250) | isolated_verified_pending_deploy | [costumes](costumes-evidence.json) |
| 53 | Costume witch hat | 19903 C_Witchs_Hat (250) | isolated_verified_pending_deploy | [costumes](costumes-evidence.json) |
| 54 | Costume floating book | 31395 C_Book_Of_Magic (250) | isolated_verified_pending_deploy | [costumes](costumes-evidence.json) |
| 55 | Costume magic aura | 20132 C_Subject_Aura (250) | isolated_verified_pending_deploy | [costumes](costumes-evidence.json) |
| 56 | Costume armored helm | 19667 C_Helm_Of_Dragoon (250) | isolated_verified_pending_deploy | [costumes](costumes-evidence.json) |
| 57 | Costume knight cape | 420046 C_Royal_Mantle (250) | isolated_verified_pending_deploy | [costumes](costumes-evidence.json) |
| 58 | Costume crown | 19630 C_Crown (250) | isolated_verified_pending_deploy | [costumes](costumes-evidence.json) |
| 59 | Costume mask | 19618 C_Mask_Of_Fox (250) | isolated_verified_pending_deploy | [costumes](costumes-evidence.json) |
| 60 | Costume black wings | 20764 C_Fallen_Angel_Wing (250) | isolated_verified_pending_deploy | [costumes](costumes-evidence.json) |
| 61 | Costume eyepatch | 19289 C_Moon_Eyepatch (250) | isolated_verified_pending_deploy | [costumes](costumes-evidence.json) |
| 62 | Costume animal ears | 19617 C_Ear_Of_Puppy (250) | isolated_verified_pending_deploy | [costumes](costumes-evidence.json) |
| 63 | Costume animal on head | 19739 C_Sleeping_Kitty_Cat (250) | isolated_verified_pending_deploy | [costumes](costumes-evidence.json) |
| 64 | Costume balloon | 20202 C_Deviruchi_Balloon (250) | isolated_verified_pending_deploy | [costumes](costumes-evidence.json) |
| 65 | Costume halo | 20536 C_Violet_Halo (250) | isolated_verified_pending_deploy | [costumes](costumes-evidence.json) |
| 66 | Costume white wings | 20765 C_Archangel_Wing (250) | isolated_verified_pending_deploy | [costumes](costumes-evidence.json) |
| 67 | Costume priest cape | 31438 C_Fluffy_Angel_Cape (250) | isolated_verified_pending_deploy | [costumes](costumes-evidence.json) |
| 68 | Christmas costume | 19702 C_Santa_Hat_1 (250) | isolated_verified_pending_deploy | [costumes](costumes-evidence.json) |
| 69 | Halloween costume | 19910 C_Halloween_Hat (250) | isolated_verified_pending_deploy | [costumes](costumes-evidence.json) |
| 70 | Thai themed costume | 31143 C_Krathong_Crown_TH (250) | isolated_verified_pending_deploy | [costumes](costumes-evidence.json) |
| 71 | Starter pet egg + correct food | 2000710 RO_Catalogue_Poring_Starter (500); 643 Pet_Incubator (5) | isolated_verified_pending_deploy | [pet-packs-final](pet-packs-final-evidence.json), [pet-edges](pet-edges-evidence.json), [pet-species](pet-species-evidence.json) |
| 72 | Bulk pet food | 2000720 RO_Catalogue_72_0 (90); 2000721 RO_Catalogue_72_1 (90); 2000722 RO_Catalogue_72_2 (90); 2000723 RO_Catalogue_72_3 (90); 2000724 RO_Catalogue_72_4 (90) | isolated_verified_pending_deploy | [pet-species](pet-species-evidence.json) |
| 73 | Pet accessories | 10013 Backpack (100); 10007 Silk_Ribbon (100); 10012 Tiny_Egg_Shell (100); 10002 Monster_Oxygen_Mask (100); 10017 Bark_Shorts (100) | isolated_verified_pending_deploy | [pet-species](pet-species-evidence.json) |
| 74 | Species-selectable taming kit | 2000740 RO_Catalogue_74_0 (135); 2000741 RO_Catalogue_74_1 (135); 2000742 RO_Catalogue_74_2 (135); 2000743 RO_Catalogue_74_3 (135); 2000744 RO_Catalogue_74_4 (135); 2000745 RO_Catalogue_74_5 (135) | isolated_verified_pending_deploy | [pet-species](pet-species-evidence.json), [taming-final](taming-final-evidence.json), [capture-recovery](capture-recovery-evidence.json) |
| 75 | Mage/hunter/priest themed pets | 2000710 RO_Catalogue_Poring_Starter (500); 2000750 RO_Catalogue_Spore_Starter (500); 2000751 RO_Catalogue_Lunatic_Starter (500) | isolated_verified_pending_deploy | [pet-packs-final](pet-packs-final-evidence.json), [pet-edges](pet-edges-evidence.json), [pet-species](pet-species-evidence.json) |
| 76 | Prontera/Payon/Morroc collectible costume | 19630 C_Crown (250); 19618 C_Mask_Of_Fox (250); 19844 C_Turban (250) | isolated_verified_pending_deploy | [costumes](costumes-evidence.json) |
| 77 | Hunter Supply | 2000770 RO_Catalogue_77_0 (360); 2000771 RO_Catalogue_77_1 (360); 2000772 RO_Catalogue_77_2 (360); 2000773 RO_Catalogue_77_3 (360); 2000774 RO_Catalogue_77_4 (360); 2000775 RO_Catalogue_77_5 (360) | isolated_verified_pending_deploy | [status-items](status-items-evidence.json), [outgoing-elements](outgoing-elements-evidence.json) |
| 78 | Knight Puller | 2000780 RO_Catalogue_78_0 (2025) | isolated_verified_pending_deploy | [consumable-effects](consumable-effects-evidence.json) |
| 79 | Wizard Supply | 2000790 RO_Catalogue_79_0 (630) | isolated_verified_pending_deploy | [consumable-effects](consumable-effects-evidence.json) |
| 80 | Priest Support | 2000800 RO_Catalogue_80_0 (576) | isolated_verified_pending_deploy | [consumable-effects](consumable-effects-evidence.json), [status-items](status-items-evidence.json) |
| 81 | Assassin Supply | 2000810 RO_Catalogue_81_0 (1215); 2000811 RO_Catalogue_81_1 (1215); 2000812 RO_Catalogue_81_2 (1215); 2000813 RO_Catalogue_81_3 (1215) | isolated_verified_pending_deploy | [status-items](status-items-evidence.json), [outgoing-elements](outgoing-elements-evidence.json) |
| 82 | Farming outing | 2000820 RO_Catalogue_82_0 (1163) | isolated_verified_pending_deploy | [consumable-effects](consumable-effects-evidence.json), [utilities](utilities-evidence.json), [wings](wings-evidence.json) |
| 83 | Loot hunt | 2000830 RO_Catalogue_83_0 (1350) | isolated_verified_pending_deploy | [buff-effects](buff-effects-evidence.json) |
| 84 | Leveling | 2000840 RO_Catalogue_84_0 (765) | isolated_verified_pending_deploy | [buff-effects](buff-effects-evidence.json) |
| 85 | Map exploration | 2000850 RO_Catalogue_85_0 (672); 2000851 RO_Catalogue_85_1 (672); 2000852 RO_Catalogue_85_2 (672); 2000853 RO_Catalogue_85_3 (672) | isolated_verified_pending_deploy | [status-items](status-items-evidence.json), [resist-combat](resist-combat-evidence.json), [wings](wings-evidence.json) |
| 86 | Build change | 2000860 RO_Catalogue_86_0 (963) | isolated_verified_pending_deploy | [consumable-effects](consumable-effects-evidence.json), [services](services-evidence.json), [service-limits](service-limits-evidence.json) |
| 87 | Five-companion role supplies | 2000870 RO_Catalogue_87_0 (180); 2000871 RO_Catalogue_87_1 (162); 2000872 RO_Catalogue_87_2 (279); 2000873 RO_Catalogue_87_3 (297); 2000874 RO_Catalogue_87_4 (153) | isolated_verified_pending_deploy | [companion-supplies](companion-supplies-evidence.json), [companion-combat](companion-combat-evidence.json), [reprice-companion](reprice-companion-evidence.json) |
| 88 | Team fashion | Excluded; no sale SKU | blocked_excluded | Current companion gear_runtime::reason explicitly rejects EQP_COSTUME and EQP_SHADOW_GEAR. Team fashion is conditional on appearance support; excluded from sale, not replaced by stat gear. |

Device visual/hardware acceptance is unverified for every row. No Simulator is required.
Quantities, components, service policy, variant choice, restrictions, assets and transaction evidence are in coverage.json and candidate specifications. Prices use local virtual Cash; no live grants/charges occurred.
