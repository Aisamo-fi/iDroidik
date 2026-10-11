# Binary artifacts manifest

Large binaries are **not** stored in git (see `.gitignore`). They are either built
from source (`docs/BUILD.md`) or fetched. Fill in the URLs + sha256 once you host
them. An install script (or an AI agent) should read this file to locate everything.

Legend: **build** = produce via docs/BUILD.md · **fetch-upstream** = download from a
third party · **user-host** = you must upload it somewhere and put the link here ·
**on-device** = generated on the phone, never distributed.

| Artifact | Path it belongs at | How to get it | Source / URL | sha256 |
|----------|--------------------|---------------|--------------|--------|
| Android kernel | `work/Image-a16f.lzma` | build or user-host | corellium/linux-sandcastle + patches | `TODO` |
| Boot initrd | `work/debug-initrd.cpio.gz` | user-host | from the working tree | `TODO` |
| A16 ramdisk | `work/ramdisk-a16.cpio` | user-host | from the working tree | `TODO` |
| Android 10 base image | `android-sandcastle/Android.lzma` | fetch-upstream | projectsandcastle.org original release | `TODO` |
| A10 dtbpack | `android-sandcastle/dtbpack` | fetch-upstream | projectsandcastle.org | `TODO` |
| Sandcastle Linux | `linux/Linux.lzma` + `linux/dtbpack` | fetch-upstream | projectsandcastle.org / buildroot | `TODO` |
| PongoOS 2.6.1 | `pongo-rel/Pongo-2.6.1.bin` | fetch-upstream | github.com/checkra1n/PongoOS release 2.6.1 | `TODO` |
| PongoOS (legacy) | `Pongo-0.10.1.bin` | fetch-upstream | checkra1n 0.10.1 (only for the old boot.sh path) | `TODO` |
| Vulkan driver | `patch-vulkan/vulkan.pastel.so` | build or user-host | SwiftShader (docs/BUILD.md) | `TODO` |
| F-Droid | `apks/F-Droid.apk` | fetch-upstream | https://f-droid.org/F-Droid.apk | `TODO` |
| WebView APK | `psc/android/webview.apk` | fetch-upstream | projectsandcastle | `TODO` |
| Android GSI (A16) | (built into `nand`) | fetch-upstream/build | TrebleDroid `system-td-arm64-vanilla-old.img.xz` (ci-20250617) | `TODO` |
| **Android system image** | `nand-a16` (+ `nand-a16.sha256`) | **user-host, firmware-free** | split into <2 GB parts, see below | `437cf287…` (current; re-check after T0/T1) |

## The Android system image (the big one)

`nand-a16` is ~3 GB and cannot go in git or a single GitHub release asset (2 GB cap).

- **Firmware:** already handled — the image is firmware-free (see `docs/FIRMWARE-AND-LEGAL.md`,
  verified 2026-10-10). Safe to distribute.
- **Already split** (2026-10-10) with `tools/split-image.sh`. Upload these 4 files to a host:

  | File | Size | sha256 |
  |------|------|--------|
  | `nand-a16.part00` | 1,900,000,000 | `95a8a507465b6df122e1384649ee392ac0bbd188f23c1ae985074336523edf74` |
  | `nand-a16.part01` | 1,369,459,968 | `0113eb12f541779bf54c25dcb96d0dc6524282dff35a5391b00d4d52718e9594` |
  | `nand-a16.parts.sha256` | 164 | (manifest of the two parts above) |
  | `nand-a16.whole.sha256` | 101 | reassembled image = `437cf287068e2b0ffd17225d1309314aa108437a62fb187d53ed31a93f39dfe1` |

  The split parts are produced by `tools/split-image.sh` (written to `nandparts/`).

**Remaining (user decision):** pick a host (GitHub release assets / archive.org / your own
server / torrent), upload the 4 files, then set `IMAGE_BASE_URL` in `install.sh` to the folder
URL. `install.sh` already downloads the parts, verifies each sha, and reassembles with
`tools/join-image.sh`. Until `IMAGE_BASE_URL` is set, `install.sh` stops cleanly and tells the
user how to obtain the image.
