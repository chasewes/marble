import SwiftUI


enum GameChoice: String, CaseIterable, Identifiable {
case chase, jared
var id: String { rawValue }
var title: String { self == .chase ? "Chase’s Game" : "Jared’s Game" }
}


struct RootView: View {
@StateObject private var tracker = HeadTracker()
@State private var selection: GameChoice? = nil


var body: some View {
NavigationStack {
VStack(spacing: 16) {
Picker("Game", selection: $selection) {
Text("None").tag(GameChoice?.none)
ForEach(GameChoice.allCases) { choice in
Text(choice.title).tag(GameChoice?.some(choice))
}
}
.pickerStyle(.segmented)
.padding(.horizontal)


Group {
switch selection {
case .chase?: ChaseDebugGameView().environmentObject(tracker)
case .jared?: JaredDebugGameView().environmentObject(tracker)
case nil: Placeholder()
}
}
.frame(maxWidth: .infinity, maxHeight: .infinity)
}
.navigationTitle("Head‑Play (MVP)")
}
.onAppear { tracker.start() }
.onDisappear { tracker.stop() }
}
}


private struct Placeholder: View {
var body: some View {
VStack(spacing: 12) {
Image(systemName: "headphones")
.font(.system(size: 48))
Text("Select a game to view AirPods motion data.")
.foregroundStyle(.secondary)
}
.frame(maxWidth: .infinity, maxHeight: .infinity)
}
}
