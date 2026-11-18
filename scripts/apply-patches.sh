#!/bin/sh
# Install the XGS-PON patches into an OpenWrt tree.
#
# Usage:
#   OPENWRT_DIR=/path/to/openwrt ./scripts/apply-patches.sh [--check] [--copy-only]
#
# Modes:
#   (default)    copy 999-*.patch into target/linux/mediatek/patches-6.12/
#                and apply 0001-*.patch at the OpenWrt root
#   --check      dry-run only, change nothing
#   --copy-only  copy kernel patches, do not modify the OpenWrt root
#
# Environment:
#   OPENWRT_DIR       path to your OpenWrt tree (required)
#   KERNEL_PATCH_DIR  patch directory name (default: patches-6.12)

set -eu

usage() {
	cat <<EOF
Usage: OPENWRT_DIR=/path/to/openwrt $0 [--check] [--copy-only]

  --check       dry-run only, no changes
  --copy-only   install kernel patches, leave the OpenWrt root untouched
EOF
}

die() { echo "ERROR: $*" >&2; exit 1; }

CHECK_ONLY=0
COPY_ONLY=0
case "${1:-}" in
	"")          ;;
	--check)     CHECK_ONLY=1 ;;
	--copy-only) COPY_ONLY=1 ;;
	-h|--help)   usage; exit 0 ;;
	*)           usage; die "unknown option: $1" ;;
esac

[ -n "${OPENWRT_DIR:-}" ] || die "set OPENWRT_DIR to your OpenWrt tree"
[ -d "$OPENWRT_DIR/target/linux/mediatek" ] || \
	die "$OPENWRT_DIR is not an OpenWrt mediatek/filogic tree"

REPO_DIR=$(cd "$(dirname "$0")/.." && pwd)
PATCH_DIR="$REPO_DIR/patches"
KPATCH_DIR="${KERNEL_PATCH_DIR:-patches-6.12}"
DEST_KERNEL="$OPENWRT_DIR/target/linux/mediatek/$KPATCH_DIR"

[ -d "$PATCH_DIR" ] || die "no patches directory in $REPO_DIR"

# Find the prepared kernel source, if the tree has been built at least once.
KDIR=$(ls -d "$OPENWRT_DIR"/build_dir/target-*/linux-mediatek_filogic/linux-6.12.* 2>/dev/null | head -n 1 || true)

for p in "$PATCH_DIR"/0001-*.patch "$PATCH_DIR"/999-*.patch; do
	[ -f "$p" ] || continue
	echo "found: $(basename "$p")"
done

echo
echo "Kernel patch dir : $DEST_KERNEL"
echo "Kernel source    : ${KDIR:-<not prepared yet>}"
echo "Mode             : $([ "$CHECK_ONLY" -eq 1 ] && echo CHECK || ([ "$COPY_ONLY" -eq 1 ] && echo COPY-ONLY || echo APPLY))"
echo

if [ "$CHECK_ONLY" -eq 1 ]; then
	rc=0
	for p in "$PATCH_DIR"/0001-*.patch; do
		[ -f "$p" ] || continue
		printf 'root patch  %-50s ' "$(basename "$p")"
		if patch -p1 --dry-run -R -f -d "$OPENWRT_DIR" -i "$p" >/dev/null 2>&1; then
			echo "already applied"
		elif patch -p1 --dry-run -f -d "$OPENWRT_DIR" -i "$p" >/dev/null 2>&1; then
			echo "applicable"
		else
			echo "CONFLICT"; rc=1
		fi
	done
	if [ -n "$KDIR" ]; then
		for p in "$PATCH_DIR"/999-*.patch; do
			[ -f "$p" ] || continue
			printf 'kernel patch %-50s ' "$(basename "$p")"
			if [ -f "$DEST_KERNEL/$(basename "$p")" ] && \
			   cmp -s "$p" "$DEST_KERNEL/$(basename "$p")"; then
				echo "installed (identical)"
			elif patch -p1 --dry-run -f -d "$KDIR" -i "$p" >/dev/null 2>&1; then
				echo "applicable"
			elif patch -p1 --dry-run -R -f -d "$KDIR" -i "$p" >/dev/null 2>&1; then
				echo "already applied"
			else
				echo "CONFLICT"; rc=1
			fi
		done
	else
		echo "kernel source not prepared — kernel patches cannot be checked yet"
	fi
	exit "$rc"
fi

# Install kernel patches (the build system applies them during kernel prepare).
mkdir -p "$DEST_KERNEL"
for p in "$PATCH_DIR"/999-*.patch; do
	[ -f "$p" ] || continue
	cp -f "$p" "$DEST_KERNEL/"
	echo "installed kernel patch: $DEST_KERNEL/$(basename "$p")"
done

if [ "$COPY_ONLY" -eq 1 ]; then
	echo "Root-level patch not applied (--copy-only)."
	echo "Apply it manually with: patch -p1 -d $OPENWRT_DIR -i $PATCH_DIR/0001-bpi-r4-restore-sdcard-artifacts.patch"
	exit 0
fi

for p in "$PATCH_DIR"/0001-*.patch; do
	[ -f "$p" ] || continue
	if patch -p1 --dry-run -R -f -d "$OPENWRT_DIR" -i "$p" >/dev/null 2>&1; then
		echo "root patch already applied: $(basename "$p")"
	elif patch -p1 --dry-run -f -d "$OPENWRT_DIR" -i "$p" >/dev/null 2>&1; then
		patch -p1 -f -d "$OPENWRT_DIR" -i "$p" >/dev/null
		echo "applied root patch: $(basename "$p")"
	else
		die "root patch does not apply: $(basename "$p")"
	fi
done

echo
echo "Done. Now build with: cd '$OPENWRT_DIR' && make -j\$(nproc)"
