import SwiftUI

@main
struct SpatialFieldConverterApp: App {
    var body: some Scene {
        WindowGroup("Spatial Field Converter") {
            ContentView()
                .frame(minWidth: 720, minHeight: 480)
        }
        .windowResizability(.contentSize)
    }
}
