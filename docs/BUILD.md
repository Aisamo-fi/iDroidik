# Building from source

You don't need this to *run* Android — prebuilt binaries are fetched per
`MANIFEST.md`. Use this to rebuild the kernel, the loaders, or the graphics driver.

All builds assume macOS + [colima](https://github.com/abiosoft/colima) (a Docker/
Linux VM). After any build: `colima ssh -- sudo fstrim -av` (the VM disk grows on
the Mac, and disk space here is tight).

## Kernel (Sandcastle Linux 5.4)

Source = base + our patch + config (this is also the GPL-2.0 corresponding source):
- base: `https://github.com/corellium/linux-sandcastle` @ commit
  `0c2f7dda13d67bb7e06123df516f8bdb1000a79b` (Linux 5.4.14)
- patch: `kernel-patches/idroidik-linux-sandcastle-5.4.14.patch` (legacy binder, cgroup-bpf
  sockopt backport, hx-reboot debug log) — see also `docs/TECHNICAL-NOTES.md`
- config: `work/android16-kernel.config`

```bash
git clone https://github.com/corellium/linux-sandcastle.git && cd linux-sandcastle
git checkout 0c2f7dda13d67bb7e06123df516f8bdb1000a79b
git apply /path/to/kernel-patches/idroidik-linux-sandcastle-5.4.14.patch
cp /path/to/work/android16-kernel.config .config
```

**Compiler must be gcc 7.5** — build in the `kbuild7` container:

```bash
docker build -t sandcastle-kbuild7 kbuild7/     # ubuntu 18.04 + gcc 7.5
# inside it, with the kernel source mounted and work/android16-kernel.config as .config:
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- HOSTCFLAGS=-fcommon -j"$(nproc)" Image
# then LZMA-compress like Android.lzma:
xz --format=lzma --lzma1=preset=9,lc=3,lp=0,pb=2,dict=8MiB -c arch/arm64/boot/Image > Image-a16f.lzma
```

`kbuild/` (gcc 9, ubuntu 20.04) exists only to reproduce the gcc-9 failure — do not
ship kernels from it (they reset the phone to iOS; see TECHNICAL-NOTES).

## Loaders (`loader/pongo-*`)

macOS arm64 binaries built from the C in `loader/`. They need libusb:

```bash
brew install libusb
cc -O2 loader/pongo-linux.c -o loader/pongo-linux $(pkg-config --cflags --libs libusb-1.0)
# likewise pongo-bootr.c, pongo-shell.c
```

`pongo-linux` differs from Corellium's `load-linux.c`: it announces the upload size
so modern pongoOS grows its USB buffer, and it sets `linux_cmdline` explicitly
(new pongo blanks the dtb bootargs). Default cmdline is at the top of the source.

## Graphics driver (`vulkan.pastel.so`, SwiftShader Vulkan)

Source: `https://github.com/google/swiftshader`. Build for Android arm64 with 16 KB
pages, static libc++, and an AHardwareBuffer external-memory path, using the NDK.
Then apply the HWUI fix (advertise `queueCount>=2`). This is involved; the shipped
`vulkan.pastel.so` is the finished, patched build. See TECHNICAL-NOTES → Graphics.

## Small on-device helpers

- `work/effstub/stubs.sh` builds the audio effects-factory stub (`sc_effstub`)
  against tiny link stubs — see the script; needs an aarch64 gcc + linker64 target.
- `work/userdata/build.sh` builds `scdata` (the /data raw-map helper).
- `tools/sotest/sotest.c` — static aarch64 probe for setsockopt behavior.

## Android system image (nand)

The A16 image was made by editing the Sandcastle base image in place (new GSI
system, VNDK, capex→apex, audio/Wi-Fi/media fixes). The reproducible recipe is not
a single script yet — the individual edits are documented in TECHNICAL-NOTES.
`patch-vulkan/apply.sh` shows the debugfs-in-colima pattern used for such edits.
Producing a clean, firmware-free, reproducible image is ROADMAP tasks T0 + T1.
