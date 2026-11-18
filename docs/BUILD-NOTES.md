# Build notes

These notes describe the exact sequence used for the tested build. Adapt paths
and package selection to your own tree; the patches themselves are independent
of the package set.

## Reference environment

```
OpenWrt          : 25.12-SNAPSHOT
commit           : 94814b08622b8d13b4c4dbb16868b8d112733906 (2026-11-12)
kernel           : 6.12.116  (hash cb3ed3dfdd47e6ade49dc933db334fd86e24cadee920da612c262b0e9b6a511b)
target/profile   : mediatek/filogic — DEVICE_bananapi_bpi-r4 (single profile)
arch             : aarch64_cortex-a53, CONFIG_CPU_TYPE=cortex-a53
feeds            : mtk-openwrt-feeds @ 2c4d23e, plus fantastic_packages
host             : x86_64 Debian, 8 GB RAM, make -j4
```

Selected config options (not required for the SFP patches, but part of the
tested build):

```
CONFIG_OPENSSL_OPTIMIZE_SPEED=y     # OpenSSL -O3
CONFIG_PACKAGE_kmod-nvme=y          # Docker data on NVMe
CONFIG_PACKAGE_samba4-server=y      # SMB via Samba4, not ksmbd
```

No CPU retune, no overclock, no SQM/governor/HZ/PREEMPT/BBR changes.

## Steps

1. Prepare a clean OpenWrt tree with your usual workflow (for example
   `autobuild.sh clean` followed by `autobuild.sh <profile> prepare`).
2. Restore your `.config` and run `make defconfig`.
3. From this repository, install the patches:

   ```sh
   OPENWRT_DIR=/path/to/openwrt-25.12 ./scripts/apply-patches.sh --check
   OPENWRT_DIR=/path/to/openwrt-25.12 ./scripts/apply-patches.sh
   ```

   The script copies `999-*.patch` into
   `target/linux/mediatek/patches-6.12/` (the build system applies them to the
   kernel during `make`) and applies `0001-*.patch` at the OpenWrt root.

4. Build:

   ```sh
   cd /path/to/openwrt-25.12
   make -j4
   ```

5. Verify:

   ```sh
   /path/to/openwrt-bpi-r4-xgspon-leox/scripts/verify-build.sh
   ```

   Expected checks:

   - DTB strings contain `sfp1-force-power` and `sfp2-force-power`
   - no `mod-def0-gpios` remains in the BPI-R4 DTS/DTSI
   - `sfp.ko` contains all six module IDs, including `LEOX` / `LXE-010S-H`

6. Artifacts appear under
   `bin/targets/mediatek/filogic/`:

   - `openwrt-mediatek-filogic-bananapi_bpi-r4-squashfs-sysupgrade.itb`
   - `openwrt-mediatek-filogic-bananapi_bpi-r4-sdcard.img.gz`

## Re-applying after a tree reset

`autobuild.sh clean`/`prepare` may restore the tree to HEAD. Simply re-run
`apply-patches.sh`. It is idempotent for the root-level patch (detects an
already-applied patch via reverse dry-run) and overwrites the kernel patch
files with identical copies.

## Flashing

- Prefer `sysupgrade` **without** `-n` to preserve configuration.
- Insert the LEOX module in the SFP+ WAN port **before** rebooting: forced
  presence means a module inserted after boot is never probed.
- After reboot, allow ~20–30 s for ONU activation before PPPoE starts.
