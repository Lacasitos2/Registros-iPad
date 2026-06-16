import SwiftUI

@main
struct RegistrosIpadApp: App {
    @StateObject private var store = ClassroomStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
