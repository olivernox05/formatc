import SwiftUI

@main
struct FormatCApp: App {
    @State private var tools = ToolCheck()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(tools)
                .frame(minWidth: 720, minHeight: 460)
                .onAppear { tools.refresh() }
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }
}
