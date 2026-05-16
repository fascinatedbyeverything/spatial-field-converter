import SwiftUI

@main
struct SpatialFieldConverterApp: App {

    @StateObject private var libraryIndex: R2CatalogIndex = {
        R2CatalogIndex(stagingDirectory: PreferencesStore.stagingDirectory)
    }()

    var body: some Scene {
        WindowGroup("Spatial Field Converter") {
            ContentView()
                .environmentObject(libraryIndex)
                .frame(minWidth: 720, minHeight: 480)
                .task { await libraryIndex.refresh() }
        }
        .windowResizability(.contentSize)
    }
}
