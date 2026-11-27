// Curated server item/view mapping. No GRF art is bundled here.
// Source evidence: docs/cash-shop-full-catalogue/coverage.json.
struct CashShopCostume: Sendable {
    let view: Int
    let garment: Bool

    static func forItem(_ itemID: UInt32) -> CashShopCostume? {
        switch itemID {
        case 19587: return CashShopCostume(view: 905, garment: false)
        case 19876: return CashShopCostume(view: 384, garment: false)
        case 19843: return CashShopCostume(view: 2, garment: false)
        case 19578: return CashShopCostume(view: 1, garment: false)
        case 19605: return CashShopCostume(view: 369, garment: false)
        case 19903: return CashShopCostume(view: 717, garment: false)
        case 31395: return CashShopCostume(view: 1691, garment: false)
        case 20132: return CashShopCostume(view: 1267, garment: false)
        case 19667: return CashShopCostume(view: 464, garment: false)
        case 19630: return CashShopCostume(view: 45, garment: false)
        case 19618: return CashShopCostume(view: 153, garment: false)
        case 19289: return CashShopCostume(view: 1370, garment: false)
        case 19617: return CashShopCostume(view: 199, garment: false)
        case 19739: return CashShopCostume(view: 838, garment: false)
        case 20202: return CashShopCostume(view: 1082, garment: false)
        case 19702: return CashShopCostume(view: 390, garment: false)
        case 19910: return CashShopCostume(view: 1098, garment: false)
        case 31143: return CashShopCostume(view: 1560, garment: false)
        default: return nil
        }
    }
}
