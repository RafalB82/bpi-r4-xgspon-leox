# BPI-R4 XGS-PON SFP+ (LEOX LXE-010S-H) — OpenWrt patches

A small, standalone repository with the **patches needed to make the LEOX
LXE-010S-H XGS-PON ONU stick work in the SFP+ WAN port of a Banana Pi BPI-R4**.
It deliberately contains **no OpenWrt source and no MediaTek feed** — only
patches, helper scripts and documentation. Clone it next to your own OpenWrt
tree and apply the patches there.

## What problem it solves

The LEOX LXE-010S-H is not an optical transceiver. It is a complete XGS-PON
ONU (Cortina CA8271S, its own Linux, PON MAC, OMCI) with a 10GBASE-R host
interface. Three properties break a standard OpenWrt SFP setup:

1. **Pin 6 (MOD_DEF0) is not grounded at insertion.** The datasheet says the
   module drives this pin low only *after* its µC boots and I²C starts. On the
   BPI-R4 the same pin gates the 3.3 V supply to the cage (Q12), so the module
   never gets power. -> `gpio-hog` forces both cages on.
2. **The EEPROM declares no interface modes** (no compliance bits), so the
   kernel reports `unsupported SFP module: no common interface modes`.
   -> an `sfp.c` quirk declares `10GBASE-R` explicitly.
3. **TX_FAULT and LOS are uncommitted/open-collector pins** and toggle
   spuriously, producing false `module transmit fault indicated` messages.
   -> the LEOX quirk uses `sfp_fixup_ignore_tx_fault_and_los()`.

See [docs/WHY-THESE-PATCHES.md](docs/WHY-THESE-PATCHES.md) for the full
reasoning and quoted datasheet text.

## Tested with

| Component | Version |
|---|---|
| Board | Banana Pi BPI-R4 (MT7988A / Filogic 880) |
| OpenWrt | 25.12-SNAPSHOT, commit `94814b08622b8d13b4c4dbb16868b8d112733906` |
| Kernel | 6.12.116 |
| MediaTek feed | `mtk-openwrt-feeds` @ `2c4d23e` |
| Module | LEOX LXE-010S-H, firmware `V22.51.1L1` |
| Result | O5.1 registration with a Nokia/Alcatel OLT, PPPoE online |

Requirements:

- A kernel that already contains
  `sfp_fixup_ignore_tx_fault_and_los()` in `drivers/net/phy/sfp.c`
  (mainline 6.12 does; check with `grep` before applying).
- The DTS patch was written against a tree where the MediaTek feed adds the
  `sfp1` node **twice** to `mt7988a-bananapi-bpi-r4.dtsi` (feed patches 188/189).
  If your tree has only one copy, adjust the patch context (remove the second
  hunk) — everything else stays the same.

## Repository contents

```
patches/
  0001-bpi-r4-restore-sdcard-artifacts.patch   # OpenWrt root patch (image/filogic.mk)
  999-sfp-10-additional-quirks.patch            # kernel: sfp.c quirks (6 module IDs)
  999-dts-bpi-r4-sfp2-force-present.patch       # kernel: DTS forced SFP power
scripts/
  apply-patches.sh                              # install / check patches in your tree
  verify-build.sh                               # verify a finished build
  leox-setup.sh                                 # interactive module auth setup (run ON THE ROUTER)
docs/
  WHY-THESE-PATCHES.md
  BUILD-NOTES.md
  REFERENCES.md
```

## Quick start

```sh
git clone <this-repo> openwrt-bpi-r4-xgspon-leox
cd openwrt-bpi-r4-xgspon-leox

# point this at YOUR OpenWrt tree
export OPENWRT_DIR=/path/to/openwrt-25.12

# dry run first
./scripts/apply-patches.sh --check

# install (copies kernel patches, applies the root-level image patch)
./scripts/apply-patches.sh

cd "$OPENWRT_DIR"
make -j$(nproc)

# back in this repo:
./scripts/verify-build.sh
```

Then flash the resulting `*-squashfs-sysupgrade.itb` and **insert the LEOX
module before rebooting** (forced presence disables hot-swap detection).

## Configuring the module for an operator

Because both SFP cages are permanently powered, local management (LCT) of the
stick is reachable at `192.168.100.1` only **before** the ONU registers, or
after unplugging the fibre for ~60 s (OMCI disables the LCT in O5).

Copy `scripts/leox-setup.sh` to the router and run it there. It reads the
current identity, offers to save it to `backup.txt`, then asks step by step for
the values required by the operator (PON SN, MAC, firmware version, OLT type,
OMCC, LOID) and writes them with `leox set`.

Orange Poland (Nokia/ALCL OLT) needs only: PON SN, MAC and the firmware
version string. A PLOAM password was **not** required in our deployment.

## Important caveats

- **Both SFP slots are always powered and reported as `present`.** Replacing a
  module requires a reboot; hot-swap is not detected.
- The DTS patch removes `mod-def0-gpios` from both slots. A module that does
  not drive pin 6 low will still be detected, at the cost of the above.
- The proper hardware fix is to **ground pin 6 of the module to GND** (or use a
  carrier that does not gate power on MOD_DEF0). With that, no `gpio-hog` and
  no DTS patch are necessary; only the `sfp.c` EEPROM quirk may remain.
- A known issue with this class of stick: SFP+ cages that do not support
  USXGMII can log `port 6 isnt USXGMII and can't do AN during activation` and
  cause repeated ONU deactivation/reactivation. Our BPI-R4 showed four
  `Port 6 Link DOWN/UP 10Gbps` events, but the link stabilised after O5.
- If you reflash the module firmware, back up its identity first — firmware
  updates commonly reset the PON SN to the factory default and break OLT
  registration.

## License

Kernel patches are derivative work of the Linux kernel and OpenWrt and are
licensed under **GPL-2.0-or-later**. Scripts and documentation are provided
under the same license. See [LICENSE](LICENSE).

Credits: the SFP quirks were adapted from `woziwrt/bpi-r4-deploy`; hardware
details come from the LeoLabs datasheet and the hack-gpon CA8271x documentation
(see [docs/REFERENCES.md](docs/REFERENCES.md)).
