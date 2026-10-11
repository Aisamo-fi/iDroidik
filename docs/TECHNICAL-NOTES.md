# Technical notes

Hard-won fixes that made Android 16 boot on the 5.4 Sandcastle kernel. Keep these —
most were found by hours of on-device bisection and are not obvious.

## Kernel

- **Compiler: gcc 7.5 only.** Kernels built with gcc 9.4 reset the phone to iOS
  ~45 s after boot (gcc 9 auto-enables STACKPROTECTOR_PER_TASK / CC_HAS_ASM_INLINE).
  Build in the `kbuild7` container (ubuntu 18.04, gcc 7.5). LZMA-compress the Image
  like `Android.lzma` (lc3 lp0 pb2, 8 MB dict, FORMAT_ALONE).
- **16 KB pages** (`CONFIG_ARM64_16K_PAGES`). 4 KB-built GSIs (Android 13/14) cannot
  run; target page-size-agnostic Android 15/16 GSIs. All native libs must be
  16 KB-aligned (`-z max-page-size=16384`).
- **Legacy binder devices:** patch `binder.c` so `/dev/binder,hwbinder,vndbinder`
  are created even with `CONFIG_ANDROID_BINDERFS=y` (A10 first-stage init doesn't
  mount binderfs). Marker comment: `sandcastle: keep legacy binder devices`.
- **cgroup-bpf sockopt fix:** backport upstream `d8fe449a9c51` into
  `kernel/bpf/cgroup.c`. Without it, A16 `netbpfload` attaches setsockopt/getsockopt
  BPF progs that set `optlen=0`; the 5.4 code copies that back as EINVAL, so every
  `SOL_SOCKET setsockopt` fails → `netd` crash-loops. This fix is what makes
  `Image-a16f`.
- Kernel lacks: audio (i2s/codec), GPU, EROFS, `CRYPTO_LZ4` (built as module only —
  zram must use `lzo-rle`), cpuidle for `hx` (hence the thermal script).

## Android system image (nand-a16), built by in-place edits

- **VNDK:** copied 249 16 KB-aligned vndk-29 + vndk-sp-29 libs into `/vendor/lib64`
  (+`hw`). Without them the A16 linker refuses every A10 vendor binary
  ("program alignment (4096) cannot be smaller than system page size (16384)").
  Vendor ext4 was grown 53→192 MiB to fit.
- **capex → apex:** the GSI ships compressed `.capex` APEX; capex decompression
  fails on this setup, so all 24 were converted to plain `.apex` inside `system`
  (system ext4 grown to ~2800 MiB). Without this, tethering/ART/adbd never activate
  and init reboots with `netbpfload-missing`.
- **Audio HAL:** kernel has no audio, but `system_server` aborts if no audio HAL is
  found. Workaround: a hand-written AIDL effects-factory stub (`work/effstub/`,
  installed as `sc_effstub`) + patched `libaudiohal.so` (skip the type/major match)
  + VINTF manifest edits so HIDL 7.0 devices + AIDL effects satisfy `FactoryHal`.
  Result: boot proceeds; there is still no actual sound.
- **Wi-Fi rc:** A16 init drops vendor `init.ranchu.rc` services that lack a `user`
  line, so a `sc_wpa_supplicant` service is added in `sc-sandcastle.rc` with the
  supplicant interface HAL lines. Every rc `exec` needs a `seclabel` or A16 init
  refuses it.
- **/sdcard / media:** `media.omx` (A10 seccomp) crashes under A16 bionic; it was
  disabled and the vendor manifest entry renamed so A16 uses the Codec2 swcodec
  apex, unblocking StorageManagerService/`/sdcard`.

## Graphics driver (vulkan.pastel.so)

- Built from SwiftShader for Android arm64, 16 KB pages, static libc++, with an
  AHardwareBuffer external-memory path. See `docs/BUILD.md`.
- HWUI (skiavk) asserts `queueCount>=2`; the driver was patched to advertise 2
  queues. The shipped `vulkan.pastel.so` is that fixed build.
- Runtime selection lives in `patch-vulkan/sc-render.sh`; `ro.hardware.vulkan`
  points the Vulkan loader at the driver (installed as `vulkan.pastel.so`).

## Performance / thermal

- 2 GB RAM, 2 usable cores, no swap by default → zram (`lzo-rle`, ~1.2 GB).
- No cpuidle driver → the SoC idles at a high clock and runs hot. `sc-thermal.sh`
  reads battery temperature and steps `scaling_max_freq` down (41 °C→1644 MHz,
  43→1056, 46→756; full speed ≤38). `sc-cpucap.sh` re-applies the cap (it resets
  itself after screen-off).

## Deploy / on-device gotchas

- Signatures for tweaks/libs must be produced **on the device** (macOS-side ldid /
  codesign are rejected by iOS 15). Not relevant to Android, but relevant if you
  touch the iOS side.
- `patch-vulkan/apply.sh` edits `nand-a16`'s ext4 partitions via `debugfs` inside a
  colima Linux VM (loop devices at the offsets in `docs/ARCHITECTURE.md`). Always
  `colima ssh -- sudo fstrim -av` after builds — the VM disk grows on the Mac.
- Back up before image edits: `cp -c nand-a16 nand-a16.bak-…` (APFS clone, cheap).
