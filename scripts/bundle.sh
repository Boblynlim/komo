#!/bin/bash
set -e

APP_NAME="komo"
BUILD_DIR=".build/arm64-apple-macosx/debug"
BUNDLE_DIR="build/${APP_NAME}.app"

# Build first
swift build

# Create .app bundle structure
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR/Contents/MacOS"
mkdir -p "$BUNDLE_DIR/Contents/Resources"

# Copy executable
cp "$BUILD_DIR/$APP_NAME" "$BUNDLE_DIR/Contents/MacOS/$APP_NAME"

# Copy resources if they exist
if [ -d "$BUILD_DIR/${APP_NAME}_komo.bundle" ]; then
    cp -R "$BUILD_DIR/${APP_NAME}_komo.bundle" "$BUNDLE_DIR/Contents/Resources/"
fi

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
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
</dict>
</plist>
PLIST

echo "✓ Built ${BUNDLE_DIR}"
echo "  Run with: open build/komo.app"
