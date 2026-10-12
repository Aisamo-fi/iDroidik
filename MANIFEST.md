# Binary artifacts manifest

Large binaries are **not** stored in git (see `.gitignore`). They are either built
from source (`docs/BUILD.md`) or fetched. The Android image and the four boot blobs are
**hosted on the `v0.1-exp` GitHub release**, and `install.sh` fetches + sha-verifies them
(the shas are pinned in `install.sh`). An install script (or an AI agent) reads this file.

Legend: **build** = produce via docs/BUILD.md · **fetch-release** = auto-fetched by install.sh
from the v0.1-exp release (sha pinned) · **fetch-upstream** = download from a third party ·
**on-device** = generated on the phone, never distributed.

| Artifact | Path it belongs at | How to get it | Source / URL | sha256 |
|----------|--------------------|---------------|--------------|--------|
| Android kernel | `work/Image-a16f.lzma` | fetch-release or build | corellium/linux-sandcastle + patches | `f816afbc93fe87667df9a2f903c6d9b4acd4b7098bc949895afd0375b765c086` |
| Boot initrd | `work/debug-initrd.cpio.gz` | fetch-release | corellium/sandcastle-buildroot (see docs/BUILD.md) | `fac6aeeef6610a0e41d7114bfb7983d54dca622c9b4da7b4566cb00980c6adc0` |
| A16 ramdisk (built into the kernel) | `work/ramdisk-a16.cpio` | build | see docs/BUILD.md (kernel CONFIG_INITRAMFS_SOURCE) | n/a — inside `Image-a16f.lzma` |
| Android 10 base image | `android-sandcastle/Android.lzma` | fetch-upstream | projectsandcastle.org original release | `TODO` |
| A10 dtbpack | `android-sandcastle/dtbpack` | fetch-upstream | projectsandcastle.org | `TODO` |
| Sandcastle Linux | `linux/Linux.lzma` + `linux/dtbpack` | fetch-upstream | projectsandcastle.org / buildroot | `TODO` |
| PongoOS 2.6.1 | `pongo-rel/Pongo-2.6.1.bin` | fetch-release | github.com/checkra1n/PongoOS release 2.6.1 | `6e8c39fff53fdb264409cd1237df0ed12363ad9a7f52f1191e3f578d78911a3e` |
| PongoOS (legacy) | `Pongo-0.10.1.bin` | fetch-upstream | checkra1n 0.10.1 (only for the old boot.sh path) | `TODO` |
| Vulkan driver | `patch-vulkan/vulkan.pastel.so` | fetch-release or build | SwiftShader (docs/BUILD.md) | `715120039e17d2c234bc2b293ee8f9b2253e23094c935112c6934c6320b91eee` |
| F-Droid | `apks/F-Droid.apk` | fetch-upstream | https://f-droid.org/F-Droid.apk | `TODO` |
| WebView APK | `psc/android/webview.apk` | fetch-upstream | projectsandcastle | `TODO` |
| Android GSI (A16) | (built into `nand`) | fetch-upstream/build | TrebleDroid `system-td-arm64-vanilla-old.img.xz` (ci-20250617) | `TODO` |
| **Android system image** | `nand-a16` (+ `nand-a16.sha256`) | **fetch-release, firmware-free** | split into <2 GB parts, see below | `437cf287…` (pinned in install.sh) |

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

**Hosting: done.** The 4 image files (2 parts + 2 sha manifests) and the 4 boot blobs are on the
`v0.1-exp` GitHub release, and `IMAGE_BASE_URL` in `install.sh` points there. `install.sh`
downloads the parts, verifies each sha, reassembles atomically with `tools/join-image.sh`, and
fetches + sha-verifies the boot blobs. (To re-host elsewhere, upload the same files and change
`IMAGE_BASE_URL`.)
