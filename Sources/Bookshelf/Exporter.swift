import AppKit
import LibraryCore
import SwiftUI

/// Saves books out of the archives as .fb2 files.
@MainActor
final class Exporter: ObservableObject {
    @Published private(set) var busy = false
    @Published private(set) var status: String?
    @AppStorage("exportNaming") var naming: ExportNaming = .authorTitle
    @AppStorage("exportFolder") private var lastFolder = ""

    weak var store: LibraryStore?

    func export(_ books: [Book]) {
        guard !books.isEmpty, !busy else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Save Here")
        panel.message = books.count == 1 ? String(localized: "Where to save “\(books[0].title)”?")
            : String(localized: "Where to save \(books.count) books?")
        if !lastFolder.isEmpty { panel.directoryURL = URL(fileURLWithPath: lastFolder) }
        let picker = NSPopUpButton()
        for n in ExportNaming.allCases {
            picker.addItem(withTitle: n.label)
            picker.lastItem?.representedObject = n.rawValue
        }
        picker.selectItem(at: ExportNaming.allCases.firstIndex(of: naming) ?? 0)
        let label = NSTextField(labelWithString: String(localized: "File name:"))
        let accessory = NSStackView(views: [label, picker])
        accessory.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        panel.accessoryView = accessory
        panel.isAccessoryViewDisclosed = true
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        if let raw = picker.selectedItem?.representedObject as? String, let n = ExportNaming(rawValue: raw) { naming = n }
        lastFolder = dir.path
        write(books, to: dir, naming: naming) { urls in
            if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
        }
    }

    /// Extracts books to a temporary folder and opens them in the default fb2 reader.
    func open(_ books: [Book]) {
        guard !books.isEmpty, !busy else { return }
        if books.count > 10 {
            let a = NSAlert()
            a.messageText = String(localized: "Open \(books.count) books?")
            a.addButton(withTitle: String(localized: "Open"))
            a.addButton(withTitle: String(localized: "Cancel"))
            guard a.runModal() == .alertFirstButtonReturn else { return }
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Bookshelf", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        write(books, to: dir, naming: .authorTitle, quiet: true) { urls in
            guard let first = urls.first else { return }
            if NSWorkspace.shared.urlForApplication(toOpen: first) == nil {
                let a = NSAlert()
                a.messageText = String(localized: "No App Can Open fb2 Files")
                a.informativeText = String(localized: "Install a reader that opens fb2 files, or use Export. The file was saved to a temporary folder.")
                a.addButton(withTitle: String(localized: "Show in Finder"))
                a.addButton(withTitle: String(localized: "OK"))
                if a.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.activateFileViewerSelecting(urls) }
                return
            }
            for u in urls { NSWorkspace.shared.open(u) }
        }
    }

    private func write(_ books: [Book], to dir: URL, naming: ExportNaming, quiet: Bool = false,
                       done: @escaping ([URL]) -> Void) {
        guard let library = store?.library else { return }
        busy = true
        status = books.count > 1 ? String(localized: "Saving \(0) of \(books.count)…") : nil
        Task.detached(priority: .userInitiated) {
            var urls: [URL] = []
            var errors: [String] = []
            for (i, b) in books.enumerated() {
                do {
                    let data = try library.data(for: b)
                    let url = Exporter.uniqueURL(dir.appendingPathComponent(naming.fileName(for: b)), replacing: quiet)
                    try data.write(to: url)
                    urls.append(url)
                } catch {
                    errors.append("\(b.title): \(error)")
                }
                if books.count > 1 && (i % 10 == 9 || i == books.count - 1) {
                    let n = i + 1
                    await MainActor.run { self.status = String(localized: "Saving \(n) of \(books.count)…") }
                }
            }
            let (saved, failures) = (urls, errors)
            await MainActor.run {
                let urls = saved, errors = failures
                self.busy = false
                self.status = quiet || urls.isEmpty ? nil : String(localized: "Books saved: \(urls.count)")
                if !errors.isEmpty {
                    let a = NSAlert()
                    a.messageText = String(localized: "Couldn’t save \(errors.count) of \(books.count)")
                    a.informativeText = errors.prefix(10).joined(separator: "\n")
                    a.runModal()
                }
                done(urls)
            }
        }
    }

    /// "Name.fb2" → "Name (2).fb2" if the file exists, unless replacing is allowed.
    nonisolated static func uniqueURL(_ url: URL, replacing: Bool) -> URL {
        let fm = FileManager.default
        if replacing || !fm.fileExists(atPath: url.path) { return url }
        let base = url.deletingPathExtension().lastPathComponent, ext = url.pathExtension
        var n = 2
        while true {
            let u = url.deletingLastPathComponent().appendingPathComponent("\(base) (\(n)).\(ext)")
            if !fm.fileExists(atPath: u.path) { return u }
            n += 1
        }
    }
}
