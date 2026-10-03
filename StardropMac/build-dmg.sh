#!/usr/bin/env bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$DIR"

# Defaults
SKIP_BUILD=false
OPEN_AFTER=false
VERSION=""

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -s|--skip-build) SKIP_BUILD=true ;;
        -o|--open) OPEN_AFTER=true ;;
        -v|--version) VERSION="$2"; shift ;;
        -h|--help)
            echo "📦 StardropMac DMG Builder"
            echo ""
            echo "Usage: ./build-dmg.sh [options] [version]"
            echo ""
            echo "Options:"
            echo "  -s, --skip-build    Skip compiling Stardrop.app if already built"
            echo "  -o, --open          Mount and open the resulting DMG in Finder"
            echo "  -v, --version <ver> Specify version string (default: read from Info.plist)"
            echo "  -h, --help          Show this help message"
            echo ""
            echo "Examples:"
            echo "  ./build-dmg.sh"
            echo "  ./build-dmg.sh --skip-build --open"
            echo "  ./build-dmg.sh -v 1.10.4"
            exit 0
            ;;
        *)
            if [ -z "$VERSION" ]; then
                VERSION="$1"
            else
                echo "Unknown option: $1"
                exit 1
            fi
            ;;
    esac
    shift
done

APP_PATH="$DIR/build/Stardrop.app"

# 1. Build app bundle if missing or requested
if [ "$SKIP_BUILD" = false ] || [ ! -d "$APP_PATH" ]; then
    echo "🔨 Building Stardrop.app..."
    "$DIR/build-mac-app.sh"
fi

if [ ! -d "$APP_PATH" ]; then
    echo "❌ Error: App bundle not found at $APP_PATH"
    exit 1
fi

# 2. Determine version
INFO_PLIST="$APP_PATH/Contents/Info.plist"
if [ -z "$VERSION" ] && [ -f "$INFO_PLIST" ]; then
    VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST" 2>/dev/null || echo "1.10.4")
fi
VERSION="${VERSION:-1.10.4}"

VOLUME_NAME="Stardrop"
OUTPUT_DIR="$DIR/build"
DMG_NAME="Stardrop-${VERSION}-macOS.dmg"
FINAL_DMG="$OUTPUT_DIR/$DMG_NAME"
GENERIC_DMG="$OUTPUT_DIR/Stardrop.dmg"
TMP_DIR=$(mktemp -d /tmp/stardrop-dmg-staging.XXXXXX)
TMP_DMG="/tmp/stardrop-tmp-$$.dmg"
MOUNT_DIR="/Volumes/$VOLUME_NAME"

cleanup() {
    if [ -d "$MOUNT_DIR" ]; then
        hdiutil detach "$MOUNT_DIR" -force 2>/dev/null || true
    fi
    rm -rf "$TMP_DIR" "$TMP_DMG"
}
trap cleanup EXIT

echo "💿 Packaging DMG for Stardrop v$VERSION..."

# Ensure any previous mount with same volume name is detached
if [ -d "$MOUNT_DIR" ]; then
    hdiutil detach "$MOUNT_DIR" -force 2>/dev/null || true
fi

# 3. Create Staging Directory
mkdir -p "$TMP_DIR/.background"

# 4. Generate Retina Background Image
echo "🎨 Rendering DMG background..."
swift - << 'EOF' "$TMP_DIR/.background/background.png"
import Cocoa

let args = CommandLine.arguments
guard args.count > 1 else { exit(1) }
let outputPath = args[1]

let width: CGFloat = 540
let height: CGFloat = 360

let size = NSSize(width: width, height: height)
let image = NSImage(size: size)

image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { exit(1) }

// Background Gradient (Deep navy/slate)
let colorSpace = CGColorSpaceCreateDeviceRGB()
let startColor = NSColor(calibratedRed: 0.11, green: 0.13, blue: 0.19, alpha: 1.0).cgColor
let endColor = NSColor(calibratedRed: 0.17, green: 0.20, blue: 0.29, alpha: 1.0).cgColor
if let gradient = CGGradient(colorsSpace: colorSpace, colors: [startColor, endColor] as CFArray, locations: [0.0, 1.0]) {
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: height), end: CGPoint(x: 0, y: 0), options: [])
}

// Accent bar at top
let accentStart = NSColor(calibratedRed: 0.35, green: 0.55, blue: 0.95, alpha: 0.9).cgColor
let accentEnd = NSColor(calibratedRed: 0.65, green: 0.40, blue: 0.95, alpha: 0.9).cgColor
if let accentGradient = CGGradient(colorsSpace: colorSpace, colors: [accentStart, accentEnd] as CFArray, locations: [0.0, 1.0]) {
    ctx.saveGState()
    let topBar = CGRect(x: 0, y: height - 4, width: width, height: 4)
    ctx.addRect(topBar)
    ctx.clip()
    ctx.drawLinearGradient(accentGradient, start: CGPoint(x: 0, y: height), end: CGPoint(x: width, y: height), options: [])
    ctx.restoreGState()
}

// Title
let titleFont = NSFont.systemFont(ofSize: 22, weight: .bold)
let titleAttrs: [NSAttributedString.Key: Any] = [
    .font: titleFont,
    .foregroundColor: NSColor.white
]
let title = "Stardrop for macOS" as NSString
let titleSize = title.size(withAttributes: titleAttrs)
title.draw(at: CGPoint(x: (width - titleSize.width) / 2.0, y: height - 52), withAttributes: titleAttrs)

// Subtitle instruction
let subFont = NSFont.systemFont(ofSize: 13, weight: .medium)
let subAttrs: [NSAttributedString.Key: Any] = [
    .font: subFont,
    .foregroundColor: NSColor.white.withAlphaComponent(0.60)
]
let subtitle = "Drag and drop Stardrop into Applications" as NSString
let subSize = subtitle.size(withAttributes: subAttrs)
subtitle.draw(at: CGPoint(x: (width - subSize.width) / 2.0, y: 38), withAttributes: subAttrs)

// Center Arrow between Stardrop and Applications
ctx.saveGState()
ctx.setStrokeColor(NSColor(calibratedRed: 0.45, green: 0.65, blue: 1.0, alpha: 0.55).cgColor)
ctx.setFillColor(NSColor(calibratedRed: 0.45, green: 0.65, blue: 1.0, alpha: 0.55).cgColor)
ctx.setLineWidth(3.0)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)

let startX: CGFloat = 230
let endX: CGFloat = 310
let arrowY: CGFloat = 175

ctx.move(to: CGPoint(x: startX, y: arrowY))
ctx.addLine(to: CGPoint(x: endX, y: arrowY))
ctx.strokePath()

// Arrow head
ctx.beginPath()
ctx.move(to: CGPoint(x: endX - 12, y: arrowY + 8))
ctx.addLine(to: CGPoint(x: endX, y: arrowY))
ctx.addLine(to: CGPoint(x: endX - 12, y: arrowY - 8))
ctx.strokePath()

ctx.restoreGState()

image.unlockFocus()

if let tiff = image.tiffRepresentation,
   let rep = NSBitmapImageRep(data: tiff),
   let png = rep.representation(using: .png, properties: [:]) {
    try? png.write(to: URL(fileURLWithPath: outputPath))
}
EOF

# 5. Populate Staging Directory
echo "📋 Staging application and Applications link..."
cp -R "$APP_PATH" "$TMP_DIR/Stardrop.app"
ln -s /Applications "$TMP_DIR/Applications"

# Set volume icon if present
ICON_SRC="$DIR/../Stardrop/Assets/Stardrop.icns"
if [ -f "$ICON_SRC" ]; then
    cp "$ICON_SRC" "$TMP_DIR/.VolumeIcon.icns"
fi

# 6. Calculate Size & Create Temporary Read-Write DMG
APP_SIZE_MB=$(du -sm "$APP_PATH" | awk '{print $1}')
DMG_SIZE_MB=$((APP_SIZE_MB + 60))

echo "📦 Creating writable disk image (${DMG_SIZE_MB}MB)..."
hdiutil create -size "${DMG_SIZE_MB}m" \
    -volname "$VOLUME_NAME" \
    -srcfolder "$TMP_DIR" \
    -fs HFS+ \
    -format UDRW \
    -ov "$TMP_DMG" >/dev/null

# 7. Mount the temporary DMG to apply Finder styling
echo "🖥️  Mounting temporary disk image..."
ATTACH_OUT=$(hdiutil attach -readwrite -noverify -noautoopen "$TMP_DMG")
DEV_NAME=$(echo "$ATTACH_OUT" | egrep '^/dev/' | sed 1q | awk '{print $1}')

# Set custom volume icon attribute
if [ -f "$MOUNT_DIR/.VolumeIcon.icns" ]; then
    SetFile -c icnC "$MOUNT_DIR/.VolumeIcon.icns" 2>/dev/null || true
    SetFile -a C "$MOUNT_DIR" 2>/dev/null || true
fi

# 8. Apply AppleScript Finder Layout
echo "✨ Configuring Finder layout..."
osascript <<EOF 2>/dev/null || echo "⚠️ Finder layout customization skipped (running headless or no UI permission)"
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {400, 160, 940, 520}
        set viewOptions to the icon view options of container window
        set icon size of viewOptions to 120
        set arrangement of viewOptions to not arranged
        set position of item "Stardrop.app" of container window to {140, 185}
        set position of item "Applications" of container window to {400, 185}
        try
            set background picture of viewOptions to file ".background:background.png"
        end try
        close
        open
        update without registering applications
        delay 1
        close
    end tell
end tell
EOF

# Ensure changes are flushed
sync
hdiutil detach "$DEV_NAME" >/dev/null

# 9. Convert to Compressed Read-Only DMG (UDZO)
echo "🗜️  Compressing DMG..."
rm -f "$FINAL_DMG" "$GENERIC_DMG"
hdiutil convert "$TMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$FINAL_DMG" >/dev/null
cp "$FINAL_DMG" "$GENERIC_DMG"

# 10. Generate SHA256 Checksum
echo "🔒 Computing SHA256 checksum..."
(cd "$OUTPUT_DIR" && shasum -a 256 "$DMG_NAME" > "$DMG_NAME.sha256")
SHA256=$(cat "$FINAL_DMG.sha256" | awk '{print $1}')
FILE_SIZE=$(ls -lh "$FINAL_DMG" | awk '{print $5}')

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "🎉 DMG successfully built!"
echo "📍 Location: $FINAL_DMG"
echo "🔗 Alias:    $GENERIC_DMG"
echo "📊 Size:     $FILE_SIZE"
echo "🔑 SHA256:   $SHA256"
echo "═══════════════════════════════════════════════════════════"

if [ "$OPEN_AFTER" = true ]; then
    echo "🚀 Opening DMG..."
    open "$FINAL_DMG"
fi
