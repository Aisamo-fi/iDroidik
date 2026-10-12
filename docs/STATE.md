# Project state — what works, what doesn't

Hardware-verified on the maintainer's device: 2026-09-15 (docs updated 2026-10-11).
Device: iPhone 7 (iPhone9,3), iOS 15.8.8, rootful palera1n jailbreak. Android: Android 16
(TrebleDroid GSI, treble_arm64), Sandcastle kernel 5.4 (16 KB pages).

> This table describes the maintainer's fully-set-up device. The **shipped image is plain
> Android (GSI)** — the Pixel look and apps come from `pixelify.sh` (not baked in). Persistent
> `/data` is provisioned by `setup-device.sh` by default (it falls back to a RAM `/data` only if
> the phone is low on free space); `./android.sh deploy` is the advanced path that also does it.
> Single source of truth for status — update it whenever behavior changes.

## Works (on a fully-set-up device)

| Area | Status | Notes |
|------|--------|-------|
| Boot to Android UI | ✅ | Boots to a usable Android desktop. Tethered boot each time. |
| Touchscreen | ✅ | Sandcastle apple_z2 driver + hx-touchd firmware. |
| Wi-Fi + internet | ✅ | brcmfmac; user enters the Wi-Fi password on first `/data`. |
| ADB | ✅ | USB gadget ("CORELLIUM-I7") + ADB-over-Wi-Fi for bulk transfers. |
| App install (APK) | ✅ | F-Droid, Aurora Store; 16 KB page-size compat dialog is normal. |
| Graphics (2D UI) | ✅ | HWUI on legacy GLES (skiagl); per-app GL via ANGLE→SwiftShader Vulkan. |
| zram swap | ✅ | lzo-rle, ~1.2 GB (kernel has no lz4 backend). |
| Thermal management | ✅ | sc-thermal.sh caps CPU by battery temp (no cpuidle driver exists). |
| Pixel look | ⚠️ via pixelify | Lawnchair + Lawnicons, dark, circle icons, wallpaper — applied by `pixelify.sh`, NOT in the shipped image. |
| Persistent /data | ✅ by default (new) | `setup-device.sh` creates a raw-mapped `userdata.img` so `/data` survives reboot; falls back to RAM only when the phone lacks free space (or `NO_PERSIST=1`). The mechanism is proven (it ran via `./android.sh deploy`); the `setup-device.sh` integration is new and **not yet re-verified end-to-end on a fresh device**. |

## Does NOT work

| Area | Status | Reason |
|------|--------|--------|
| Audio | ❌ | No i2s/codec driver in kernel 5.4; HAL is stubbed to let boot proceed. |
| Camera | ❌ | No driver. |
| Cellular / SMS / calls | ❌ | No baseband driver. |
| Bluetooth | ❌ | hcd extraction path exists but not wired up in this build. |
| Hardware GPU accel | ❌ | No GPU driver; everything is SwiftShader (CPU) — expect a slow UI. |
| Untethered boot | ❌ | Every boot needs the Mac + DFU (checkm8 is not persistent). |
| WebView in legacy-GL mode | ⚠️ | Crashes unless ANGLE is on for that app. See ROADMAP task T3. |

## Performance (rough, SwiftShader on 2 cores, render res 450x800)

Median SystemUI frame ~42–150 ms depending on resolution; it is usable, not fast. This is a
software-rendered desktop on a phone with no GPU driver — set expectations accordingly.

## Known-good configuration

- Kernel: `work/Image-a16f.lzma` (gcc 7.5, sockopt cgroup-bpf backport).
- Render: the known-good setting is `persist.sc.render=gl` (legacy GLES for HWUI, ANGLE per-app
  except SystemUI + launcher). Note `android.sh tune` defaults to `angle` if the prop is unset —
  run `RENDER=gl ./android.sh tune` for the known-good config.
- CPU cap: `persist.sc.cpu_max=1644000` (thermal guard steps it down further).
- Shipped image `nand-a16` sha256 prefix `437cf287…`; the split parts verify against it.

## Hard constraints (do not relearn these the hard way)

- **NEVER restore/erase the iPhone.** Setup only ADDS an APFS volume; iOS must keep booting
  normally (`palera1n -n`). A "Restore" in Finder wipes the device.
- iOS and Android share ONE APFS container. The kernel's APFS driver is **read-only**; do not
  enable experimental APFS write — it risks the iOS volume.
- Never `pkill -f <pattern>` from an adb shell — it matches and kills the shell itself. Use `pidof`.
- Never restart `servicemanager` / `hwservicemanager` on a live device — VINTF is cached there
  and the phone drops.
- Phone→Mac USB transfers die past a trickle; use ADB-over-Wi-Fi in 4 MB verified chunks
  (already implemented in android.sh).
- Kernels built with gcc 9 reset to iOS after ~45 s. Build with gcc 7.5 only.
