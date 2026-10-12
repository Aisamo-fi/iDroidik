# Roadmap / open tasks

Ordered, self-contained tasks for a human or an AI agent picking this up. Each has
a goal, why it matters, where to work, and a done-check. Read `AGENTS.md` and
`docs/STATE.md` first. Most tasks need the physical iPhone connected.

Priority key: P0 = blocks a clean/legal public release · P1 = important polish ·
P2 = nice to have.

---

## T0 — Reconcile the Android image (P0, no phone needed) — ✅ DONE
**Status (2026-10-12): done.** Canonical `nand-a16` sha = `437cf287…`, pinned in `install.sh`
and hosted on the v0.1-exp release; a from-scratch install was validated end-to-end.
**Goal:** make one canonical `nand-a16` whose sha256 matches `nand-a16.sha256`.
**Why:** the deployed phone image (`437cf287…`) and the local working image may
have diverged (later patches in memory were "not yet deployed"). A release must
ship a single, known image.
**Where:** your local working image (not in this repo). Verify with
`shasum -a 256 nand-a16`; decide which patches are in; re-run `patch-vulkan/apply.sh`
if needed; update `nand-a16.sha256`.
**Done when:** local sha == marker, and `docs/STATE.md` records it.

## T1 — Strip Apple firmware from the image; generate it on-device (P0)
**Status (2026-10-10): legal blocker CLEARED — verified on-device that the shipped
`nand` image is already firmware-free** (no firmware in /vendor, /system, /odm). The
Apple/Broadcom firmware lives only on the user's own Android APFS volume
(`/efs/usr/share/firmware`: touch `D10.mtprops` + brcmfmac 4355 Wi-Fi), copied from
the user's own iOS. `tools/gen-firmware.sh` added to do that copy on-device. See
`docs/FIRMWARE-AND-LEGAL.md`. **Remaining:** verify the iOS source path and run
`gen-firmware.sh` on a freshly-created volume (needs an iOS boot).

**Goal:** the distributed Android image contains ZERO Apple/Broadcom proprietary
firmware. Firmware is (re)generated on each user's device from their own iOS, the
way Project Sandcastle does.
**Why:** legality. See `docs/FIRMWARE-AND-LEGAL.md` for the full plan, the exact
firmware inventory, and how Sandcastle's `generate_firmware` / `hx-touchd` /
`hcdpack` / `syscfg` tools do the extraction.
**Where:** the image's `/vendor` (and the APFS Android volume `/usr/share/firmware`
per Sandcastle A10); `psc/hx-touchd`, `psc/hcdpack`, `psc/syscfg`; a new
`tools/gen-firmware.sh` run at install time.
**Done when:** a diff of the shipped image shows no `*.mtprops`, brcmfmac blobs,
`*.hcd`, or syscfg data; a fresh install regenerates them on-device and touch +
Wi-Fi still work.

## T2 — Host ALL binaries + one-command flasher (P0) — ✅ DONE
**Status (2026-10-12): done.** The image (split into 2 parts) and all four boot blobs are on the
v0.1-exp release; `install.sh` fetches + sha-verifies every one and reassembles the image atomically.
**Goal:** users get everything needed to boot without it living in git — the
(firmware-free) ~3 GB image **and the four boot binaries** (`work/Image-a16f.lzma`,
`work/debug-initrd.cpio.gz`, `pongo-rel/Pongo-2.6.1.bin`, `patch-vulkan/vulkan.pastel.so`).
Not just the image — a clone with only the image still can't boot.
**Why:** 3 GB image, GitHub caps release assets at 2 GB/file; the boot blobs are also absent.
**Where:** `tools/split-image.sh` (done) splits the image into <2 GB parts; `install.sh`
currently auto-fetches only the image and must be extended to fetch the boot binaries too.
Choose a host (torrent / archive.org / release assets), upload all of it, and set the URL(s)
in `MANIFEST.md` + `install.sh`. Also finish `docs/BUILD.md` (initrd + dtbpack recipes are
missing) so the binaries can be reproduced, not only downloaded.
**Done when:** on a clean Mac, `git clone … && ./install.sh` fetches+verifies the image AND
the boot binaries, and boots Android with no manual file shuffling.

## T3 — WebView without the flicker/crash tradeoff (P1)
**Goal:** WebView renders in the default (legacy-GL) mode.
**Why:** currently WebView crashes unless ANGLE is enabled for it, but ANGLE on
SystemUI/launcher flickers. See `docs/STATE.md`.
**Where:** `patch-vulkan/sc-render.sh` (per-app ANGLE list); investigate enabling
ANGLE only for WebView-hosting packages.
**Done when:** a WebView app (e.g. the WebView shell, or an app using WebView)
renders pages with no crash and no home-screen flicker.

## T4 — Lawnchair gestures / recents (P1)
**Goal:** bottom-edge swipe opens Lawnchair recents, not Launcher3's.
**Why:** Launcher3 is `config_recentsComponentName`; Lawnchair isn't a priv-app.
**Where:** make Lawnchair a priv-app with the needed privapp-permissions +
recents overlay (requires an image rebuild/deploy).
**Done when:** recents gesture works from the Lawnchair home.

## T5 — Pixel-like system font (P2)
**Goal:** ship Google Sans Flex (OFL) system-wide.
**Where:** `/system/fonts` + fallback config; needs an image deploy.
**Done when:** UI renders in the Pixel font after a clean boot.

## T6 — Install-crash robustness (P2)
**Goal:** installing large apps (Gboard, Chrome) no longer resets the phone to iOS.
**Why:** dex2oat/memory pressure crashed Android during a big install.
**Where:** `android.sh tune` already sets `pm.dexopt.*`, dex2oat threads/heap; tune
further, and document "install one small app at a time; watch MemAvailable".
**Done when:** a 90 MB app installs without a reset, or the limit is clearly documented.

---

### Backlog / ideas (unscheduled)
- Kernel `CRYPTO_LZ4` for faster zram (measured ~no gain last time; low value).
- Newer SwiftShader / ANGLE for a faster software GPU.
- Mac-free boot via a Raspberry Pi Zero 2 W running palera1n + our loaders.
- SurfaceFlinger on skiavkthreaded (needs framework restart; untested).
