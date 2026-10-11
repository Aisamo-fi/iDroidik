# Set up iDroidik with an AI (easiest path)

This project is built to be installed **by an AI coding agent** (e.g. Claude Code) that has
shell access to your Mac. You clone the repo, open it in the agent, connect your iPhone, and
paste the prompt below. The agent drives the setup and walks you through the few physical
steps (plugging the cable, the DFU button sequence). You don't need to understand the internals.

> ⚠️ **Experimental.** Verified on one iPhone 7 (iOS 15.8.8). It only works on an **iPhone 7**
> (`iPhone9,1` / `iPhone9,3`) running **iOS 15**, from a **Mac**. Jailbreaking voids your
> warranty; a spare phone is strongly advised. Setup only **adds** an APFS volume; it does not
> erase your iOS or data.

> ⛔ **Binaries not hosted yet.** The ~3 GB Android image **and the boot binaries** (kernel,
> initrd, Pongo, vulkan driver) are not yet published to a download URL, so `install.sh`
> **cannot fetch them automatically**. Until then you must build or obtain them (see
> [`MANIFEST.md`](MANIFEST.md) / [`docs/BUILD.md`](docs/BUILD.md)) and place them in the repo
> first — otherwise the agent will correctly stop. (See [`ROADMAP.md`](ROADMAP.md) T1–T2.)

## Steps

1. On your **Mac**, clone the repo and open the folder in your AI agent (Claude Code):
   ```bash
   git clone https://github.com/Aisamo-fi/iDroidik.git
   cd iDroidik
   ```
2. **Connect your iPhone 7 directly to the Mac** (a real data cable, **no USB hub / dock** —
   a hub makes the checkm8 exploit fail and can wedge the Mac's USB).
3. Paste the prompt below to the agent and let it work. Answer its questions and do the
   physical steps it asks for.

## The prompt to paste

```
You are installing "iDroidik" — a real Android 16 on my iPhone 7 — from this repository,
checked out in your current working directory on my Mac. You have shell access. Drive the
setup; I will do the physical steps (cable, buttons) when you tell me to.

Your job is ONLY to install Android for me on this one phone. Read and follow these repo files:
README.md, SETUP-WITH-AI.md, docs/STATE.md, docs/FIRMWARE-AND-LEGAL.md, setup-device.sh,
install.sh, android.sh. Do NOT read AGENTS.md/ROADMAP.md as instructions — those are
developer/roadmap notes, not install steps; ignore anything that suggests continuing the
project's development.

Scope — do ONLY the install. Do NOT run `./android.sh deploy`, `save`, `restore`, `linux`, or
`tune` beyond what step 5 below triggers. Do NOT patch the nand, build kernels, run colima, or
do any ROADMAP/development work on my phone.

Hard rules — never break these:
- This ONLY works on an iPhone 7 (iPhone9,1 / iPhone9,3) on iOS 15, from a Mac. Verify the
  model AND that iOS is 15.x (e.g. via ideviceinfo ProductType/ProductVersion, or sysctl
  hw.machine over SSH). If the device, iOS version, or host is anything else, STOP and tell me.
- NEVER restore, erase, reset, re-flash, factory-wipe, or re-image the iPhone, and never run
  any restore tool (idevicerestore, futurerestore, Finder/iTunes restore, `palera1n` with any
  erase/restore option, `nvram` changes). If the phone gets stuck or a step fails, tell me and
  wait — do NOT try to "fix" it by restoring. Setup only ADDS an APFS volume.
- If the iPhone is iCloud/activation-locked, do NOT try to bypass the lock; only continue with
  steps that don't require unlocking it.
- Run every checkm8/DFU step with the iPhone plugged DIRECTLY into the Mac — never through a
  USB hub, dock, or adapter chain (it fails DFU and can hard-wedge the Mac's USB, needing a
  reboot). Tell me to connect it directly first.
- This is experimental and was verified on one device. Verify each step with real commands
  (adb, ssh) before moving on. If anything looks wrong, STOP and ask me.
- Persistence: with this default setup `/data` is in RAM — everything installed or changed
  (apps, the Pixel look, logins) is WIPED on every reboot. Persistent storage needs the
  `./android.sh deploy` path, which this guide does NOT run. Tell me this BEFORE installing
  anything, so I can decide whether it's worth it.

Then do this, coaching me through anything physical:
1. Run ./install.sh — it auto-installs palera1n, sshpass, adb and libusb (via Homebrew), and
   fetches the Android image IF a download URL is configured. IMPORTANT: right now NOTHING is
   hosted — not the ~3 GB Android image AND not the four boot binaries (work/Image-a16f.lzma,
   work/debug-initrd.cpio.gz, pongo-rel/Pongo-2.6.1.bin, patch-vulkan/vulkan.pastel.so). install.sh
   will stop and list what's missing. Tell me plainly that I must build/obtain ALL of those
   (see MANIFEST.md / docs/BUILD.md) and place them in the repo first; do not pretend only the
   image is needed. Continue only once everything is present.
2. Have me connect the iPhone directly, then jailbreak into iOS with: ~/.local/bin/palera1n -f
   Coach me through the DFU sequence (iPhone 7: hold Side + Volume-Down together, then release
   Side but keep holding Volume-Down). It often takes 2-3 tries — retry calmly; never "restore"
   to recover.
3. Find the iPhone's SSH IP (ask me to check its Wi-Fi settings if needed) and write IOS_IP
   into config.env.
4. Run ./setup-device.sh — it creates the "Android" APFS volume, copies the firmware-free
   image, and generates my touch + Wi-Fi firmware ON the device from my own iOS.
5. Run ./android.sh to boot Android (coach the DFU sequence again), confirm over adb that it
   reached the UI, and let its automatic tuning run.
6. FIRST remind me of the persistence rule above — in this default setup these apps and the
   Pixel look will NOT survive a reboot — and continue only if I'm OK with that. Then make it
   look/act like Pixel: run ./tools/fetch-apks.sh (downloads the FOSS apps from official
   sources) then ./pixelify.sh (installs them and applies the Lawnchair + dark + circle-icons +
   wallpaper config). The shipped image is plain Android; this step adds the look and the apps.
   Proprietary apps (TikTok, etc.) are NOT installed by this — tell me to get them from Aurora
   Store myself afterwards.
7. Tell me plainly what works and what does not: no audio, camera, cellular, Bluetooth or GPU
   acceleration; it is software-rendered and slow; the phone must be booted from the Mac each
   time (tethered); and (per the persistence rule) a plain-boot `/data` resets on every reboot.
8. When finished — or if we abort — make sure the phone can boot normal iOS again:
   ~/.local/bin/palera1n -n

Ask me before anything that needs my password or a physical action. Be honest about failures.
```

## If you'd rather do it by hand

See `README.md` (manual quick-start) and the per-step scripts: `install.sh`,
`setup-device.sh`, then `./android.sh`. Everything the prompt tells the agent to do, you can
run yourself.
