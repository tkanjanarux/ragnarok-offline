import SwiftUI

struct CompanionView: View {
    var close: () -> Void
    @Environment(PlaySession.self) private var session
    @State private var selected: UInt32?
    @State private var details: UInt32?
    @State private var settings = false
    @State private var release: UInt32?
    @State private var feedback = ""
    @State private var stopInput = ""
    @State private var retreatInput = ""

    private var state: CompanionState { session.companions }
    private var row: CompanionProfile? { state.profiles.first { $0.id == selected } }
    private var enabled: Bool { state.ready && state.available && !state.pending && !state.transferPending }
    private var mode: String { state.teamMode ?? (state.nearbyHunt == true ? "nearby" : "assist") }
    private func send(_ command: String) { session.companionCommand(command) }

    var body: some View {
        GeometryReader { viewport in
            let height = min(396, max(294, viewport.size.height - 24))
            if let release {
                ClassicGamePanel(title: "Release Companion", width: 300, height: 132, tracksCompanion: true, onClose: { self.release = nil }) {
                    VStack(spacing: 12) {
                        Text("Permanently release \(state.profiles.first(where: { $0.id == release })?.name ?? "companion")? Its level and EXP will be lost.")
                            .multilineTextAlignment(.center)
                        HStack {
                            Button("Cancel") { self.release = nil }
                            Button("Release") {
                                send("retire \(release) confirm")
                                self.release = nil
                            }.disabled(!enabled)
                        }.buttonStyle(.game).frame(height: 30)
                    }.padding(10)
                }
            } else if let details {
                CompanionEquipmentView(profileID: details, close: { self.details = nil })
            } else if settings {
                ClassicGamePanel(title: "Companion Settings", width: 344, height: min(height, 350), tracksCompanion: true, onClose: { settings = false }) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            if let row {
                                Text(row.name).font(.game(weight: .bold))
                                if let build = row.build {
                                    choice("Build", value: companionBuildTitle(build), options: row.buildChoices, label: companionBuildTitle) { send("build \(row.id) \($0)") }.disabled(row.active)
                                    if row.active { Text("Reserve to change build.").font(.game(size: 10)) }
                                }
                                choice("Preset", value: row.preset.capitalized, options: ["custom","protect","assist","conserve"], label: { $0.capitalized }) { send("preset \(row.id) \($0)") }
                                if let rented = row.rented, [7,11].contains(row.job) || rented {
                                    let bird = [1,7].contains(row.job) ? "Peco Peco" : "Falcon"
                                    if rented, let on = row.birdOn {
                                        let peco = bird == "Peco Peco"
                                        let label = peco ? (on ? "Mounted · Dismount" : "On foot · Mount Peco") : (on ? "Falcon active · Rest" : "Falcon resting · Call")
                                        Button(label) { send("\(peco ? "ride" : "falcon") \(row.id) \(on ? "off" : "on")") }
                                            .buttonStyle(.game).frame(height: 30)
                                    } else {
                                    Button(rented ? "\(bird) · Rented" : "Rent \(bird) · 2,500 Z") { send("rent \(row.id)") }
                                        .buttonStyle(.game).frame(height: 30).disabled(rented || row.active)
                                    }
                                }
                                Divider()
                            }
                            Text("Team").font(.game(weight: .bold))
                            if let voice = state.voice {
                                choice("Speech", value: voice.capitalized, options: ["off","quiet","normal","chatty"], label: { $0.capitalized }) { send("talk "+$0) }
                            }
                            if state.teamMode != nil {
                                choice("Mob limit", value: String(state.mobCap), options: (1...10).map { String($0) }, label: { $0 }) { send("mob "+$0) }
                                threshold("Pause pulling at HP", verb: "stop", input: $stopInput)
                                threshold("Retreat at HP", verb: "retreat", input: $retreatInput)
                            }
                            if !feedback.isEmpty { Text(feedback).font(.game(size: 10)) }
                        }.padding(10).disabled(!enabled)
                    }
                }
            } else {
                ClassicGamePanel(title: "Companions", width: 356, height: height, tracksCompanion: true, onClose: close) {
                    VStack(spacing: 3) {
                        HStack {
                            Text("Active \(state.activeCount)/\(CompanionState.activeLimit)").font(.game(weight: .bold))
                            Spacer()
                            Menu("Manage ▾") {
                                Menu("Recruit") {
                                    ForEach(["Swordman","Acolyte","Mage","Archer"], id: \.self) { job in
                                        Button(job) { send("recruit "+(["Swordman":"knight","Acolyte":"priest","Mage":"wizard","Archer":"hunter"][job] ?? "")) }
                                    }
                                }.disabled(!enabled || state.profiles.count >= 9)
                                Button("Create Party") { send("party") }.disabled(!enabled || !session.party.members.isEmpty)
                                Button("Refresh") { send("list") }.disabled(state.pending)
                                Button("Release…") { release = row?.id }.disabled(!enabled || row?.active != false)
                            }
                            Text("\(state.profiles.count)/9").font(.game(size: 10)).frame(width: 36)
                        }.padding(.horizontal, 4).frame(height: 28)
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(state.profiles) { member in
                                    Button { selected = member.id } label: { memberRow(member) }.buttonStyle(.plain).accessibilityIdentifier("roster-\(member.id)")
                                    Divider()
                                }
                                if state.ready && state.profiles.isEmpty { Text("Manage ▸ Recruit").padding(10) }
                            }
                        }.border(Color.gameBoxBorder)
                        HStack(spacing: 3) {
                            action(row?.active == true ? "Reserve" : "Summon", row?.active == true ? "bench" : "summon", row == nil || (row?.active == false && state.activeCount >= CompanionState.activeLimit))
                            action("Follow","follow",row?.active != true)
                            action("Assist","assist",row?.active != true)
                            action("Stop","stop",row?.active != true || row?.mode == 3)
                        }.frame(height: 30)
                        HStack(spacing: 3) {
                            Button("Details") { details = selected }.disabled(row == nil || !enabled)
                            Button("Settings") { settings = true }.disabled(!enabled)
                            Menu {
                                Button("Assist") { send(state.teamMode != nil ? "teamoff" : "hunt off") }.disabled(mode == "assist")
                                if state.nearbyHunt != nil { Button("Nearby Hunt") { send("hunt on") }.disabled(mode != "assist") }
                                if state.teamMode != nil { Button("Mob") { send("mob on") }.disabled(mode != "assist") }
                            } label: { Text("Team · " + (mode == "nearby" ? "Hunt" : mode.capitalized) + " ▾") }
                            .disabled(!enabled || (state.teamMode == nil && state.nearbyHunt == nil))
                            if mode == "mob" || mode == "boss" { Button("Retreat") { send("retreat") }.disabled(!enabled) }
                        }.buttonStyle(.game).frame(height: 30)
                        if !feedback.isEmpty { Text(feedback).font(.game(size: 10)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading) }
                    }.padding(6)
                }
            }
        }
        .onChange(of: state.profiles, initial: true) {
            if !state.profiles.contains(where: { $0.id == selected }) { selected = state.profiles.first?.id }
        }
        .onChange(of: state.completedSequence) {
            if details == nil && (state.action != "list" || !state.available || !state.ready) { feedback = state.message }
        }
        .task {
            send("list")
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                if !state.pending && details == nil && release == nil { send("list") }
            }
        }
    }

    private func memberRow(_ member: CompanionProfile) -> some View {
        HStack(spacing: 7) {
            GameImage("renewalparty/icon_jobs_\(member.job)\(member.mode == 4 ? "_die" : "").bmp").frame(width: 26, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(member.name).font(.game(weight: .bold))
                Text([member.jobName, member.build.map(companionBuildTitle)].compactMap { $0 }.joined(separator: " · ")).font(.game(size: 10)).lineLimit(1)
            }
            Spacer(minLength: 2)
            VStack(alignment: .trailing, spacing: 2) {
                Text("Lv \(member.level)/\(member.jobLevel) · \(member.stateName)").font(.game(size: 10))
                if member.hp >= 0 && member.maxHP > 0 {
                    HPSPBarView(hp: min(Int(member.hp),Int(member.maxHP)), maxHp: Int(member.maxHP), sp: max(0,min(Int(member.sp),Int(member.maxSP))), maxSp: max(1,Int(member.maxSP)), objectType: .pc)
                        .accessibilityLabel("HP \(member.hp)/\(member.maxHP), SP \(member.sp)/\(member.maxSP)")
                }
            }
        }.padding(.horizontal, 6).frame(height: 44).background(member.id == selected ? Color(red: 0.82,green: 0.89,blue: 1) : Color.white).contentShape(Rectangle())
    }

    private func action(_ title: String, _ verb: String, _ disabled: Bool) -> some View {
        Button(title) { if let selected { send("\(verb) \(selected)") } }.buttonStyle(.game).disabled(disabled || !enabled)
    }

    private func choice(_ title: String, value: String, options: [String], label: (String) -> String, perform: @escaping (String) -> Void) -> some View {
        let labels = options.map(label)
        return HStack {
            Text(title)
            Spacer()
            Menu(value + " ▾") {
                ForEach(Array(options.indices), id: \.self) { i in Button(labels[i]) { perform(options[i]) } }
            }
        }.frame(height: 28)
    }

    private func threshold(_ title: String, verb: String, input: Binding<String>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("%", text: input).textFieldStyle(.roundedBorder).frame(width: 48)
            Button("Set") {
                if let value = Int(input.wrappedValue), (1...99).contains(value) { send("mob \(verb) \(value)") }
            }.buttonStyle(.game).frame(width: 44, height: 28)
                .disabled(!(1...99).contains(Int(input.wrappedValue) ?? 0))
        }
    }
}

func companionBuildTitle(_ key: String) -> String {
    ["sword":"Two-Handed Sword","spear":"Spear","double":"Double Strafe","falcon":"Falcon","support":"Full Support","battle":"Battle Priest","bolt":"Bolt","storm":"Storm Gust","vermilion":"Lord of Vermilion","pillar":"Fire Pillar"][key] ?? key
}
