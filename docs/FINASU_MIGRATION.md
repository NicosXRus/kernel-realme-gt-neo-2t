# FinaSU migration status

## Applied

- Removed the old `KernelSU-Next/` kernel component from the working tree.
- Vendored the supplied FinaSU source as `FinaSU/`.
- Wired `drivers/kernelsu` to `FinaSU/kernel`.
- Kept the existing Linux 4.19.191 kernel tree and MediaTek/vendor changes.
- Kept the existing SuSFS 1.5.5 implementation and current config options.
- Removed `CONFIG_KSU_MANUAL_HOOK`, which is not a FinaSU Kconfig option.
- Updated the CI path filter from `KernelSU-Next/**` to `FinaSU/**`.
- Made the kernel build require the FinaSU preinit runner.

## Deliberately not changed

- Existing `fs/*` SuSFS hooks.
- Existing `include/linux/susfs*.h` files.
- Existing SELinux NULL guards and related 4.19 changes.
- Existing kernel ABI/vendor patches.
- Existing companion module.

## Compatibility work performed

- FinaSU's newer SUSFS extension object is **not compiled**. The supplied NeoCore
  SUSFS 1.5.5 implementation already owns the reboot/prctl ABI used by FinaSU's
  userspace, so compiling FinaSU's newer `extension/susfs.c` would introduce
  symbols that do not exist in this 1.5.5 tree.
- FinaSU setuid/sucompat paths were adapted to the existing
  `TASK_STRUCT_NON_ROOT_USER_APP_PROC` marker used by NeoCore's SuSFS 1.5.5.
- FinaSU's 5.x `path_mount()` dependency was given a Linux 4.19 fallback using
  the legacy in-kernel `do_mount()` interface.
- FinaSU's process-mark debug ABI remains wired through its existing tracepoint
  marker implementation.

## Not yet verified

The supplied environment does not contain the AArch64 Android clang toolchain and
the kernel Kconfig build tools available here lack `bison`, so a complete Linux
4.19 kernel compilation cannot be completed in this session.

The next verification must be done in the repository's GitHub Actions environment:

1. merge `stock.config` + `custom_rmx3357.config`;
2. run `olddefconfig`;
3. build `Image.gz` and modules;
4. inspect modpost/compile errors from FinaSU;
5. boot-test the resulting image before flashing as a release.

## Manager signature

FinaSU validates the Manager certificate at kernel level. Do not invent a
signature hash. Build the intended FinaSU Manager APK, extract its signing
certificate size and SHA-256, and pass those values as `KSU_EXPECTED_SIZE` and
`KSU_EXPECTED_HASH` (or use the second release signature slot).
