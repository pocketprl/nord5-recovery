# AERA Recovery device tree for OnePlus Nord 5 (lexus)

Unofficial, **alpha, untested on hardware**. Targets CPH2709 (global/EU, `prjname 24881`)
and should also cover CPH2707.

| | |
|---|---|
| SoC | Snapdragon 8s Gen 3 (SM8635 "cliffs", `pineapple` platform) |
| Display | 1272x2800, 120 Hz |
| Touch | Synaptics S3910 on-cell (Tianma) |
| Wi-Fi | qca6750 (same as POCO F6 / peridot) |
| GPU | Adreno 735 (gen7_11_0) |
| Partitions | A/B + dedicated `recovery_[ab]`, virtual A/B, FBEv2 + metadata encryption |

## Where everything comes from

Nothing here is guessed. Each value traces back to one of these:

- [TeamWin/android_device_oneplus_lexus](https://github.com/TeamWin/android_device_oneplus_lexus): official TWRP, which targets CPH2709.
  The ramdisk blobs (decryption stack, haptics, touch firmware), module list, fstab, brightness path and CPU temp zone all come from here.
- [LineageOS/android_device_oneplus_lexus](https://github.com/LineageOS/android_device_oneplus_lexus) + sm8650-common: partition sizes, screen size,
  Wi-Fi chip, GPU generation, A/B list, encryption options.
- AERA `waffle` (OnePlus 12) and `peridot` (POCO F6, same SoC): AERA flag layout and OxygenOS `my_*` partitions.

Values marked `VERIFY` get checked on hardware by `tools/01-first-contact.sh`.

The decryption/security stack (keymint, gatekeeper, qseecomd, qwesd, ssgtzd, boot, health,
vibrator) and its 60-library closure come from **CPH2709 OxygenOS 16.0.5.1301 (EX01)** itself.
Readable files were pulled over adb from a locked phone and hash-verified. The ones SELinux hides
from the shell (`tools/selinux-locked-files.txt`) were cut out of the matching OTA by
`tools/erofs_lazy.py` and checked against files with known hashes. Service init and start order
follow AERA's OnePlus 12 tree, which runs the same stack.

Fixed relative to the upstream TWRP tree:
- Its blobs are Android 15; 61 of 117 differed from OxygenOS 16 and the gatekeeper it starts no longer exists
- `init` started a nonexistent `boot-hal-1-2` while the real AIDL `boot-qti` was commented out
- `init` started a nonexistent `health-hal-2-1` instead of the `health-default` service that actually exists
- `variant-script.sh` had a stray `;;` after `esac`, a syntax error, so it never set the model props

## Phases

1. **Base** (this tree): display, touch, ADB/MTP/fastbootd, FBE decryption, haptics, flash/backup.
   Feature parity with official TWRP, inside AERA.
2. Wi-Fi (`qca6750` + `icnss2`, following peridot), Adreno 735 GPU acceleration, audio.

## Build

CI: run the **Build AERA (lexus)** workflow (Actions tab -> Run workflow). The image ends up in a prerelease.

Local:
```bash
repo init -u https://github.com/AERA-Recovery/android_manifest.git -b aera-16.0 --depth=1
repo sync -c --no-tags --no-clone-bundle --optimized-fetch -j8
git clone <this repo> device/oneplus/lexus
source build/envsetup.sh
lunch twrp_lexus-bp2a-eng
mka adbd recoveryimage
```

Before pushing, `tools/aera-lint.sh <bootable/recovery> <vendor/recovery>` checks the tree against AERA's
sources (unknown flags, combinations AERA rejects, missing filesystem types). CI runs the same check
before the long build.

## Bring-up runbook (`tools/`)

| Step | Phone state | Script | Writes to phone? |
|---|---|---|---|
| 1 | bootloader | `01-first-contact.sh`: getvar dump, checks partition sizes against the tree | no |
| 2 | official TWRP flashed, booted | `02-backup.sh`: sizes first, then persist/EFS/modem/oplus* and every small partition to the PC | no |
| 3 | TWRP | `03-blob-audit.sh`: compares ramdisk blobs with the phone's firmware; `PULL=1` updates them | no |
| 4 | bootloader | `04-test-image.sh <img>`: flashes **only** `recovery_<slot>`, boots it, collects logs | recovery only |
| loop | - | `05-repack.sh <img>`: overlays `recovery/root` changes into an image without a rebuild | no |

### Getting blobs without unlocking

```bash
# Partition table of a remote OTA (reads ~350 KB):
tools/ota_peek.py '<signed OTA url>'
# Files from an erofs partition, fetching only the 2 MB chunks they live in:
tools/erofs_lazy.py '<signed OTA url>' vendor ./ota-cache /bin/qseecomd /firmware/gen71100_zap.mbn
```
Needs `dump.erofs` (erofs-utils) and `strace`. Works for full A/B OTAs whose payload is stored
uncompressed in the zip. OnePlus CDN links are signed and expire within about an hour.

Logs and backups go to `./lexus-device-logs` and `./lexus-device-backup` (both gitignored, since
backups contain IMEI/calibration data). `05-repack.sh` needs `magiskboot` on `PATH` or `MAGISKBOOT=`;
it's `lib/x86_64/libmagiskboot.so` inside the Magisk APK.

Escape hatch: the bootloader lives in ABL and this never touches it. If a test image hangs, hold
**Power + Vol Up** about 10 s, then **Power + Vol Down** for the bootloader, then
`fastboot flash recovery_<slot> <official-twrp.img>`.

**Never** run `fastboot flashing lock` on a modified CPH2709. That's a known hard brick.
