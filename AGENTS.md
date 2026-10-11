# AGENTS.md — orientation for an AI agent (or new human) continuing this project

You are picking up a working-but-unfinished port of **Android 16 to the iPhone 7**.
This file tells you what exists, how to work on it safely, and what to do next.
Read it fully before touching anything.

## Mission

Make Android on the iPhone 7 good enough for anyone to install, and finish the
public release. The maintainer has stepped back; you are expected to continue the
work with minimal hand-holding. "Good" means: legal, one-command install, honest
docs, and the polish items in `ROADMAP.md` addressed.

## Read these first, in order

1. `docs/STATE.md` — ground truth of what works, what doesn't, and **hard
   constraints you must not violate**.
2. `ROADMAP.md` — the prioritized task list. Each task is self-contained.
3. `docs/ARCHITECTURE.md` — how the boot chain and the `nand` image fit together.
4. `docs/TECHNICAL-NOTES.md` — the non-obvious fixes (don't re-derive them).
5. `docs/FIRMWARE-AND-LEGAL.md` — the firmware/legality rules (release blocker T1).

## Safety rules (violating these can brick the device or break the law)

- **Never** restore, erase, or factory-reset the iPhone. iOS must always still boot
  (`palera1n -n`). Setup only ADDS an APFS volume; a restore would wipe the device.
- iOS and Android **share one APFS container**. Do not enable experimental APFS
  write in the kernel; it endangers the iOS volume. The kernel APFS driver is
  read-only on purpose.
- **Never distribute Apple firmware.** Any public image must be firmware-free
  (see `docs/FIRMWARE-AND-LEGAL.md`).
- Never commit `data/`, `logs/`, `config.env`, or anything with a Wi-Fi PSK or
  personal path. `.gitignore` blocks the obvious cases; still check your diffs.
- On a running Android over adb: never `pkill -f <pattern>` (it kills the adb shell
  itself — use `pidof`); never restart `servicemanager`/`hwservicemanager` (drops
  the phone).
- Confirm destructive or outward-facing actions (publishing, flashing, deleting)
  with the maintainer before doing them.

## The environment

- Host is a **Mac**; disk space is chronically tight — check `df -h` before large
  operations and clean up after (`colima ssh -- sudo fstrim -av`).
- Builds run in **colima** (Docker/Linux VM): `kbuild7` (gcc 7.5) for the kernel,
  a SwiftShader container for the GPU driver. See `docs/BUILD.md`.
- The phone talks to the Mac via **checkm8/palera1n → PongoOS**, then **ADB** (USB
  gadget, plus ADB-over-Wi-Fi for bulk transfers).
- Personal/machine values live in `config.env` (git-ignored); scripts read it.
  Never hard-code an IP, path, or password back into a script.

## Common workflows

- **Boot Android:** `./android.sh` (needs the phone + DFU button dance).
- **Change the system image:** edit files into `nand-a16` via the debugfs-in-colima
  pattern in `patch-vulkan/apply.sh`, back up first with `cp -c`, update
  `nand-a16.sha256`, then `./android.sh deploy`.
- **Change runtime behavior (no reboot):** the `sc-*.sh` scripts in `patch-vulkan/`
  are pushed by `./android.sh tune`.
- **Rebuild the kernel:** `docs/BUILD.md` — gcc 7.5 only, LZMA-compress.

## Conventions

- Keep `docs/STATE.md` current — it is the status contract. Update it in the same
  change that alters behavior.
- Prefer small, verifiable, on-device-tested changes. Much of this was found by
  bisection; assume nothing works until you see it on the phone.
- When you learn a new hard constraint, add it to `docs/STATE.md` and/or
  `docs/TECHNICAL-NOTES.md` so the next agent doesn't relearn it.
- Big binaries never go in git — add them to `MANIFEST.md` instead.

## Where to start

If unsure, start with **ROADMAP task T0** (reconcile the image — no phone needed),
then **T1** (strip Apple firmware — the release blocker), then **T2** (image hosting
+ flasher). T3–T6 are polish and need the phone.
