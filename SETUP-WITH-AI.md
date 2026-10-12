# Set up iDroidik with an AI (easiest path)

This project is built to be installed **by an AI coding agent** (e.g. Claude Code) that has
shell access to your Mac. You clone the repo, open it in the agent, connect your iPhone, and
paste the prompt below. The agent drives the setup and walks you through the few physical
steps (plugging the cable, the DFU button sequence). You don't need to understand the internals.

> ⚠️ **Experimental.** Verified on one iPhone 7 (iOS 15.8.8). It only works on an **iPhone 7**
> (`iPhone9,1` / `iPhone9,3`) running **iOS 15**, from a **Mac**. Jailbreaking voids your
> warranty; a spare phone is strongly advised. Setup only **adds** an APFS volume; it does not
> erase your iOS or data.

> 📦 **Binaries are hosted.** The ~3 GB Android image (split) **and the boot binaries** (kernel,
> initrd, Pongo, vulkan driver) are published on the `v0.1-exp` GitHub release, and `install.sh`
> fetches them automatically and verifies each against a pinned SHA-256. You normally don't need
> to build anything — just run `install.sh`. (To build from source instead, see
> [`MANIFEST.md`](MANIFEST.md) / [`docs/BUILD.md`](docs/BUILD.md).)

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
- Persistence: `setup-device.sh` provisions a persistent `/data` by default (a ~6 GB
  `userdata.img` on the Android volume), so apps, the Pixel look and logins SURVIVE reboots.
  If the phone is low on free space it automatically falls back to a RAM `/data` (wiped on
  reboot) and says so; `NO_PERSIST=1 ./setup-device.sh` forces RAM, `USERDATA_GB=N` sizes it.
  After setup-device.sh runs, tell me which mode actually happened (persistent vs RAM).

Then do this, coaching me through anything physical:
1. Run ./install.sh — it auto-installs palera1n, sshpass, adb and libusb (via Homebrew), then
   fetches the ~3 GB Android image (split) AND the four boot binaries (work/Image-a16f.lzma,
   work/debug-initrd.cpio.gz, pongo-rel/Pongo-2.6.1.bin, patch-vulkan/vulkan.pastel.so) from the
   v0.1-exp GitHub release, verifying each against a pinned SHA-256. If a download fails or a
   checksum doesn't match, install.sh stops and says what's wrong — tell me plainly and don't
   continue until everything is present and verified. (Building from source is optional — see
   MANIFEST.md / docs/BUILD.md.)
2. Have me connect the iPhone directly, then jailbreak into **rootful** iOS. On a device that
   has NEVER been jailbroken this way, the FIRST time also creates the fakefs and installs the
   bootstrap/SSH — follow palera.in's rootful instructions (it can take a couple of passes and
   reboots). On an already-set-up device, `~/.local/bin/palera1n -f` boots straight into it.
   Coach me through the DFU sequence (iPhone 7: hold Side + Volume-Down together, then release
   Side but keep holding Volume-Down). It often takes 2-3 tries — retry calmly; never "restore".
   (This project was verified on a device already jailbroken rootful with OpenSSH; a fresh
   device needs that one-time setup first — see https://palera.in.)
3. Confirm root SSH works — the whole setup drives the phone over `ssh root@<iPhone>` (default
   password `alpine`). If SSH is refused, OpenSSH isn't installed/running on the jailbroken iOS:
   rootful palera1n normally sets it up; otherwise I install it from Sileo. STOP and tell me if
   SSH doesn't answer. Then find the iPhone's SSH IP (ask me to check its Wi-Fi settings if
   needed) and write IOS_IP into config.env.
4. Run ./setup-device.sh — it creates the "Android" APFS volume, copies the firmware-free
   image, generates my touch + Wi-Fi firmware ON the device from my own iOS, and provisions a
   persistent /data (userdata.img) by default. Read back whether it provisioned persistence or
   fell back to RAM (low space) and tell me which.
5. Run ./android.sh to boot Android (coach the DFU sequence again), confirm over adb that it
   reached the UI, and let its automatic tuning run.
6. Make it look/act like Pixel: run ./tools/fetch-apks.sh (downloads the FOSS apps from official
   sources) then ./pixelify.sh (installs them and applies the Lawnchair + dark + circle-icons +
   wallpaper config). The shipped image is plain Android; this step adds the look and the apps.
   If persistence was provisioned in step 4, this look and these apps survive reboots; if it fell
   back to RAM, remind me they will reset on the next boot. Proprietary apps (TikTok, etc.) are
   NOT installed by this — tell me to get them from Aurora Store myself afterwards.
7. Tell me plainly what works and what does not: no audio, camera, cellular, Bluetooth or GPU
   acceleration; it is software-rendered and slow; the phone must be booted from the Mac each
   time (tethered); and if persistence fell back to RAM in step 4, `/data` resets on every reboot.
8. When finished — or if we abort — make sure the phone can boot normal iOS again:
   ~/.local/bin/palera1n -n

Ask me before anything that needs my password or a physical action. Be honest about failures.
```

## If you'd rather do it by hand

See `README.md` (manual quick-start) and the per-step scripts: `install.sh`,
`setup-device.sh`, then `./android.sh`. Everything the prompt tells the agent to do, you can
run yourself.
