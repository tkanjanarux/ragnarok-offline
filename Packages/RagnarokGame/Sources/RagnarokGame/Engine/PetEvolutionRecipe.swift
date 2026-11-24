// Public rAthena pet evolution recipes. Copyright (C) 2021 rAthena Development Team.
// GPL-3.0-or-later, https://github.com/rathena/rathena
// Catalog evidence SHA256: ce86c34ef97ae6228b4cf8d62d2f152df07e6c084a5ac58b494b5b47cd056de2
// Costs are reference data; only the server can authorize and complete evolution.
struct PetEvolutionRecipe: Identifiable {
    var id: Int { egg }
    let base: Int, target: Int, egg: Int
    let materials: [(id: Int, amount: Int)]
    static let all: [PetEvolutionRecipe] = [
        .init(base: 1002, target: 1090, egg: 9069, materials: [(id: 610, amount: 10), (id: 619, amount: 3)]),
        .init(base: 1113, target: 3495, egg: 9092, materials: [(id: 7032, amount: 20), (id: 7031, amount: 10), (id: 531, amount: 3), (id: 4659, amount: 1)]),
        .init(base: 1113, target: 3790, egg: 9109, materials: [(id: 25290, amount: 500), (id: 529, amount: 50), (id: 530, amount: 50), (id: 4004, amount: 1)]),
        .init(base: 1063, target: 3496, egg: 9094, materials: [(id: 7198, amount: 100), (id: 705, amount: 250), (id: 706, amount: 30), (id: 4663, amount: 1)]),
        .init(base: 1167, target: 1166, egg: 9070, materials: [(id: 537, amount: 10), (id: 627, amount: 3), (id: 517, amount: 100), (id: 949, amount: 50)]),
        .init(base: 1107, target: 1106, egg: 9129, materials: [(id: 628, amount: 3), (id: 4082, amount: 1), (id: 7030, amount: 300), (id: 919, amount: 20)]),
        .init(base: 1052, target: 1058, egg: 9106, materials: [(id: 707, amount: 3), (id: 940, amount: 777), (id: 508, amount: 200), (id: 4057, amount: 1)]),
        .init(base: 1019, target: 1369, egg: 9071, materials: [(id: 537, amount: 10), (id: 632, amount: 3), (id: 7101, amount: 300), (id: 4031, amount: 1), (id: 522, amount: 10)]),
        .init(base: 1057, target: 1214, egg: 9091, materials: [(id: 634, amount: 3), (id: 753, amount: 2), (id: 7182, amount: 300), (id: 4051, amount: 1)]),
        .init(base: 1023, target: 1213, egg: 9087, materials: [(id: 635, amount: 3), (id: 1124, amount: 1), (id: 931, amount: 500), (id: 2267, amount: 1), (id: 4066, amount: 1)]),
        .init(base: 1110, target: 1301, egg: 9089, materials: [(id: 637, amount: 3), (id: 981, amount: 3), (id: 1021, amount: 300), (id: 969, amount: 3)]),
        .init(base: 1029, target: 3636, egg: 9090, materials: [(id: 639, amount: 3), (id: 10006, amount: 1), (id: 954, amount: 300), (id: 732, amount: 6)]),
        .init(base: 1155, target: 3670, egg: 9098, materials: [(id: 640, amount: 3), (id: 6260, amount: 100), (id: 606, amount: 150), (id: 4279, amount: 1)]),
        .init(base: 1109, target: 3669, egg: 9097, materials: [(id: 641, amount: 3), (id: 1039, amount: 250), (id: 1009, amount: 30), (id: 4122, amount: 1)]),
        .init(base: 1188, target: 1512, egg: 9093, materials: [(id: 5367, amount: 1), (id: 7277, amount: 100), (id: 7014, amount: 50), (id: 4328, amount: 1)]),
        .init(base: 1275, target: 1737, egg: 9120, materials: [(id: 7047, amount: 500), (id: 511, amount: 200), (id: 985, amount: 30), (id: 4253, amount: 1)]),
        .init(base: 1208, target: 20420, egg: 9117, materials: [(id: 7005, amount: 500), (id: 1009, amount: 50), (id: 1059, amount: 100), (id: 4210, amount: 1)]),
        .init(base: 1040, target: 3023, egg: 9131, materials: [(id: 953, amount: 500), (id: 12371, amount: 3), (id: 27029, amount: 1), (id: 990, amount: 20)]),
        .init(base: 1379, target: 20373, egg: 9116, materials: [(id: 7120, amount: 500), (id: 510, amount: 100), (id: 935, amount: 100), (id: 4166, amount: 1)]),
        .init(base: 1180, target: 1307, egg: 9096, materials: [(id: 23187, amount: 3), (id: 1022, amount: 999), (id: 10008, amount: 1), (id: 4159, amount: 1)]),
        .init(base: 1632, target: 1773, egg: 9105, materials: [(id: 23188, amount: 3), (id: 6100, amount: 50), (id: 7340, amount: 200), (id: 4413, amount: 1)]),
        .init(base: 1041, target: 1297, egg: 9107, materials: [(id: 23256, amount: 3), (id: 7511, amount: 200), (id: 969, amount: 30), (id: 4248, amount: 1)]),
        .init(base: 1622, target: 2995, egg: 9108, materials: [(id: 23189, amount: 3), (id: 7442, amount: 300), (id: 724, amount: 50), (id: 4340, amount: 1)]),
        .init(base: 1622, target: 1736, egg: 9118, materials: [(id: 7317, amount: 500), (id: 518, amount: 100), (id: 727, amount: 10), (id: 4340, amount: 1)]),
        .init(base: 1622, target: 1735, egg: 9119, materials: [(id: 7317, amount: 500), (id: 518, amount: 100), (id: 7449, amount: 50), (id: 4340, amount: 1)]),
        .init(base: 1090, target: 1096, egg: 9088, materials: [(id: 503, amount: 20), (id: 2282, amount: 1), (id: 509, amount: 50), (id: 909, amount: 200)]),
        .init(base: 20696, target: 20697, egg: 9124, materials: [(id: 1000103, amount: 500), (id: 7095, amount: 50), (id: 7094, amount: 10)]),
    ]
}
