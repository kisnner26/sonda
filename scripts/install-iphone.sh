#!/usr/bin/env bash
# compila sonda en release, la firma con tu equipo de apple y la instala en tu iphone.
# con una cuenta gratuita el perfil dura 7 dias: vuelve a correr este script para renovarlo.
#
#   TEAM_ID=XXXXXXXXXX ./scripts/install-iphone.sh            instala en el primer iphone emparejado
#   TEAM_ID=XXXXXXXXXX ./scripts/install-iphone.sh "mi iphone" busca por nombre
#   ./scripts/install-iphone.sh --dry-run                      solo muestra que iphone encontro
#
# tu team id: xcode > settings > accounts > tu equipo, o `security find-identity -v -p codesigning`.
set -euo pipefail
cd "$(dirname "$0")/.."

DRY=0; NAME=""
for a in "$@"; do [ "$a" = "--dry-run" ] && DRY=1 || NAME="$a"; done

tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
xcrun devicectl list devices --json-output "$tmp" >/dev/null 2>&1
read -r ID UDID PNAME < <(python3 - "$tmp" "$NAME" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))["result"]["devices"]
want = sys.argv[2].lower()
for d in data:
    hw, dp = d.get("hardwareProperties", {}), d.get("deviceProperties", {})
    if hw.get("deviceType") != "iPhone": continue
    if d.get("connectionProperties", {}).get("tunnelState") == "unavailable": continue
    if want and want not in dp.get("name", "").lower(): continue
    print(d["identifier"], hw.get("udid", ""), dp.get("name", "").replace(" ", "_"))
    break
PY
) || true
[ -n "${ID:-}" ] || { echo "no encontre un iphone emparejado y disponible (desbloquealo y conectalo)" >&2; exit 1; }
echo "iphone: ${PNAME//_/ } ($UDID)"
[ "$DRY" = 1 ] && exit 0

: "${TEAM_ID:?define TEAM_ID con tu team id de apple}"
command -v xcodegen >/dev/null || { echo "falta xcodegen: brew install xcodegen" >&2; exit 1; }
xcodegen generate >/dev/null
xcodebuild -project Sonda.xcodeproj -scheme Sonda -configuration Release \
  -destination "platform=iOS,id=$UDID" -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM_ID" \
  -derivedDataPath build build | grep -E 'error:|BUILD' || true

APP=$(find build ~/Library/Developer/Xcode/DerivedData/Build/Products -path '*Release-iphoneos/Sonda.app' -maxdepth 6 2>/dev/null | head -1)
[ -d "${APP:-}" ] || { echo "no encontre Sonda.app compilado" >&2; exit 1; }
xcrun devicectl device install app --device "$ID" "$APP"
xcrun devicectl device process launch --device "$ID" com.kisnner26.sonda
