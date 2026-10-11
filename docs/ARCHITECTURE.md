# Architecture

How Android ends up running on an iPhone 7, and how the pieces in this repo fit.

## Big picture

The iPhone 7 (A10) is vulnerable to **checkm8**, an unpatchable bootrom exploit.
That lets us run unsigned code at boot via **PongoOS**, which loads a **Linux 5.4
kernel** (the Corellium *Sandcastle* fork, built for the iPhone's hardware). On top
of that kernel we run an **Android 16 GSI**. iOS is untouched and still boots
normally — Android is loaded fresh from the Mac each time (tethered; checkm8 is not
persistent).

```
Mac (host)                                iPhone 7
──────────                                ────────
palera1n -p  ── checkm8 ───────────────▶  BootROM → palera1n's pongoOS 2.6.3
loader/pongo-bootr  ── chainload ──────▶  official PongoOS 2.6.1 (has Linux cmds)
loader/pongo-linux  ── upload ─────────▶  kernel (Image-a16f.lzma) + dtbpack + initrd
                                          Linux 5.4 boots, mounts Android image,
                                          switch_root → Android init → UI
```

Why two PongoOS: palera1n's bundled pongo (2.6.3) lacks the Linux boot commands,
so we chainload the official 2.6.1 build that has them, and pass `linux_cmdline`
explicitly (the newer pongo blanks the dtb bootargs).

## Where Android lives: the `nand` image

Android's `system` + `vendor` partitions live inside a single **`nand` image file**
(~3 GB) stored on a dedicated **APFS volume named `Android`** inside the iPhone
(created next to the iOS volumes; iOS and Android share one APFS container). The
kernel maps partitions out of this file with `dm-linear`.

`nand` internal layout (super partition, offsets used by `patch-vulkan/apply.sh`):

| Partition | Byte offset | Length |
|-----------|-------------|--------|
| vendor | 3145728 | 201326592 |
| system | 204472320 | 2935996800 |

The base `nand.gz` is the pristine Project Sandcastle Android 10 image. The
Android 16 image (`nand-a16`) was produced by many in-place edits to that (new GSI
system, VNDK libs, capex→apex, audio HAL stubs, etc.) — see `docs/TECHNICAL-NOTES.md`.

## Persistent /data

Android's `/data` would be tmpfs (wiped every boot). Instead a `userdata.img` file
on the iPhone is **raw-mapped**: at boot Android scans raw `nvme0n1p1`, builds an
extent map for the file, sets up a `dm-linear` device over it, and mounts ext4 over
tmpfs `/data`. Guarded by nonce/header checks; any doubt → falls back to tmpfs.
Sources: `work/userdata/` (`scdata.c`, `sc-userdata.sh`).

## Graphics

No GPU driver exists. Rendering is pure CPU:
- **HWUI** (app 2D) runs on legacy GLES (skiagl) by default.
- Per-app GL goes through **ANGLE → our SwiftShader Vulkan driver**
  (`vulkan.pastel.so`, built from SwiftShader; see `docs/BUILD.md`).
- SystemUI + launcher are kept on native GL (they flickered under ANGLE/skiavk).
Controlled at runtime by `patch-vulkan/sc-render.sh` (`persist.sc.render`).

## Repo map

| Path | What |
|------|------|
| `android.sh` | main driver: boot / deploy / save / restore / tune / linux |
| `boot.sh`, `boot-android-shell.sh`, `wait-and-load.sh` | lower-level boot helpers |
| `config.env.example` | machine/phone-specific settings template |
| `loader/` | PongoOS loaders (`pongo-bootr`, `pongo-linux`, `pongo-shell`) + C sources |
| `patch-vulkan/` | SwiftShader Vulkan driver install + render/thermal/cpucap scripts + `apply.sh` |
| `psc/` | Project Sandcastle sources: kernel patches, `hx-touchd`, `hcdpack`, `syscfg`, AOSP diff |
| `linux/` | Sandcastle Linux build assets (`./android.sh linux`) |
| `android-sandcastle/` | original Sandcastle Android 10 release (base of the boot chain) |
| `pongo/` | PongoOS source (to build the loaders / the 2.6.1 blob) |
| `work/` | kernel configs, dtb, initrd sources, `effstub/` (audio stub), `userdata/` (persistence) |
| `kbuild/`, `kbuild7/` | Dockerfiles for the kernel build containers (gcc 9 and gcc 7.5) |
| `tools/` | image split/join, on-phone nand upload/patch, `lpsuper.py`, `sotest.c` |
| `pixel/` | Material-3 wallpapers + preview for the Pixel look |
| `docs/` | this documentation |

Big binaries (kernel, GSI, image, apks, pongo blobs, `.so`) are NOT in git — see
`MANIFEST.md`.
