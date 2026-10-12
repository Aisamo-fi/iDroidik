#!/bin/bash
# One-command setup for Android on iPhone 7.
#
# It installs host prerequisites, fetches the Android system image (split) AND the kernel / initrd /
# pongo / vulkan boot blobs from the GitHub release (IMAGE_BASE_URL below), verifying each against a
# pinned sha256 and reassembling the image, then hands off to ./setup-device.sh / ./android.sh.
# If a download fails or a checksum does not match, it stops cleanly. To build from source instead,
# see MANIFEST.md / docs/BUILD.md.
#
# It never restores or erases your iPhone. iOS keeps working (palera1n -n).
set -u
cd "$(dirname "$0")"
# make tools installed in the usual places visible (palera1n, brew, adb)
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '\033[32m✓ %s\033[0m\n' "$*"; }
warn() { printf '\033[33m! %s\033[0m\n' "$*"; }
die()  { printf '\033[31m✗ %s\033[0m\n' "$*"; exit 1; }

# Where the image parts + boot binaries are hosted (GitHub release assets; see MANIFEST.md).
IMAGE_BASE_URL="${IMAGE_BASE_URL:-https://github.com/Aisamo-fi/iDroidik/releases/download/v0.1-exp}"
IMAGE_BASE_NAME="nand-a16"
# Pinned sha256 of the reassembled image. The image is verified against THIS value (baked into
# the repo), never against a .sha256 downloaded from the same host — so a compromised host can't
# swap the system image. Update this when the canonical image changes (ROADMAP T0/T1).
EXPECTED_IMAGE_SHA256="437cf287068e2b0ffd17225d1309314aa108437a62fb187d53ed31a93f39dfe1"

bold "Android on iPhone 7 — installer"
echo

# 1. config
if [ ! -f config.env ]; then
  cp config.env.example config.env
  warn "created config.env from the example — edit it (phone IP etc.) if you will use deploy/save"
fi

# 2. host prerequisites
# Auto-install palera1n (the checkm8/boot tool) if it is missing. Best-effort: on any
# failure we fall back to a clear manual instruction and keep going.
if ! command -v palera1n >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/palera1n" ]; then
  bold "Installing palera1n (official installer from palera.in)…"
  # download to a temp file first (so a truncated stream is caught), then run it
  # non-interactively (</dev/null) so its prompts don't hang an automated run.
  _p1n=$(mktemp)
  if curl -fsSL https://static.palera.in/scripts/install.sh -o "$_p1n" && [ -s "$_p1n" ]; then
    bash "$_p1n" </dev/null || warn "palera1n installer returned an error"
  else
    warn "could not download the palera1n installer"
  fi
  rm -f "$_p1n"
  export PATH="$HOME/.local/bin:$PATH"
  command -v palera1n >/dev/null 2>&1 || warn "palera1n is not on PATH yet — install it from https://palera.in (and ensure ~/.local/bin is on PATH)"
fi
# Auto-install sshpass + adb via Homebrew if missing (needed for on-device setup / adb).
if ! command -v sshpass >/dev/null 2>&1 && command -v brew >/dev/null 2>&1; then
  bold "Installing sshpass (Homebrew)…"
  NONINTERACTIVE=1 brew install hudochenkov/sshpass/sshpass >/dev/null 2>&1 && ok "sshpass installed" || warn "could not auto-install sshpass — brew install hudochenkov/sshpass/sshpass"
fi
if ! command -v adb >/dev/null 2>&1 && command -v brew >/dev/null 2>&1; then
  bold "Installing adb (Homebrew android-platform-tools)…"
  NONINTERACTIVE=1 brew install android-platform-tools >/dev/null 2>&1 && ok "adb installed" || warn "could not auto-install adb — brew install android-platform-tools"
fi
# libusb: the prebuilt pongo loaders (loader/pongo-*) link against Homebrew's libusb at runtime.
if command -v brew >/dev/null 2>&1 && ! brew list libusb >/dev/null 2>&1; then
  bold "Installing libusb (Homebrew; the pongo loaders link against it)…"
  NONINTERACTIVE=1 brew install libusb >/dev/null 2>&1 && ok "libusb installed" || warn "could not auto-install libusb — brew install libusb"
fi

step_missing=0
need() { command -v "$1" >/dev/null 2>&1 || { warn "missing: $1  ($2)"; step_missing=1; }; }
need palera1n "install from https://palera.in, or set PALERA1N in config.env"
need sshpass   "brew install hudochenkov/sshpass/sshpass"
need adb       "brew install android-platform-tools"
need shasum    "part of macOS"
need curl      "part of macOS"
need python3   "part of the Xcode Command Line Tools: xcode-select --install"
need perl      "part of macOS"
need openssl   "part of macOS / brew install openssl"
[ "$step_missing" = 0 ] && ok "host tools present" || warn "install the tools above, then re-run"

# 3. fetch the Android image (per MANIFEST.md)
# Downloading the parts (~3.3 GB) and reassembling them needs ~6.5 GB free transiently on the Mac.
free_mb=$(df -m . 2>/dev/null | awk 'NR==2{print $4}')
case "$free_mb" in ''|*[!0-9]*) : ;; *) [ "$free_mb" -lt 7000 ] && warn "low disk on the Mac (~${free_mb} MB free) — downloading + joining the image needs ~6.5 GB; free space first or the join may fail." ;; esac
fetched=0
# Drop a stale/partial leftover: trust an existing reassembled image only when it still matches
# the downloaded parts' whole.sha256 (when we have it). A genuine self-built image has no
# nandparts/whole.sha256 and is pin-checked below instead.
if [ -f "$IMAGE_BASE_NAME" ] && [ -f "nandparts/$IMAGE_BASE_NAME.whole.sha256" ] \
   && [ "$(shasum -a 256 "$IMAGE_BASE_NAME" | cut -d' ' -f1)" != "$(cut -d' ' -f1 "nandparts/$IMAGE_BASE_NAME.whole.sha256")" ]; then
  warn "existing $IMAGE_BASE_NAME doesn't match the downloaded parts — discarding and re-joining"
  rm -f "$IMAGE_BASE_NAME"
fi
if [ -f "$IMAGE_BASE_NAME" ]; then
  ok "$IMAGE_BASE_NAME already present"
elif [ -n "$IMAGE_BASE_URL" ]; then
  fetched=1
  bold "downloading Android image parts…"
  mkdir -p nandparts
  curl -fsSL "$IMAGE_BASE_URL/$IMAGE_BASE_NAME.parts.sha256" -o "nandparts/$IMAGE_BASE_NAME.parts.sha256" \
    || die "could not fetch the parts manifest from $IMAGE_BASE_URL"
  while read -r psha part; do
    [ -n "$part" ] || continue
    # only accept a bare filename from the manifest (no path traversal)
    case "$part" in */*|*..*) die "refusing suspicious part name in manifest: $part" ;; esac
    if [ -f "nandparts/$part" ]; then
      # keep an existing part only if it already matches its manifest sha; else re-fetch it
      [ "$(shasum -a 256 "nandparts/$part" | cut -d' ' -f1)" = "$psha" ] && continue
      warn "re-downloading corrupt/partial part: $part"; rm -f "nandparts/$part"
    fi
    echo "  $part"
    curl -fSL "$IMAGE_BASE_URL/$part" -o "nandparts/$part" || die "download failed: $part"
  done < "nandparts/$IMAGE_BASE_NAME.parts.sha256"
  curl -fsSL "$IMAGE_BASE_URL/$IMAGE_BASE_NAME.whole.sha256" -o "nandparts/$IMAGE_BASE_NAME.whole.sha256" 2>/dev/null || true
  ./tools/join-image.sh nandparts "$IMAGE_BASE_NAME" "$IMAGE_BASE_NAME" || die "reassembly failed"
  ok "Android image ready"
else
  warn "IMAGE_BASE_URL is not set — cannot auto-download the Android image."
  echo "  Options:"
  echo "   • build it yourself (docs/BUILD.md), or"
  echo "   • get the split parts, put them in ./nandparts/, and run:"
  echo "       ./tools/join-image.sh nandparts $IMAGE_BASE_NAME $IMAGE_BASE_NAME"
  echo "  See MANIFEST.md. (This is expected on first release — ROADMAP task T2.)"
fi

# Verify the image and write the marker ./android.sh deploy / tools/*-phone-nand.sh need.
# A DOWNLOADED image must match the PINNED hash (so a compromised host can't swap it). A
# self-built / self-supplied image legitimately won't match the canonical pin — accept it and
# record its own hash (set ALLOW_UNPINNED_IMAGE=0 to forbid even that).
if [ -f "$IMAGE_BASE_NAME" ]; then
  got=$(shasum -a 256 "$IMAGE_BASE_NAME" | cut -d' ' -f1)
  if [ "$got" = "$EXPECTED_IMAGE_SHA256" ]; then
    printf '%s  %s\n' "$got" "$IMAGE_BASE_NAME" > "$IMAGE_BASE_NAME.sha256"
    ok "image verified against the pinned sha256"
  elif [ "$fetched" = 1 ]; then
    warn "DOWNLOADED image sha256 does NOT match the pinned value — do NOT flash it:"
    echo "    expected $EXPECTED_IMAGE_SHA256"
    echo "    got      $got"
    # QUARANTINE the bad download: if we left it in place, a re-run would see "already present"
    # (fetched=0) and accept it as a self-built image — silently defeating the pin.
    rm -f "$IMAGE_BASE_NAME.sha256"
    mv -f "$IMAGE_BASE_NAME" "$IMAGE_BASE_NAME.BAD" 2>/dev/null \
      && warn "moved the bad image to $IMAGE_BASE_NAME.BAD — delete it; do not use it."
    step_missing=1
  elif [ "${ALLOW_UNPINNED_IMAGE:-1}" = 1 ]; then
    warn "image is not the canonical pinned build (normal for a self-built image) — using its own hash."
    printf '%s  %s\n' "$got" "$IMAGE_BASE_NAME" > "$IMAGE_BASE_NAME.sha256"
  else
    warn "image sha256 does not match the pin and ALLOW_UNPINNED_IMAGE=0 — refusing."
    rm -f "$IMAGE_BASE_NAME.sha256"
    step_missing=1
  fi
fi

# 3b. boot binaries (not in git). Fetch from IMAGE_BASE_URL if set, verify against pinned sha256.
# Format: "<target-path>|<basename>|<sha256>"
BOOT_BLOBS="
work/Image-a16f.lzma|Image-a16f.lzma|f816afbc93fe87667df9a2f903c6d9b4acd4b7098bc949895afd0375b765c086
work/debug-initrd.cpio.gz|debug-initrd.cpio.gz|fac6aeeef6610a0e41d7114bfb7983d54dca622c9b4da7b4566cb00980c6adc0
pongo-rel/Pongo-2.6.1.bin|Pongo-2.6.1.bin|6e8c39fff53fdb264409cd1237df0ed12363ad9a7f52f1191e3f578d78911a3e
patch-vulkan/vulkan.pastel.so|vulkan.pastel.so|715120039e17d2c234bc2b293ee8f9b2253e23094c935112c6934c6320b91eee
"
boot_missing=""
echo "$BOOT_BLOBS" | while IFS='|' read -r path name sha; do
  [ -n "$path" ] || continue
  if [ ! -f "$path" ] && [ -n "$IMAGE_BASE_URL" ]; then
    mkdir -p "$(dirname "$path")"
    echo "  fetching $name"
    curl -fSL "$IMAGE_BASE_URL/$name" -o "$path.tmp" 2>/dev/null && mv "$path.tmp" "$path" || rm -f "$path.tmp"
  fi
done
# verify each boot blob against its pinned sha (separate loop: the while-pipe runs in a subshell)
echo "$BOOT_BLOBS" | while IFS='|' read -r path name sha; do
  [ -n "$path" ] || continue
  [ -f "$path" ] || continue
  got=$(shasum -a 256 "$path" | cut -d' ' -f1)
  [ "$got" = "$sha" ] || { warn "$path sha256 mismatch — removing (expected $sha)"; mv -f "$path" "$path.BAD" 2>/dev/null; }
done
for b in work/Image-a16f.lzma work/debug-initrd.cpio.gz pongo-rel/Pongo-2.6.1.bin patch-vulkan/vulkan.pastel.so; do
  [ -f "$b" ] || boot_missing="$boot_missing $b"
done
if [ -n "$boot_missing" ]; then
  step_missing=1
  warn "missing/invalid boot binaries (build per docs/BUILD.md, or set IMAGE_BASE_URL to a host that has them):"
  for f in $boot_missing; do echo "    $f"; done
fi

# 4. firmware note (see docs/FIRMWARE-AND-LEGAL.md)
warn "Apple firmware (touch/Wi-Fi) is NOT shipped. It is generated on your"
echo "  device from your own iOS by ./setup-device.sh (tools/gen-firmware.sh) — see docs/FIRMWARE-AND-LEGAL.md."

echo
if [ "$step_missing" = 0 ] && [ -f "$IMAGE_BASE_NAME" ] && [ -z "$boot_missing" ]; then
  bold "Ready. First-time device setup:  ./setup-device.sh    then boot:  ./android.sh"
else
  warn "NOT READY — finish these first:"
  [ "$step_missing" = 0 ] && [ -z "$boot_missing" ] || echo "  • install the missing host tools / boot binaries listed above"
  [ -f "$IMAGE_BASE_NAME" ] || echo "  • obtain/build the Android image '$IMAGE_BASE_NAME' and place it here (see MANIFEST.md)"
  echo "  then re-run ./install.sh"
  exit 2
fi
