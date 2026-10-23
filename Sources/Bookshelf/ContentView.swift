import AppKit
import LibraryCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var exporter: Exporter

    var body: some View {
        Group {
            switch store.state {
            case .empty:
                Placeholder(icon: "books.vertical", title: String(localized: "No Library Selected"),
                            text: String(localized: "Choose the folder that contains the .inpx file and the zip archives with books.")) {
                    Button("Choose Folder…") { store.chooseFolder() }.keyboardShortcut(.defaultAction)
                }
            case .loading(let message):
                VStack(spacing: 12) {
                    ProgressView()
                    Text(message).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                Placeholder(icon: "exclamationmark.triangle", title: String(localized: "Can’t Open Library"), text: message) {
                    HStack {
                        Button("Try Again") { store.reload() }
                        Button("Choose Another Folder…") { store.chooseFolder() }.keyboardShortcut(.defaultAction)
                    }
                }
            case .ready:
                BrowserView()
            }
        }
        .frame(minWidth: 900, minHeight: 520)
        .navigationTitle(store.collectionName.isEmpty ? String(localized: "Bookshelf") : store.collectionName)
    }
}

struct Placeholder<Actions: View>: View {
    let icon: String
    let title: String
    let text: String
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 44)).foregroundStyle(.secondary)
            Text(title).font(.title2.weight(.semibold))
            Text(text).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 460)
            actions().padding(.top, 4)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension Book {
    var seriesSortKey: String { series.isEmpty ? "\u{10FFFF}" : series + String(format: "\u{1}%06d", seriesNo) }
    var sizeText: String { ByteCountFormatter.string(fromByteCount: size, countStyle: .file) }
    var languageName: String { Book.languageName(lang) }

    /// "ru" → "Russian", in the language the app runs in.
    static func languageName(_ code: String) -> String {
        guard !code.isEmpty else { return String(localized: "Not Specified") }
        let locale = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
        return locale.localizedString(forLanguageCode: code)?.capitalized(with: locale) ?? code
    }
}

struct BrowserView: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var exporter: Exporter
    @State private var selection = Set<Book.ID>()
    @State private var sortOrder: [KeyPathComparator<Book>] = []
    @State private var rows: [Book] = []

    private var selectedBooks: [Book] { rows.filter { selection.contains($0.id) } }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                table
                Divider()
                statusBar
            }
            .frame(minWidth: 560)

            DetailPane(books: selectedBooks)
                .frame(minWidth: 260, idealWidth: 320, maxWidth: 480)
        }
        .searchable(text: $store.query, placement: .toolbar, prompt: "Author, title or series")
        .searchScopes($store.scope) {
            ForEach(SearchScope.allCases) { Text($0.label).tag($0) }
        }
        .toolbar {
            ToolbarItemGroup {
                Picker("Language", selection: $store.language) {
                    Text("All Languages").tag("")
                    Divider()
                    ForEach(store.languages, id: \.code) { l in
                        Text(verbatim: "\(Book.languageName(l.code)) — \(l.count.formatted())").tag(l.code)
                    }
                }
                .frame(width: 190)
                .help("Show only books in this language")

                Button { exporter.export(selectedBooks) } label: {
                    Label("Export to fb2", systemImage: "square.and.arrow.up")
                }
                .disabled(selection.isEmpty || exporter.busy)
                .help("Save the selected books to a folder")
            }
        }
        .onChange(of: store.results) { _ in resort() }
        .onChange(of: sortOrder) { _ in resort() }
        .onAppear { resort() }
    }

    private var table: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Author", value: \.authors) { Text($0.authors).help($0.authors) }
                .width(min: 120, ideal: 200)
            TableColumn("Title", value: \.title) { Text($0.title).help($0.title) }
            .width(min: 160, ideal: 280)
            TableColumn("Series", value: \.seriesSortKey) { Text($0.seriesDisplay).help($0.seriesDisplay) }
                .width(min: 80, ideal: 160)
            TableColumn("Genre") { Text($0.genreNames).help($0.genreNames) }
                .width(min: 80, ideal: 140)
            TableColumn("Language", value: \.lang) { Text($0.languageName) }
                .width(min: 60, ideal: 90)
            TableColumn("Size", value: \.size) { Text($0.sizeText).monospacedDigit() }
                .width(70)
            TableColumn("Added", value: \.date) { Text($0.date).monospacedDigit() }
                .width(80)
        }
        .contextMenu(forSelectionType: Book.ID.self) { ids in
            let books = rows.filter { ids.contains($0.id) }
            if !books.isEmpty {
                Button("Open") { exporter.open(books) }
                Button("Export to fb2…") { exporter.export(books) }
                if books.count == 1, let b = books.first {
                    Divider()
                    Button("All Books by This Author") { store.showAuthor(b) }
                    if !b.series.isEmpty { Button("Entire Series “\(b.series)”") { store.showSeries(b) } }
                }
            }
        } primaryAction: { ids in
            exporter.open(rows.filter { ids.contains($0.id) })
        }
        .overlay {
            if rows.isEmpty && !store.searching {
                if store.query.isEmpty && store.language.isEmpty {
                    Placeholder(icon: "magnifyingglass", title: String(localized: "Search Books"),
                                text: String(localized: "Books in the library: \(store.bookCount.formatted()). Start typing an author’s name, a title or a series. Words can go in any order.")) {}
                } else {
                    Placeholder(icon: "questionmark.folder", title: String(localized: "No Results"),
                                text: String(localized: "Try changing the search or the filters.")) {}
                }
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            Text("Books in library: \(store.bookCount.formatted())")
            if !rows.isEmpty {
                Text("Found: \(rows.count.formatted() + (store.truncated ? "+" : ""))")
            }
            if store.truncated {
                Text("Showing the first \(BookSearch.resultLimit.formatted()) — refine your search").foregroundStyle(.orange)
            }
            Spacer()
            if let status = exporter.status { Text(status).lineLimit(1) }
            if !selection.isEmpty { Text("Selected: \(selection.count)") }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    private func resort() {
        rows = sortOrder.isEmpty ? store.results : store.results.sorted(using: sortOrder)
        let visible = Set(rows.map(\.id))
        selection = selection.filter { visible.contains($0) }
    }
}

struct DetailPane: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var exporter: Exporter
    let books: [Book]

    var body: some View {
        Group {
            if books.count == 1, let b = books.first {
                BookDetail(book: b).id(b.id)
            } else if books.count > 1 {
                Placeholder(icon: "books.vertical", title: String(localized: "Books selected: \(books.count)"),
                            text: ByteCountFormatter.string(fromByteCount: books.reduce(0) { $0 + $1.size }, countStyle: .file)) {
                    Button("Export to fb2…") { exporter.export(books) }.disabled(exporter.busy)
                }
            } else {
                Placeholder(icon: "book.closed", title: "", text: String(localized: "Select a book to see its description.")) {}
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

struct BookDetail: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var exporter: Exporter
    let book: Book
    @State private var info: FB2Info?
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let data = info?.cover, let img = NSImage(data: data) {
                    Image(nsImage: img)
                        .resizable().aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 300)
                        .shadow(radius: 3, y: 1)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(book.title).font(.title3.weight(.semibold)).textSelection(.enabled)
                    Button(book.authors.isEmpty ? String(localized: "Unknown Author") : book.authors) { store.showAuthor(book) }
                        .buttonStyle(.link)
                        .help("Show all books by this author")
                    if !book.series.isEmpty {
                        Button(book.seriesDisplay) { store.showSeries(book) }
                            .buttonStyle(.link)
                            .help("Show the entire series")
                    }
                }

                HStack {
                    Button { exporter.export([book]) } label: { Label("Export", systemImage: "square.and.arrow.up") }
                    Button { exporter.open([book]) } label: { Label("Open", systemImage: "book") }
                }
                .disabled(exporter.busy)

                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                    row("Genre", book.genreNames)
                    row("Language", book.languageName)
                    if let info, !info.year.isEmpty { row("Year", info.year) }
                    if let info, !info.publisher.isEmpty { row("Publisher", info.publisher) }
                    row("Size", book.sizeText)
                    row("Added", book.date)
                    if book.rating > 0 { row("Rating", String(repeating: "★", count: book.rating) + String(repeating: "☆", count: max(0, 5 - book.rating))) }
                    row("File", "\(book.archive) / \(book.fileName)")
                }
                .font(.callout)

                if let info, !info.annotation.isEmpty {
                    Divider()
                    Text(info.annotation).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                } else if let error {
                    Text(error).foregroundStyle(.red).font(.callout)
                } else if info == nil {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task {
            guard let library = store.library else { return }
            let book = self.book
            let result: Result<FB2Info, Error> = await Task.detached(priority: .userInitiated) {
                Result { FB2.info(from: try library.data(for: book)) }
            }.value
            switch result {
            case .success(let i): info = i
            case .failure(let e): error = String(localized: "Can’t read the book: \(String(describing: e))")
            }
        }
    }

    @ViewBuilder private func row(_ k: LocalizedStringKey, _ v: String) -> some View {
        GridRow {
            Text(k).foregroundStyle(.secondary)
            Text(v).textSelection(.enabled)
        }
    }
}
