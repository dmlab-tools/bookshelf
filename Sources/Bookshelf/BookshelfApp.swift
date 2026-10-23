import LibraryCore
import SwiftUI

@main
struct BookshelfApp: App {
    @StateObject private var store = LibraryStore()
    @StateObject private var exporter = Exporter()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(exporter)
                .onAppear { exporter.store = store }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Library…") { store.chooseFolder() }
                    .keyboardShortcut("o")
                Button("Reload Catalog") { store.reload() }
                    .keyboardShortcut("r")
                    .disabled(store.folder == nil)
            }
        }
    }
}
