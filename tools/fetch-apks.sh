#!/bin/bash
# ⚠️ EXPERIMENTAL — download the core FOSS apps into ./apks/ from their OFFICIAL sources, so
# pixelify.sh can install them. Nothing proprietary is downloaded. Best-effort: sources/versions
# change over time; if one fails, get that app from F-Droid/Aurora by hand. Requires curl.
#
# These give the Pixel look + an app store:
#   - Lawnchair + Lawnicons  → the Pixel-style launcher + icons
#   - HeliBoard              → keyboard
#   - F-Droid                → open-source app store (get Aurora, Fossify, Firefox, etc. from it)
# Proprietary apps (TikTok, etc.) are NOT downloaded — install them from Aurora Store yourself.
set -u
cd "$(dirname "$0")/.."
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
mkdir -p apks
command -v curl >/dev/null 2>&1 || { echo "curl is required"; exit 1; }

ok(){ printf '\033[32m✓ %s\033[0m\n' "$*"; }
warn(){ printf '\033[33m! %s\033[0m\n' "$*"; }

# grab the first .apk asset URL from a GitHub repo's latest release
gh_latest_apk() { # owner/repo [name-filter]
  local repo="$1" filt="${2:-}"
  curl -fsSL "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null \
    | grep -oE '"browser_download_url": *"[^"]+\.apk"' | cut -d'"' -f4 \
    | { [ -n "$filt" ] && grep -i "$filt" || cat; } | head -1
}
dl() { # url outfile
  [ -n "$1" ] || { warn "no URL for $2"; return 1; }
  printf '  %s … ' "$2"
  if curl -fSL "$1" -o "apks/$2" 2>/dev/null && [ -s "apks/$2" ]; then echo ok; else echo "FAILED ($1)"; rm -f "apks/$2"; return 1; fi
}

echo "Fetching core FOSS apps into ./apks/ (official sources)…"
dl "https://f-droid.org/F-Droid.apk" "F-Droid.apk"
dl "$(gh_latest_apk LawnchairLauncher/lawnchair)" "Lawnchair.apk"
dl "$(gh_latest_apk LawnchairLauncher/lawnicons)" "Lawnicons.apk"
dl "$(gh_latest_apk Helium314/HeliBoard)" "HeliBoard.apk"

echo
ok "Done (best-effort). In ./apks/:"
ls -1 apks/*.apk 2>/dev/null | sed 's|^|  |' || warn "nothing downloaded — fetch apps from F-Droid/Aurora manually"
echo
echo "Get the rest from F-Droid once it's installed (Aurora Store, Fossify suite, Firefox/Fennec),"
echo "and proprietary apps (TikTok, etc.) from Aurora Store. Then run ./pixelify.sh."
