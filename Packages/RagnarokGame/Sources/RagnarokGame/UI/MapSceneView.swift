//
//  MapSceneView.swift
//  RagnarokGame
//
//  Created by Leon Li on 2026/5/30.
//

import SwiftUI

struct MapSceneView: View {
    var runtime: MapSceneRuntime

    #if os(visionOS)
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    #endif

    @Environment(PlaySession.self) private var playSession

    @State private var actionBarHeight: CGFloat = 0
    @State private var presentedMenuItem: MenuItem?

    var body: some View {
        MapHUDViewport { size in scene(in: size) }
    }

    private func scene(in size: CGSize) -> some View {
        let isWidescreen = size.width >= 640
        let inset: CGFloat = size.width < 360 ? 8 : 16
        let chatWidth = isWidescreen ? (size.width >= 780 ? 360.0 : 280.0) : max(0, size.width - 2 * inset)

        return ZStack {
            #if os(visionOS)
            Color.clear
                .onAppear {
                    Task {
                        await openImmersiveSpace(id: GameSession.immersiveSpaceID)
                    }
                }
                .onDisappear {
                    Task {
                        await dismissImmersiveSpace()
                    }
                }
            #elseif os(iOS)
            MapView(runtime: runtime, isWidescreen: isWidescreen)
                .ignoresSafeArea(.container)
            #else
            MapView(runtime: runtime)
            #endif
        }
        .frame(width: size.width, height: size.height)
        .overlay(alignment: .bottomLeading) {
            #if os(macOS)
            ChatBoxView()
                .frame(width: 440)
                .hudObstacle()
            #endif
        }
        .overlay(alignment: .bottomTrailing) {
            if isWidescreen {
                actionBar
                    .hudObstacle()
                    .frame(maxWidth: size.width - chatWidth - 2 * inset, alignment: .trailing)
                    .padding(.trailing, inset)
                    .padding(.bottom, 16)
            }
        }
        .overlay(alignment: .bottom) {
            if !isWidescreen {
                actionBar
                    .hudObstacle()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, inset)
                    .padding(.bottom, ChatBoxView.contentHeight(for: .compact) + 8)
            }
        }
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                BasicInfoView(character: playSession.character, status: playSession.playerStatus)

                MenuView { item in
                    if item == presentedMenuItem {
                        presentedMenuItem = nil
                    } else {
                        presentedMenuItem = item
                    }
                }
            }
            .hudObstacle()
        }
        .overlay(alignment: .topTrailing) {
            VStack(alignment: .trailing, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    GameImageButton("basic_interface/nc_cashshop.bmp") {
                        presentedMenuItem = presentedMenuItem == .cashShop ? nil : .cashShop
                    }
                    .frame(width: 43, height: 45)
                    .accessibilityLabel("Cash Shop")
                    MinimapView(scene: runtime.scene)
                }
                .hudObstacle()

                StatusIconBarView(statusChanges: playSession.statusChanges)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, 16)
            .padding(.trailing, 16)
            .padding(.bottom, statusIconBarBottomPadding(isWidescreen: isWidescreen))
        }
        .overlay {
            #if os(iOS)
            ChatBoxView()
                .frame(width: chatWidth)
                .hudObstacle()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: isWidescreen ? .bottomLeading : .bottom)
            #endif
        }
        .overlayPreferenceValue(HUDObstacleKey.self) { obstacles in
            GeometryReader { viewport in
                let frames = obstacles.map { viewport[$0] }
                if let slot = questTrackerSlot(in: viewport.size, obstacles: frames) {
                    QuestTrackerView(quests: Array(playSession.quests.values), ui: playSession.questUI)
                        .frame(width: slot.width, height: slot.height, alignment: .topLeading)
                        .clipped()
                        .position(x: slot.midX, y: slot.midY)
                }
            }
            .allowsHitTesting(false)
        }
        .overlay(alignment: .center) {
            if let item = presentedMenuItem {
                switch item {
                case .status:
                    StatusView(status: playSession.playerStatus) {
                        presentedMenuItem = nil
                    }
                case .equipment:
                    EquipmentView {
                        presentedMenuItem = nil
                    }
                case .inventory:
                    InventoryView(inventory: playSession.inventory) {
                        presentedMenuItem = nil
                    }
                case .skill:
                    SkillListView(skillList: playSession.skillList) {
                        presentedMenuItem = nil
                    }
                case .party:
                    PartyView { presentedMenuItem = nil }
                case .cashShop:
                    CashShopView { presentedMenuItem = nil }
                case .quest:
                    QuestLogView(quests: Array(playSession.quests.values), ui: playSession.questUI, setActive: playSession.setQuestActive) {
                        presentedMenuItem = nil
                    }
                case .worldMap:
                    WorldMapView(currentMapName: runtime.scene.mapName) {
                        presentedMenuItem = nil
                    }
                case .options:
                    OptionsView(isPlayerDead: runtime.scene.state.isPlayerDead) {
                        presentedMenuItem = nil
                    }
                }
            }
        }
        .overlay {
            if presentedMenuItem == nil || presentedMenuItem == .quest {
                QuestDetailView(quests: Array(playSession.quests.values), ui: playSession.questUI)
            }
        }
        .overlay(alignment: .center) {
            if let dialog = playSession.dialog {
                NPCDialogView(dialog: dialog)
            }
            if let warpList = playSession.warpList {
                WarpListView(warpList: warpList)
            }
            if let npcShop = playSession.npcShop {
                NPCShopView(shop: npcShop)
            }
            if playSession.dealSelectionNPCID != nil {
                NPCShopDealTypeView()
            }
            if let storage = playSession.storage {
                StorageView(storage: storage)
            }
        }
        .onChange(of: playSession.examAdmissions) { _, _ in
            if playSession.questUI.selectedQuestID == 4011 {
                playSession.questUI.selectedQuestID = nil
                if presentedMenuItem == .quest { presentedMenuItem = nil }
            }
        }
        .onChange(of: runtime.scene.state.isPlayerDead) { _, newValue in
            if newValue {
                presentedMenuItem = .options
            } else if presentedMenuItem == .options {
                presentedMenuItem = nil
            }
        }
        .onChange(of: playSession.storage != nil) { _, isStorageOpen in
            if isStorageOpen {
                presentedMenuItem = nil
            }
        }
    }

    private var actionBar: some View {
        ActionBarView(
            selectedTargetType: runtime.scene.state.selectedTargetType,
            onTargetAction: {
                runtime.scene.performTargetAction()
            },
            onSelectNextTarget: {
                runtime.selectNextTarget()
            },
            onDeselectTarget: {
                runtime.scene.selectTarget(nil)
            },
            onPickup: {
                runtime.scene.pickUpNearestItem()
            },
            onSit: {
                runtime.scene.toggleSit()
            },
            onShortcut: { shortcut in
                playSession.useShortcut(shortcut)
            }
        )
        .onGeometryChange(for: CGFloat.self) { geometryProxy in
            geometryProxy.size.height
        } action: { height in
            actionBarHeight = height
        }
    }

    private func statusIconBarBottomPadding(isWidescreen: Bool) -> CGFloat {
        if isWidescreen {
            16 + actionBarHeight + 8
        } else {
            ChatBoxView.contentHeight(for: .compact) + 8 + actionBarHeight + 8
        }
    }
}

struct HUDObstacleKey: PreferenceKey {
    static var defaultValue: [Anchor<CGRect>] { [] }

    static func reduce(value: inout [Anchor<CGRect>], nextValue: () -> [Anchor<CGRect>]) {
        value += nextValue()
    }
}

extension View {
    func hudObstacle() -> some View {
        anchorPreference(key: HUDObstacleKey.self, value: .bounds) { [$0] }
    }
}
