# Unlock day runbook (CPH2709)

Everything in this tree was matched to **OxygenOS 16.0.5.1301 (EX01)**: the
decryption stack, GPU stack, kernel modules and panel values. A different build
on the phone means re-checking blobs before flashing anything.

## Before the day

- [ ] **Turn off automatic system updates** (Settings > System > Software update).
      An OTA before unlock day changes the blobs this tree was built against.
- [ ] Move 2FA apps, eSIM and anything else to the new phone.
- [ ] Sign out of Google, OnePlus account and Find My Device on the Nord 5.
- [ ] Developer options: **OEM unlocking** on, **USB debugging** on.
- [ ] On the PC, in `~/aera-lexus/images/`:
  - `twrp-3.7.1_12-0-lexus.img`: official TWRP, PGP-verified. Known-good fallback.
  - `stock-recovery-CPH2709_16.0.5.1301-EX01.img`: back to exactly stock.
  - the latest AERA image from CI releases or `tools/local/build.sh`.

## Escape hatches (any step)

| Situation | Do this |
|---|---|
| Screen black/frozen, no adb | Hold **Power + Vol Up** ~10 s, then **Power + Vol Down** for the bootloader |
| Bad recovery image | Bootloader: `fastboot flash recovery_<current slot> images/twrp-…img` |
| Want stock back | same, with `images/stock-recovery-…img` |
| Anything | **Never** `fastboot flashing lock`. **Never** touch slot b (unbootable since the last OTA). |

The bootloader (ABL) is never flashed by anything here, so the bootloader is
always reachable with Power + Vol Down.

## Steps

| # | Phone state | Who | Action | Expect |
|---|---|---|---|---|
| 1 | Android | me | `adb shell getprop ro.build.display.id` | `CPH2709_16.0.5.1301(EX01)`. Anything else: stop, re-audit blobs. |
| 2 | bootloader | me | `tools/01-first-contact.sh` | sizes OK, `unlocked: no`, slot a |
| 3 | bootloader | **you** | I run `fastboot flashing unlock`; you confirm with the volume keys | phone wipes and reboots |
| 4 | bootloader | you | Power off, then Power + Vol Down | `fastboot getvar unlocked` → `yes` |
| 5 | bootloader | me | `tools/04-test-image.sh images/twrp-3.7.1_12-0-lexus.img` | boots TWRP, image hash verified on the phone |
| 6 | TWRP | me | `tools/02-backup.sh` | persist, EFS, modem, oplus* + small partitions, sha256 on both ends. **Copy the folder off this PC.** |
| 7 | TWRP | me | `tools/03-blob-audit.sh` | ramdisk blobs vs this phone; should be `same` except known [TW] leftovers |
| 8 | bootloader | me | `tools/04-test-image.sh <AERA image>` | AERA boots, hash verified, logs collected |
| 9 | AERA | **you** | Is the screen on and the right way up? Does touch work? | yes/no answers |
| 10 | AERA | me | Read logs: modules, touch device, battery, backlight, thermal zone3, GPU probe | fixes via `05-repack.sh` (seconds) or a rebuild (flags/code) |
| 11 | Android | **you** | Boot Android, finish setup, set a **PIN** | needed to test decryption |
| 12 | AERA | you + me | Enter the PIN in AERA | `twrp.all.users.decrypted=true`, /data readable |

Steps 9–12 repeat as needed. Ramdisk-only fixes (rc files, blobs, props) never
need a build: `tools/05-repack.sh <last image>` and flash.
