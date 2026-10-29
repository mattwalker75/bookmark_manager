#!/usr/bin/env bash
#
# make_icns.sh — turn icon/icon.svg into icon/BookmarkManager.icns (every size macOS wants, 16 px to 1024 px).
#
# Draws the SVG with the Mac's own image code (no browser needed), scales it with sips and packs it with iconutil.
# The result is committed, so this only has to run again when icon.svg changes.
#
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SVG="$HERE/icon.svg"; OUT="$HERE/BookmarkManager.icns"; SET="$HERE/BookmarkManager.iconset"; PNG="$HERE/icon-1024.png"

# 1024×1024 PNG from the SVG, through AppKit (macOS reads SVG since Big Sur)
SVG="$SVG" PNG="$PNG" swift - <<'SWIFT'
import AppKit
let env = ProcessInfo.processInfo.environment
let svg = URL(fileURLWithPath: env["SVG"]!), png = URL(fileURLWithPath: env["PNG"]!)
guard let image = NSImage(contentsOf: svg) else { FileHandle.standardError.write(Data("Could not read \(svg.path) as a picture.\n".utf8)); exit(1) }
let side = 1024
guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
rep.size = NSSize(width: side, height: side)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high
image.draw(in: NSRect(x: 0, y: 0, width: side, height: side), from: .zero, operation: .sourceOver, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! data.write(to: png)
SWIFT
[[ -s "$PNG" ]] || { echo "The picture was not produced." >&2; exit 1; }

rm -rf "$SET"; mkdir -p "$SET"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$PNG" --out "$SET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$PNG" --out "$SET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o "$OUT"
rm -rf "$SET"
echo "Wrote $OUT"
