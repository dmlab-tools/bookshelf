#!/bin/zsh
# Builds dist/Bookshelf.app.
set -e
cd "$(dirname "$0")"
# Universal binary: Apple Silicon and Intel.
swift build -c release --arch arm64 --arch x86_64
APP="dist/Bookshelf.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/apple/Products/Release/Bookshelf "$APP/Contents/MacOS/Bookshelf"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
# UI languages: English (the strings in the code) and Russian. macOS picks one.
cp -R Resources/*.lproj "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Bookshelf</string>
    <key>CFBundleIdentifier</key><string>io.github.dmlab-tools.bookshelf</string>
    <key>CFBundleName</key><string>Bookshelf</string>
    <key>CFBundleDisplayName</key><string>Bookshelf</string>
    <key>LSHasLocalizedDisplayName</key><true/>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.1</string>
    <key>CFBundleVersion</key><string>2</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key><array><string>en</string><string>ru</string></array>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.books</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --deep -s - "$APP"
echo "Done: $(pwd)/$APP"
