#!/bin/bash
set -e

APP_NAME="komo"
BUILD_DIR=".build/arm64-apple-macosx/release"
BUNDLE_DIR="build/${APP_NAME}.app"

# CEF SDK (downloaded separately; see cef-prototype/README.md).
CEF_DIST="/Users/jazulynn/src/tries/browser/cef-proof/cef"
CEF_FRAMEWORK="$CEF_DIST/Release/Chromium Embedded Framework.framework"
HELPER_SRC="$CEF_DIST/build/tests/swiftcef/Release/swiftcef Helper.app"

# Build first (optimized release)
swift build -c release

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

# All 5 dedicated helper subprocess apps (Renderer/GPU/Plugin/Alerts + base),
# renamed from the prebuilt swiftcef helpers. CEF auto-discovers them by name;
# the renderer needs its own helper, so a single generic one isn't enough.
HELPERS_SRC_DIR="$CEF_DIST/build/tests/swiftcef/Release"
for variant in "" " (GPU)" " (Plugin)" " (Renderer)" " (Alerts)"; do
    src="$HELPERS_SRC_DIR/swiftcef Helper${variant}.app"
    dst="$BUNDLE_DIR/Contents/Frameworks/komo Helper${variant}.app"
    cp -R "$src" "$dst"
    mv "$dst/Contents/MacOS/swiftcef Helper${variant}" "$dst/Contents/MacOS/komo Helper${variant}"
    /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable 'komo Helper${variant}'" "$dst/Contents/Info.plist"
    idsuffix=$(echo "$variant" | tr -dc '[:alpha:]' | tr '[:upper:]' '[:lower:]')
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.komo.browser.helper${idsuffix:+.$idsuffix}" "$dst/Contents/Info.plist" 2>/dev/null || true
done

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

# --- Sign (ad-hoc, dev) — deep sign the whole bundle, like the prototype ---
echo "Signing…"
codesign --force --deep --sign - "$BUNDLE_DIR" 2>/dev/null

echo "✓ Built ${BUNDLE_DIR}"
echo "  Run with: open build/komo.app"
