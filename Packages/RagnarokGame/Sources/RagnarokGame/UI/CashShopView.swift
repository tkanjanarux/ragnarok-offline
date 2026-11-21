import RagnarokResources
import SwiftUI

/// Original CashShop layout: 535px Sell List, 186px Buy List, nine category tabs.
/// GRF paths and layout follow roBrowser's UI/Components/CashShop.
struct CashShopView: View {
    var close: () -> Void
    @Environment(PlaySession.self) private var session
    @Environment(GameContext.self) private var context
    @State private var tab: UInt16 = 6
    @State private var search = ""
    @State private var page = 0
    @State private var freePoints = "0"
    @State private var confirming = false
    @State private var detail: CashShopProduct?

    private var free: UInt32? { UInt32(freePoints) }
    private var filtered: [CashShopProduct] {
        session.cashShop.products.filter { $0.tab == tab && (search.isEmpty || name($0).localizedCaseInsensitiveContains(search)) }
            .sorted { $0.itemID < $1.itemID }
    }
    private var pages: Int { max(1, (filtered.count + 8) / 9) }
    private var visible: [CashShopProduct] { Array(filtered.dropFirst(min(page, pages - 1) * 9).prefix(9)) }
    private func name(_ product: CashShopProduct) -> String {
        context.itemInfoTable.localizedIdentifiedItemName(forItemID: Int(product.itemID)) ?? "Item #\(product.itemID)"
    }

    var body: some View {
        ClassicGamePanel(title: "Cash Shop", width: 723, height: 540, onClose: close) {
            ZStack {
                HStack(spacing: 2) {
                    sellList.frame(width: 535)
                    buyList.frame(width: 182)
                }
                .padding(2)
                .background { GameImage("cashshop/img_shop_bg.bmp") { $0.resizable() }.allowsHitTesting(false) }
                .disabled(confirming || detail != nil)
                if let detail { itemDetails(detail) }
                if confirming { confirmation }
            }
            .font(.game())
            .foregroundStyle(Color.gameLabel)
        }
        .onAppear { session.openCashShop() }
        .onDisappear { session.closeCashShop() }
        .onChange(of: tab) { page = 0 }
        .onChange(of: search) { page = 0 }
    }

    private var emptyCatalogueMessage: String {
        if !session.cashShop.ready { return "Opening shop…" }
        if session.cashShop.products.isEmpty { return "Shop catalogue unavailable.\nReconnect to refresh." }
        return search.isEmpty ? "No items in this category." : "No matching items."
    }

    private var sellList: some View {
        VStack(spacing: 3) {
            Text("Sell List").frame(maxWidth: .infinity).frame(height: 22)
                .background(Color.white.opacity(0.7))
            // Advertisements are intentionally empty when no server banner is configured.
            Color.white.opacity(0.45).frame(height: 36)
            HStack(spacing: 0) {
                ForEach(0..<9, id: \.self) { index in
                    Button { tab = UInt16(index) } label: {
                        CashShopSkinLabel(
                            name: "img_shop_tap\(index)_\(tab == UInt16(index) ? "on" : "off").bmp",
                            fallback: CashShopState.tabs[index])
                            .id("tab-\(index)-\(tab == UInt16(index))")
                            .frame(width: 56, height: 31)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .accessibilityLabel(CashShopState.tabs[index])
                        .accessibilityAddTraits(tab == UInt16(index) ? .isSelected : [])
                }
            }
            ZStack(alignment: .topLeading) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(172), spacing: 4), count: 3), spacing: 2) {
                    ForEach(visible) { product in productCell(product) }
                }
                if visible.isEmpty {
                    Text(emptyCatalogueMessage)
                        .frame(width: 525, height: 370)
                }
            }.frame(height: 382, alignment: .topLeading)
            HStack(spacing: 4) {
                TextField("Search", text: $search).textFieldStyle(.plain)
                    .padding(.horizontal, 4).frame(width: 160, height: 20)
                    .background(.white).border(Color.gameBoxBorder)
                skinButton("Search", image: "btn_searchbar_normal", width: 48, showsText: false) { page = 0 }
                Spacer(minLength: 0)
                arrow("|‹", image: "bt_arrowL2_on", enabled: page > 0) { page = 0 }
                arrow("‹", image: "bt_arrowL_on", enabled: page > 0) { page -= 1 }
                Text("\(min(page + 1, pages)) / \(pages)").frame(width: 46)
                arrow("›", image: "bt_arrowR_on", enabled: page + 1 < pages) { page += 1 }
                arrow("›|", image: "bt_arrowR2_on", enabled: page + 1 < pages) { page = pages - 1 }
            }.padding(.horizontal, 4).frame(height: 24)
        }
    }

    private func productCell(_ product: CashShopProduct) -> some View {
        VStack(spacing: 2) {
            Text(name(product)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 5).frame(height: 22)
            HStack(spacing: 3) {
                Button { detail = product } label: {
                    CashShopItemImage(itemID: product.itemID, preview: true).frame(width: 85, height: 87)
                }.buttonStyle(.plain).accessibilityLabel("Item information: " + name(product))
                VStack(spacing: 14) {
                    Text("\(product.price) C").lineLimit(1)
                    skinButton("Purchase", image: "btn_add_normal", width: 70) {
                        session.cashShop.addToCart(product)
                    }.disabled(session.cashShop.pending || !session.cashShop.ready)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: 172, height: 126)
        .background {
            ZStack {
                Color.white
                GameImage("cashshop/img_shop_itembg.bmp") { $0.resizable() }
            }
        }
        .border(Color.gameBoxBorder.opacity(0.4))
    }

    private var buyList: some View {
        VStack(spacing: 4) {
            Text("Buy List").frame(maxWidth: .infinity).frame(height: 22)
            HStack { Text("Cash Point"); Spacer(); Text("\(session.cashShop.cash)") }.padding(.horizontal, 4)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(session.cashShop.cart) { line in cartRow(line) }
                }
            }.frame(height: 287)
                .background { GameImage("cashshop/img_shop_cart_bg.bmp") { $0.resizable() } }
            VStack(spacing: 4) {
                HStack { Text("Free Points"); Spacer(); Text("\(session.cashShop.kafra)") }
                HStack {
                    Text("Use Free Points")
                    TextField("0", text: $freePoints).textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing).frame(width: 54, height: 20)
                        .background(.white).border(Color.gameBoxBorder)
                }.disabled(session.cashShop.pending)
                HStack { Text("Cash Point"); Spacer(); Text("\(session.cashShop.cartTotal - min(UInt64(free ?? 0), session.cashShop.cartTotal))") }
            }.padding(4)
            HStack { Text("Total Price"); Spacer(); Text("\(session.cashShop.cartTotal) C") }
                .padding(.horizontal, 4)
            skinButton(session.cashShop.checkingBalance ? "Checking…" : (session.cashShop.pending ? "Buying…" : "Purchase"), image: "btn_buy_normal", width: 82) { confirming = true }
                .disabled(free == nil || !session.cashShop.canPurchaseCart(freePoints: free ?? 0))
            Text(purchaseStatus)
                .font(.system(size: 10)).frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 60, alignment: .top).padding(.horizontal, 4)
            Spacer(minLength: 0)
        }.background(Color.white.opacity(0.5))
    }

    private var purchaseStatus: String {
        if let message = session.cashShop.message { return message }
        guard !session.cashShop.cart.isEmpty else { return "Add up to 8 items. Maximum 99 each." }
        guard let free else { return "Enter a valid Free Points amount." }
        if free > session.cashShop.kafra || UInt64(free) > session.cashShop.cartTotal {
            return "Free Points amount exceeds your balance or total price."
        }
        let required = session.cashShop.cartTotal - UInt64(free)
        if required > UInt64(session.cashShop.cash) {
            return "Not enough Cash Points. Need \(required), available \(session.cashShop.cash)."
        }
        return "Review your Buy List, then choose Purchase."
    }

    private func cartRow(_ line: CashShopCartLine) -> some View {
        HStack(spacing: 3) {
            CashShopItemImage(itemID: line.product.itemID, preview: false).frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(name(line.product)).lineLimit(1)
                HStack(spacing: 3) {
                    Text("\(line.quantity)").frame(width: 22)
                    smallButton("−") { session.cashShop.setQuantity(line.quantity - 1, for: line.id) }
                    smallButton("+") { session.cashShop.setQuantity(line.quantity + 1, for: line.id) }
                    Spacer(minLength: 0)
                }
                Text("\(line.product.price) C")
            }
            Button { session.cashShop.setQuantity(0, for: line.id) } label: {
                CashShopSkinLabel(name: "btn_close.bmp", fallback: "×")
                    .frame(width: 14, height: 14)
                    .frame(width: 36, height: 44)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityLabel("Remove " + name(line.product))
        }.padding(3).frame(height: 64)
            .background { GameImage("cashshop/img_shop_itembg2.bmp") { $0.resizable() } }
            .disabled(session.cashShop.pending)
    }

    private func itemDetails(_ product: CashShopProduct) -> some View {
        VStack(spacing: 0) {
            GameTitleBar(Text(verbatim: name(product)), closeAction: { detail = nil }, usesGameSkin: true)
            HStack(alignment: .top, spacing: 8) {
                CashShopItemImage(itemID: product.itemID, preview: true).frame(width: 85, height: 100)
                ScrollView {
                    Text(AttributedString(description: context.itemInfoTable.localizedIdentifiedItemDescription(forItemID: Int(product.itemID)) ?? "", defaultColor: .gameLabel))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.frame(height: 205)
            }.padding(8)
        }.frame(width: 340).background(Color.white).border(Color.gameBoxBorder)
    }

    private var confirmation: some View {
        VStack(spacing: 12) {
            Text("Purchase items?").frame(maxWidth: .infinity).padding(4)
                .background { GameImage("basic_interface/titlebar_mid.bmp") { $0.resizable() } }
            Text("Total: \(session.cashShop.cartTotal) C\nFree Points: \(free ?? 0)")
                .multilineTextAlignment(.center)
            HStack {
                Button("OK") {
                    confirming = false
                    if let free { session.buyCashShopCart(freePoints: free) }
                }.buttonStyle(.game).frame(width: 55, height: 22)
                Button("Cancel") { confirming = false }.buttonStyle(.game).frame(width: 55, height: 22)
            }.padding(.bottom, 8)
        }.frame(width: 280).background(Color.white).border(Color.gameBoxBorder)
    }

    private func skinButton(_ label: String, image: String, width: CGFloat, showsText: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            CashShopSkinLabel(name: "\(image).bmp", fallback: label, showsText: showsText)
                .frame(width: width, height: 22)
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    private func smallButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(label, action: action).buttonStyle(.game).frame(width: 18, height: 17)
    }
    private func arrow(_ label: String, image: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        skinButton(label, image: image, width: 20, showsText: false, action: action).disabled(!enabled)
    }
}

private struct CashShopItemImage: View {
    var itemID: UInt32
    var preview: Bool
    @Environment(GameContext.self) private var context
    @State private var resource: Resources.Image?
    var body: some View {
        Group {
            if let resource { Image(decorative: resource.cgImage, scale: 1).resizable().scaledToFit() }
            else { Color.clear }
        }.task(id: itemID) {
            if preview {
                resource = try? await context.resourceManager.itemPreviewImage(forItemID: Int(itemID))
            } else {
                resource = try? await context.resourceManager.itemIconImage(forItemID: Int(itemID))
            }
        }
    }
}

/// Tabs/arrows contain icons; Purchase assets are backgrounds with separate text.
private struct CashShopSkinLabel: View {
    var name: String
    var fallback: String
    var showsText = false
    @Environment(GameContext.self) private var context
    @State private var resource: Resources.Image?
    @State private var loadedName = ""
    var body: some View {
        // A stable container keeps the loader alive when resource state changes.
        ZStack {
            if let resource, loadedName == name {
                Image(decorative: resource.cgImage, scale: 1).resizable()
                if showsText { Text(fallback).font(.game(size: 11)).foregroundStyle(Color.gameLabel) }
            } else {
                Color(white: 0.92)
                Text(fallback).font(.game(size: 10)).multilineTextAlignment(.center)
            }
        }.accessibilityLabel(fallback).task(id: name) {
            let path = ResourcePath.userInterfaceDirectory.appending(["cashshop", name])
            let loaded = try? await context.resourceManager.image(at: path, removesMagentaPixels: true)
            guard !Task.isCancelled else { return }
            resource = loaded
            loadedName = name
        }
    }
}
