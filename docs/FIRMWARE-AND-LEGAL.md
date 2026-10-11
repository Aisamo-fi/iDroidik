# Firmware & legality

**The single rule:** this project never distributes Apple's (or Broadcom's) proprietary
firmware. That firmware is required to make the touchscreen and Wi-Fi work, but it belongs
to Apple/Broadcom and is licensed to the user only as part of their iOS. So we do what
Project Sandcastle does: the firmware is copied on the user's own device, from their own
iOS, at install time.

## ✅ Verified on-device (2026-10-10): the shipped image is already firmware-free

Inspected a live install and confirmed:

- The distributed **`nand` image contains NO firmware** — `/vendor`, `/system` and `/odm`
  (all from the image) have zero `*.mtprops`, `brcmfmac*`, `*.hcd`, `*.clm*`, `*.trx` files.
- The firmware lives ONLY on the **Android APFS volume** the user creates on their own
  iPhone, mounted at `/efs` (`/usr/share/firmware`), alongside the `nand` file:

  | Component | Files on the Android volume | Origin |
  |-----------|------------------------------|--------|
  | Touch (iPhone 7 = D10) | `usr/share/firmware/multitouch/D10.mtprops` | the user's iOS |
  | Wi-Fi (brcmfmac 4355) | `usr/share/firmware/wifi/C-4355__s-C0/*.trx, *.clmb, *.txcb, *.txt` | the user's iOS |
  | Bluetooth | (not present — BT is not wired up in this build) | — |

So distributing our `nand` image does **not** redistribute Apple firmware. The legal blocker
is cleared for the image itself.

## How a new user gets firmware (on-device generation)

The original Sandcastle on-device setup (`android-sandcastle/isetup`) only creates the
Android APFS volume and downloads the `nand` image — it does **not** place firmware. The
firmware on `/efs/usr/share/firmware` comes from the user's own iOS, which stores the same
tree at `/usr/share/firmware`.

`tools/gen-firmware.sh` performs that copy, on the user's device, over SSH to their
jailbroken iOS:

```bash
# phone booted into jailbroken iOS, reachable over SSH (config.env set)
./tools/gen-firmware.sh
```

It mounts the Android volume and copies `/usr/share/firmware/{multitouch,wifi}` from the
device's own iOS onto it. Nothing is downloaded; nothing proprietary leaves the device.

The Sandcastle `psc/` tools remain available for the harder extraction cases (reconstructing
firmware when it is not already a plain file): `psc/syscfg` (board config), `psc/hx-touchd`
(loads touch firmware at runtime), `psc/hcdpack` (Bluetooth). The Snowcastle
`generate_firmware` is the reference for pulling touch/Wi-Fi/BT from the iOS root volume /
preboot kernelcache when needed, sha-pinned to the iOS build.

## Still to verify (needs an iOS boot)

- Confirm the exact iOS source path on a fresh device (`/usr/share/firmware` is expected and
  used by `gen-firmware.sh`; verify on the target's iOS version and adjust if Apple moved it).
- Run `gen-firmware.sh` end-to-end on a freshly-created Android volume and confirm touch +
  Wi-Fi come up. (On the current device firmware is already present, so this needs a clean
  volume to test the path properly.)

## How to verify an image is clean (before publishing any image)

Mount the image's `/vendor` read-only (offsets in `patch-vulkan/apply.sh` /
`docs/ARCHITECTURE.md`) — or, on a running device, inspect `/vendor`, `/system`, `/odm` — and
confirm there are no `*.mtprops`, `brcmfmac*`, `*.hcd`, `*.trx`, `*.clm*`, or syscfg dumps.
On the 2026-10-10 image this returned nothing.

## Other legal notes

- **GSI / AOSP** (the Android system) is Apache-2.0 — redistributable, but large; fetch/build
  per `MANIFEST.md` rather than committing it.
- **Do not** commit anyone's `WifiConfigStore.xml`, `/data`, or logs — Wi-Fi PSKs / personal
  data. `.gitignore` blocks `data/` and `logs/`.
- Never restore/erase the device (unrelated to firmware legality, but it would wipe the phone).
- Guidance, not legal advice. Before publicly distributing any prebuilt image, re-run the
  "verify an image is clean" check above.
