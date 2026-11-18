# Why these patches are necessary

## The module is an ONU, not a transceiver

A normal SFP+ module contains a laser and maybe a PHY. Its EEPROM advertises
link modes (`10GBASE-SR`, `10GBASE-LR`, `10GBASE-CR`, ...), the kernel reads
those bits and picks `10gbase-r` automatically. Pin 6 (`MOD_DEF0`) is wired to
GND inside the module, so insertion is detected electrically and the host
applies power.

The **LEOX LXE-010S-H** is different:

- Cortina **CA8271S** network processor, 128 MB RAM/flash, its own Linux
  (4.14.275 in our sample), PON MAC, OMCI, PLOAM, FEC, DBA, AES and a 4K-entry
  L2 switch. The host only sees a 10GBASE-R port.
- Its EEPROM contains the vendor/model string `LEOX / LXE-010S-H` but **no
  compliance bits and no extended compliance code**. The kernel therefore
  reports `no common interface modes`.
- The datasheet says about pin 6:

  > *"MOD_DEF0 — Presence Pin, the MOD_DEF0 Signal set to low level **after
  > initialisation of µC and power up the I2C interface**"*

  The pin is actively driven by firmware, not hard-grounded. On the BPI-R4,
  `MOD_DEF0` also gates `3.3V_SFP` through Q12. Result: no power -> no µC boot
  -> no MOD_DEF0 -> no power.

- `Tx_FAULT` and `LOS` are listed as *"uncommitted"* pins needing 4.7–10 kΩ
  pull-ups to 3.3 V; `Rx_LOS` is open collector/drain. They are not reliable
  status signals on this stick. The kernel saw false `tx_fault` and tried to
  poll a soft status that does not exist (`-ENXIO`).

## What each patch does

### 1. `999-dts-bpi-r4-sfp2-force-present.patch`

- Removes `mod-def0-gpios` from `sfp2` in `mt7988a-bananapi-bpi-r4.dts`
  (GPIO83).
- Removes `mod-def0-gpios` from **both duplicated `sfp1` nodes** in
  `mt7988a-bananapi-bpi-r4.dtsi` (GPIO82). The MediaTek feed adds this node
  twice; leaving one copy would make the driver request the GPIO and conflict
  with the hog.
- Adds two `gpio-hog` entries on `&pio`, both `output-low`:
  - `sfp1-force-power` (GPIO82, `UART1_CTS` alternate function for Q12)
  - `sfp2-force-power` (GPIO83)

Effect: both cages are powered and reported `present` from boot. A module
must be inserted **before** boot; hot-swap is not detected.

### 2. `999-sfp-10-additional-quirks.patch`

Adds six quirks to `drivers/net/phy/sfp.c`:

| Vendor | Model | Fixup |
|---|---|---|
| Zaram | ZXOS11NPI | `ignore_tx_fault` |
| HSGQ | NU-STICK1.0 | `halny_gsfp` |
| OEM | XGSPONST2000 / XGSPONST2001 | `halny_gsfp` |
| LEOX | LXE-010S-H | `quirk_10gbase_r` + `ignore_tx_fault_and_los` |

`sfp_quirk_10gbase_r()` sets `10000baseSR` in the link-mode bitmap and
`PHY_INTERFACE_MODE_10GBASER` in the interface bitmap. Without it the module
is rejected with `no common interface modes`.

`sfp_fixup_ignore_tx_fault_and_los()` is preferable to the older
`sfp_fixup_halny_gsfp` trick: the latter only masks the hardware pins, which
makes the kernel fall back to polling the soft status in the EEPROM and report
`-ENXIO` plus a false `tx_fault`. `ignore_tx_fault_and_los` sets
`state_ignore_mask` so both signals are ignored in HW **and** soft status.

This function already exists in mainline Linux 6.12 — the patch only uses it.

### 3. `0001-bpi-r4-restore-sdcard-artifacts.patch`

Not related to the SFP itself. The MediaTek feed removes the `sdcard.img.gz`
and `emmc-*`/`snand-*` artifacts from `filogic.mk`. This patch restores them so
a flashable SD image can be built alongside the sysupgrade image. It is an
**OpenWrt-root** patch (applied with `patch -p1` from the OpenWrt directory),
not a kernel patch.

## Observed result

A successful boot with the LEOX in `sfp-wan` produced:

```
sfp sfp1: module LEOX LXE-010S-H rev V1.0 has been found in the quirk list
sfp sfp1: sfp: support mode 00,00000000,00000800,00006440
sfp-wan: requesting link mode inband/10gbase-r
sfp-wan: switched to inband/10gbase-r link mode
sfp-wan: Link is Up - 10Gbps/Full
br-wan: port 2(sfp-wan) entered forwarding state
```

Inside the module, after plugging the fibre:

```
pre_state O4 new_state O5.1!
EVENT: ONU Active(onuid = 65543)
Set TCONT 1/2/3 to be Enable, Alloc-ID 1025/1026/1027
```

No `no common interface modes`, no `module persistently indicates fault`, no
`failed to read SFP soft status: -ENXIO`.

## Local management and OMCI

After the ONU reaches O5, the OLT can disable the Local Craft Terminal via
OMCI (ME 256) — in our deployment the module stopped answering at
`192.168.100.1`. This is expected and desirable in production. To regain
access, unplug the fibre for ~60 s so the ONU falls back to O1/O2.

The Cortina CLI (`app-cli`) is also reachable directly over telnet on
**port 2233** of the module management IP. Useful commands:

```
enable
config
aal
xgpon
show activation_state 0        # PON mode, VendorID/VSSN, S/W FSM state, ONU ID

enable
config
omci
show info                      # OMCC version, OLT type, LOID, VLAN info
```

## The real hardware fix

Ground pin 6 of the module to GND (or redesign the carrier so SFP power is
not gated by MOD_DEF0). Then:

- no `gpio-hog` is needed,
- no DTS patch is needed,
- hot-swap works normally,
- only the `sfp.c` EEPROM quirk may still be required for link-mode detection.
