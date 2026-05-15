import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Text("Spatial Field Converter v0.1")
                .font(.title)
            Text("Drop a Zoom H8 .wav or SD card folder")
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
