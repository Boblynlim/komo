#!/bin/bash
set -e

APP_NAME="komo"
BUILD_DIR=".build/arm64-apple-macosx/debug"
BUNDLE_DIR="build/${APP_NAME}.app"

# CEF SDK (downloaded separately; see cef-prototype/README.md).
CEF_DIST="/Users/jazulynn/src/tries/browser/cef-proof/cef"
CEF_FRAMEWORK="$CEF_DIST/Release/Chromium Embedded Framework.framework"
HELPER_SRC="$CEF_DIST/build/tests/swiftcef/Release/swiftcef Helper.app"

# Build first
swift build

# Create .app bundle structure
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR/Contents/MacOS"
mkdir -p "$BUNDLE_DIR/Contents/Resources"
mkdir -p "$BUNDLE_DIR/Contents/Frameworks"

# Copy executable
cp "$BUILD_DIR/$APP_NAME" "$BUNDLE_DIR/Contents/MacOS/$APP_NAME"

# Copy resources if they exist
if [ -d "$BUILD_DIR/${APP_NAME}_komo.bundle" ]; then
    cp -R "$BUILD_DIR/${APP_NAME}_komo.bundle" "$BUNDLE_DIR/Contents/Resources/"
fi

# --- Chromium engine (CEF) ---
echo "Bundling Chromium framework + helper…"
cp -R "$CEF_FRAMEWORK" "$BUNDLE_DIR/Contents/Frameworks/"

# Helper subprocess app (reuse the prebuilt one, renamed to "komo Helper").
cp -R "$HELPER_SRC" "$BUNDLE_DIR/Contents/Frameworks/komo Helper.app"
mv "$BUNDLE_DIR/Contents/Frameworks/komo Helper.app/Contents/MacOS/swiftcef Helper" \
   "$BUNDLE_DIR/Contents/Frameworks/komo Helper.app/Contents/MacOS/komo Helper"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable 'komo Helper'" \
   "$BUNDLE_DIR/Contents/Frameworks/komo Helper.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.komo.browser.helper" \
   "$BUNDLE_DIR/Contents/Frameworks/komo Helper.app/Contents/Info.plist" 2>/dev/null || true

# Create Info.plist
cat > "$BUNDLE_DIR/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>komo</string>
    <key>CFBundleIdentifier</key>
    <string>com.komo.browser</string>
    <key>CFBundleName</key>
    <string>komo</string>
    <key>CFBundleDisplayName</key>
    <string>komo</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <!-- Required by CEF: the NSApplication must conform to CefAppProtocol. -->
    <key>NSPrincipalClass</key>
    <string>KomoCEFApplication</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
</dict>
</plist>
PLIST

# --- Sign (ad-hoc, dev) — inner components first, then the app ---
echo "Signing…"
codesign --force --sign - --timestamp=none \
    "$BUNDLE_DIR/Contents/Frameworks/Chromium Embedded Framework.framework" 2>/dev/null
codesign --force --deep --sign - --timestamp=none \
    "$BUNDLE_DIR/Contents/Frameworks/komo Helper.app" 2>/dev/null
codesign --force --deep --sign - --timestamp=none "$BUNDLE_DIR" 2>/dev/null

echo "✓ Built ${BUNDLE_DIR}"
echo "  Run with: open build/komo.app"
