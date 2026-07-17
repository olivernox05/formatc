import SwiftUI

@main
struct FormatCApp: App {
    @State private var tools = ToolCheck()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(tools)
                // Explicit ideal size stops SwiftUI from resizing the
                // window when a sub-picker mode has taller/shorter
                // controls than the last one. Without it, `.contentSize`
                // resizability was pumping the window every mode swap
                // and pushing the header off the top of the screen.
                .frame(
                    minWidth: 900, idealWidth: 1000,
                    minHeight: 620, idealHeight: 700
                )
                .onAppear { tools.refresh() }
        }
        // Standard title bar (with room for the traffic lights) instead
        // of `.hiddenTitleBar`, so my "FormatC" header can't overlap the
        // close/minimise/maximise buttons.
        .windowResizability(.contentMinSize)
    }
}
