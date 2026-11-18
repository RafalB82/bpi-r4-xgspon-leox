#!/bin/sh
# Verify that a finished build contains the XGS-PON patches.
#
# Usage:
#   OPENWRT_DIR=/path/to/openwrt ./scripts/verify-build.sh

set -u

die() { echo "ERROR: $*" >&2; exit 1; }

[ -n "${OPENWRT_DIR:-}" ] || die "set OPENWRT_DIR to your OpenWrt tree"
[ -d "$OPENWRT_DIR" ] || die "no such directory: $OPENWRT_DIR"

KDIR=$(ls -d "$OPENWRT_DIR"/build_dir/target-*/linux-mediatek_filogic/linux-6.12.* 2>/dev/null | head -n 1 || true)
[ -n "$KDIR" ] || die "no prepared 6.12 kernel source in $OPENWRT_DIR/build_dir"

DTB="$KDIR/arch/arm64/boot/dts/mediatek/mt7988a-bananapi-bpi-r4.dtb"
DTSI="$KDIR/arch/arm64/boot/dts/mediatek/mt7988a-bananapi-bpi-r4.dtsi"
DTS="$KDIR/arch/arm64/boot/dts/mediatek/mt7988a-bananapi-bpi-r4.dts"
SFP=$(ls "$OPENWRT_DIR"/build_dir/target-*/root-mediatek/lib/modules/6.12.*/sfp.ko 2>/dev/null | head -n 1 || true)

fail=0
check() {
	label=$1
	shift
	if "$@" >/dev/null 2>&1; then
		printf '  OK    %s\n' "$label"
	else
		printf '  FAIL  %s\n' "$label"
		fail=1
	fi
}

echo "Kernel : $KDIR"
echo "DTB    : $DTB"
echo "sfp.ko : ${SFP:-<not found>}"
echo

[ -f "$DTB" ] || die "DTB not found: $DTB"
[ -n "$SFP" ] && [ -f "$SFP" ] || die "sfp.ko not found"

echo "Device tree:"
check "sfp1-force-power hog present"  sh -c "strings '$DTB' | grep -q sfp1-force-power"
check "sfp2-force-power hog present"  sh -c "strings '$DTB' | grep -q sfp2-force-power"
if [ -f "$DTSI" ] || [ -f "$DTS" ]; then
	check "no mod-def0-gpios in BPI-R4 DTS" sh -c \
		"! grep -h 'mod-def0-gpios' '$DTSI' '$DTS' 2>/dev/null | grep -q ."
else
	echo "  SKIP  DTS sources not present (generated tree only)"
fi

echo
echo "sfp.ko module IDs:"
for id in LEOX LXE-010S-H ZXOS11NPI NU-STICK1.0 XGSPONST2000 XGSPONST2001; do
	check "$id" sh -c "strings '$SFP' | grep -q '$id'"
done

echo
echo "Sysupgrade artifact:"
IMG=$(ls "$OPENWRT_DIR"/bin/targets/mediatek/filogic/*bananapi_bpi-r4*squashfs-sysupgrade.itb 2>/dev/null | head -n 1 || true)
if [ -n "$IMG" ]; then
	printf '  OK    %s\n' "$IMG"
	sha256sum "$IMG"
else
	printf '  FAIL  no sysupgrade .itb found\n'
	fail=1
fi

echo
if [ "$fail" -eq 0 ]; then
	echo "ALL CHECKS PASSED"
	exit 0
else
	echo "SOME CHECKS FAILED"
	exit 1
fi
