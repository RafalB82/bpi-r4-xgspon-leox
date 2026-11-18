# References

## Official documentation

- LeoLabs datasheet, LXE-010S-H XGSPON ONU stick (Rev1.0, Dec 2025):
  https://leolabs.pl/assets/docs/data_sheets/lxe-010s-h_datasheet.pdf
  - pinout: pin 6 MOD_DEF0 asserted low only after µC/I²C init
  - 3.3 V ±5 %, max 900 mA (< 3 W)
  - Tx_FAULT/Rx_LOS are uncommitted / open-collector pins
  - host interface XFI / 10GBASE-R, optics SC/APC, TX 1270 nm, RX 1577 nm

## Reverse-engineering and community documentation

- Hack GPON — HiSense LTF7267-BHA+ (same Cortina CA8271S hardware, documents
  the `scfg.txt` mechanism, `app-cli` on port 2233, activation state, OMCI
  settings, known USXGMII issue):
  https://hack-gpon.org/xgs/ont-hisense-ltf7267-bha+/
- Hack GPON — LEOX LXT-010S-H (GPON sibling, credential conventions):
  https://hack-gpon.org/ont-leox-lxt-010s-h/
- Hack GPON — ONT access methods:
  https://deepwiki.com/hack-gpon/hack-gpon.github.io/3.1-access-methods
- YuukiJapanTech CA8271x repository (firmware dumps, UART docs):
  https://github.com/YuukiJapanTech/CA8271x
- SFP quirks were adapted from:
  https://github.com/woziwrt/bpi-r4-deploy

## Operator-specific notes (Orange Poland)

- Orange authenticates ONTs by PON SN (4 vendor letters + 8 hex digits), not
  by MAC. `SMBS` is the Sagemcom vendor ID used on Orange ONTs.
- Some deployments also use a PLOAM password or LOID. Our Nokia/Alcatel OLT
  accepted SN + MAC + firmware version only, with an empty PLOAM password.
- The OLT may disable the local management interface (LCT, ITU-T G.988 ME 256)
  once the ONU reaches O5.

## Useful commands on the module

```
leox print                          # show current identity
cat /config/scfg.txt                # user overrides
cat /config/default_scfg.txt        # manufacturer defaults
nc <module-ip> 2233                 # Cortina app-cli (only while LCT is enabled)
```

Inside `app-cli`:

```
enable
config
aal
xgpon
show activation_state 0             # O5.1, ONU ID, vendor ID/VSSN

enable
config
omci
show info                           # OMCC, OLT type, LOID, VLANs
```
