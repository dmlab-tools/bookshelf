import AppKit
import Foundation
import LibraryCore

@MainActor
final class LibraryStore: ObservableObject {
    enum State: Equatable {
        case empty
        case loading(String)
        case ready
        case failed(String)
    }

    @Published private(set) var state: State = .empty
    @Published private(set) var folder: URL?
    @Published private(set) var library: Library?

    @Published var query = "" { didSet { scheduleSearch() } }
    @Published var scope: SearchScope = .all { didSet { scheduleSearch() } }
    @Published var language = "" { didSet { scheduleSearch() } }
    @Published private(set) var results: [Book] = []
    @Published private(set) var truncated = false
    @Published private(set) var searching = false

    private var searchTask: Task<Void, Never>?
    private let folderKey = "libraryFolder"

    var collectionName: String { library?.name ?? "" }
    var bookCount: Int { library?.books.count ?? 0 }
    var languages: [(code: String, count: Int)] { library?.languages ?? [] }

    init() {
        if let path = UserDefaults.standard.string(forKey: folderKey) {
            open(URL(fileURLWithPath: path))
        }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Open")
        panel.message = String(localized: "Choose the library folder (it must contain the .inpx file and the zip archives)")
        if let folder { panel.directoryURL = folder }
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    func reload() { if let folder { open(folder) } }

    func open(_ folder: URL) {
        self.folder = folder
        guard FileManager.default.fileExists(atPath: folder.path) else {
            state = .failed(String(localized: "The folder isn’t available: \(folder.path)\nThe disk may not be connected."))
            return
        }
        state = .loading(String(localized: "Reading the catalog…"))
        library = nil
        results = []
        let key = folderKey
        Task.detached(priority: .userInitiated) {
            do {
                let lib = try Library(folder: folder) { msg in
                    Task { @MainActor in if case .loading = self.state { self.state = .loading(msg) } }
                }
                await MainActor.run {
                    self.library = lib
                    self.state = .ready
                    UserDefaults.standard.set(folder.path, forKey: key)
                    self.scheduleSearch(immediately: true)
                }
            } catch {
                await MainActor.run { self.state = .failed("\(error)") }
            }
        }
    }

    func scheduleSearch(immediately: Bool = false) {
        guard state == .ready, let books = library?.books else { return }
        searchTask?.cancel()
        let query = self.query, scope = self.scope, lang = self.language
        searching = true
        searchTask = Task.detached(priority: .userInitiated) {
            if !immediately { try? await Task.sleep(nanoseconds: 180_000_000) }
            if Task.isCancelled { return }
            let (found, more) = BookSearch.search(books, query: query, scope: scope, lang: lang)
            if Task.isCancelled { return }
            await MainActor.run {
                self.results = found
                self.truncated = more
                self.searching = false
            }
        }
    }

    func showAuthor(_ book: Book) {
        scope = .author
        query = book.authors.components(separatedBy: ", ").first ?? book.authors
    }

    func showSeries(_ book: Book) {
        scope = .series
        query = book.series
    }
}
