# Adreno 735 GPU acceleration (lexus)

AERA renders in software unless it can dlopen the Adreno driver
(`/vendor/lib64/egl/libEGL_adreno.so`); then it uses GLES for blur and
compositing. Nothing here changes AERA's behaviour when the driver fails to
load: the software renderer stays the fallback.

Everything comes from CPH2709 OxygenOS 16.0.5.1301 (EX01): libraries readable
over adb were pulled and hash-verified on the phone; the allocator service,
`gen71100_*` firmware and the system-side libraries (libui, libnativewindow,
graphics HIDL interfaces) were cut from the matching OTA with
`tools/erofs_lazy.py` and checked against files with known hashes. The
dependency closure was resolved against the ramdisk file list of a real build,
so nothing the driver needs at load time is missing.

- kernel: `msm_kgsl.ko` from the phone's own vendor_dlkm, via AERA_LOAD_VENDOR_MODULES
- firmware: `vendor/firmware/gen71100_{sqe.fw,gmu.bin,zap.mbn}` (Adreno 735 = gen7_11_0)
- userspace: EGL/GLES2, eglSubDriverAndroid, gralloc/mapper 4.0, allocator service
- `aera-gpu-probe` (from AERA's OnePlus 12 tree) renders one known pixel to an EGL
  pbuffer and reads it back: a single end-to-end check of KGSL, firmware, EGL
  and the shader compiler before hardware rendering is trusted

Wiring follows AERA's POCO F6 (peridot) tree, which runs the same Adreno 735.
