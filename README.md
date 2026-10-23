# Bookshelf

A native macOS app for browsing a local library of FB2 books stored in the INPX format: a folder with an
`.inpx` catalog and zip archives of books (the format used by MyHomeLib and similar catalogs).

- Instant search by author, title and series across hundreds of thousands of books, straight from the catalog.
- The selected book's annotation, cover, genres, series, year and publisher.
- Export one or many books to `.fb2` files, with a choice of file naming.
- English and Russian interface.

The app only reads the library: it never changes the catalog or the archives. It doesn't come with any books.

## Requirements

macOS 13 or later, Apple Silicon or Intel. Building needs Xcode or just the Command Line Tools (`xcode-select --install`).

## Building

```sh
./build-app.sh        # → dist/Bookshelf.app
```

Move `dist/Bookshelf.app` to Applications if you like. The app is signed ad hoc, so if macOS refuses to open a
copy brought from another Mac, right-click it and choose **Open**, or allow it in **System Settings → Privacy &
Security**.

## Using

On first launch, choose the library folder (the one with the `.inpx` file). It opens automatically next time.

- **Search**: the field in the top right corner. Words can go in any order; case and “ё” vs “е” don't matter.
  Below the field you can limit the search to the author, the title or the series.
- **Language**: the filter in the toolbar.
- **Details**: the selected book is shown on the right. The author and series links list all their books.
- **Export**: select one or more books (⌘- or ⇧-click), click **Export to fb2…** and choose a folder.
  File naming can be set in the folder dialog.
- Double-click a book to open it in the app set up for `.fb2` files.
- ⌘O opens another library, ⌘R reloads the catalog.

Books whose files are missing from the archives are not shown, so a library that has been trimmed down (some
archives removed, or books deleted from them) needs no catalog changes.

## Languages

The interface follows the system language: English or Russian. To pick a language for this app alone, use
**System Settings → General → Language & Region → Applications**.

English strings live in the code, the Russian translation is in `Resources/ru.lproj`. A new language needs a
`Resources/<code>.lproj` folder with `Localizable.strings` and `InfoPlist.strings`, and its code added to
`CFBundleLocalizations` in `build-app.sh`. Genre names are in `Sources/LibraryCore/Genres.swift`.

## Development

```sh
swift build
swift test
```

With only the Command Line Tools installed (no Xcode), `swift test` needs to be pointed at the testing framework:

```sh
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
L=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
swift test -Xswiftc -F$F -Xlinker -F$F -Xlinker -rpath -Xlinker $F -Xlinker -rpath -Xlinker $L
```

`RealLibraryTests` also run against a real library when it's given:
`BOOKSHELF_TEST_LIBRARY=/path/to/library swift test`.

Layout:

- `Sources/LibraryCore`: zip and INPX reading, the book model, search, FB2 parsing, genres.
- `Sources/Bookshelf`: the SwiftUI app.
- `Resources`: translations and the icon. `swift Resources/make-icon.swift` redraws the icon.

There are no dependencies: zip archives are read with a small built-in reader (memory-mapped, ZIP64-aware,
inflated with Apple's Compression framework).

## Credits

Written with [Claude Code](https://claude.com/claude-code).

## License

[MIT](LICENSE)
