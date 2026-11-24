//
//  OptionsView.swift
//  RagnarokGame
//
//  Created by Leon Li on 2025/10/16.
//

import SwiftUI

struct OptionsView: View {
    var isPlayerDead: Bool
    var onClose: () -> Void = {}

    @Environment(GameSession.self) private var gameSession
    @Environment(GameContext.self) private var gameContext
    @Environment(PlaySession.self) private var playSession
    @Environment(\.exitGame) private var exitGame

    @State private var settings: String?

    var body: some View {
        if let settings {
            GameSettingsView(section: settings) { self.settings = nil }
        } else {
        GameWindow {
            VStack(spacing: 3) {
                if isPlayerDead {
                    // esc_05a.bmp
                    Button {
                        playSession.resurrectInPlace()
                    } label: {
                        Text("Resurrection", bundle: #bundle)
                    }
                    .buttonStyle(.game)
                    .frame(width: 220, height: 44)
                    .disabled(!playSession.inventory.hasTokenOfSiegfried)

                    // esc_04a.bmp
                    Button {
                        playSession.returnToLastSavePoint()
                    } label: {
                        Text("Return to last save point", bundle: #bundle)
                    }
                    .buttonStyle(.game)
                    .frame(width: 220, height: 44)
                } else {
                    // esc_01a.bmp
                    Button {
                        playSession.returnToCharacterSelect()
                    } label: {
                        Text("Character Select", bundle: #bundle)
                    }
                    .buttonStyle(.game)
                    .frame(width: 220, height: 44)

                    // esc_06a.bmp
                    Button {
                        settings = "Settings"
                    } label: {
                        Text("Settings", bundle: #bundle)
                    }
                    .buttonStyle(.game)
                    .frame(width: 220, height: 44)

                    // esc_07a.bmp
                    Button {
                        settings = "Sound"
                    } label: {
                        Text("Sound", bundle: #bundle)
                    }
                    .buttonStyle(.game)
                    .frame(width: 220, height: 44)

                    // esc_08a.bmp
                    Button {
                        settings = "BM/Shortcut Settings"
                    } label: {
                        Text("BM/Shortcut Settings", bundle: #bundle)
                    }
                    .buttonStyle(.game)
                    .frame(width: 220, height: 44)

                    // esc_03a.bmp
                    Button {
                        playSession.requestExit()
                        gameSession.exitSession()
                        exitGame()
                    } label: {
                        Text("Exit", bundle: #bundle)
                    }
                    .buttonStyle(.game)
                    .frame(width: 220, height: 44)
                }
            }
            .padding(.vertical, 20)
        }
        .gameWindowTitle(Text(gameContext.messageStringTable.localizedMessageString(forID: 1483)))
        .gameWindowCloseAction(onClose)
        .frame(width: 280)
        }
    }
}

#Preview {
    OptionsView(isPlayerDead: false)
        .padding()
        .environment(GameSession.testing)
        .environment(GameContext.testing)
        .environment(PlaySession.testing)
}
