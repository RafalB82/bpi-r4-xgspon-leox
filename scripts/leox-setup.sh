#!/bin/sh
# ---------------------------------------------------------------------------
# leox-setup.sh — interactive configuration of a LEOX LXE-010S-H XGS-PON stick
#                 from OpenWrt (BPI-R4), via telnet to the module.
#
# Purpose: the module has NOT been pre-configured for an operator.
# The script first READS the current identity from the module, offers to save
# it to a text file (backup.txt), then asks step by step for the values needed
# for OLT authentication and writes them with "leox set".
#
# Run on the router:
#   scp leox-setup.sh root@<router>:/tmp/
#   ssh root@<router> 'sh /tmp/leox-setup.sh'
#   sh /tmp/leox-setup.sh --dry-run     # print commands, send nothing
#
# Requirements: nc, ping, ip, sed, grep (BusyBox in OpenWrt).
# Does NOT use "timeout" or "nc -v/-w" (unsupported by this BusyBox build).
# ---------------------------------------------------------------------------

set -u

LM_IP="${LM_IP:-192.168.100.1}"          # module management IP
LM_PORT=23
LM_USER="leox"
LM_PASS="leolabs_7"
MGMT_IF="${MGMT_IF:-br-wan}"              # router interface for the /32 address
MGMT_LOCAL="${MGMT_LOCAL:-192.168.100.2}"
BACKUP_FILE="${BACKUP_FILE:-backup.txt}"
LOG="/tmp/leox-setup.log"
TMP_READ="/tmp/leox-read.txt"
DRY_RUN=0

usage() {
	cat <<EOF
Usage: sh leox-setup.sh [option]

Options:
  -h, --help      show this help
  -n, --dry-run   print the commands without sending them to the module

Environment variables:
  LM_IP=192.168.100.1        module management IP
  MGMT_IF=br-wan             router interface used to reach the module
  MGMT_LOCAL=192.168.100.2   temporary /32 address on MGMT_IF
  BACKUP_FILE=backup.txt     file for saving the current configuration
EOF
}

case "${1:-}" in
	-h|--help)    usage; exit 0 ;;
	-n|--dry-run) DRY_RUN=1 ;;
	"")           ;;
	*)            echo "Unknown option: $1"; usage; exit 1 ;;
esac

pause() { [ "$DRY_RUN" -eq 1 ] || sleep "$1"; }

ask() {
	printf '%s' "$1"
	IFS= read -r REPLY
	REPLY=$(printf '%s' "$REPLY" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
}

ask_default() {
	ask "$1"
	[ -n "$REPLY" ] || REPLY="$2"
}

valid() { printf '%s' "$1" | grep -Eqi "$2"; }

# Extract one value from the captured telnet session (leox print or *.conf)
get_val() {
	grep -E "^$1[[:space:]]*=" "$TMP_READ" 2>/dev/null | tail -1 | \
		sed -E 's/^[^=]*=[[:space:]]*//; s/^"//; s/"$//; s/;[[:space:]]*$//; s/^[[:space:]]+//; s/[[:space:]]+$//'
}

echo "================================================================"
echo " LEOX LXE-010S-H — operator authentication setup"
echo " mode: $([ "$DRY_RUN" -eq 1 ] && echo DRY-RUN || echo LIVE)"
echo "================================================================"
echo

command -v nc >/dev/null 2>&1 || { echo "ERROR: 'nc' not found in OpenWrt"; exit 1; }

# ---------------------------------------------------------------------------
# 1. Connectivity to the module's LCT
# ---------------------------------------------------------------------------
echo "[1/5] Checking access to module at ${LM_IP} ..."

ip -4 addr add "${MGMT_LOCAL}/32" dev "$MGMT_IF" 2>/dev/null || true
ip -4 route replace "${LM_IP}/32" dev "$MGMT_IF" src "$MGMT_LOCAL" 2>/dev/null || true

if ping -c 1 -W 2 "$LM_IP" >/dev/null 2>&1; then
	echo "      OK — module responds."
else
	echo "      Module does not respond."
	echo "      If the fibre is plugged in and the ONU reached O5, the local"
	echo "      LCT has been disabled by OMCI (ME 256) — this is normal."
	echo "      Unplug the fibre for ~60 s, then press Enter."
	ask "      Ready? [Enter] " ""
	if ! ping -c 2 -W 2 "$LM_IP" >/dev/null 2>&1; then
		echo "ERROR: still no reply from ${LM_IP}. Check the cable/fibre."
		exit 1
	fi
	echo "      OK — module responds after unplugging the fibre."
fi

# ---------------------------------------------------------------------------
# 2. Read the current configuration from the module
# ---------------------------------------------------------------------------
echo
echo "[2/5] Reading current configuration from the module ..."

CUR_EQSN=""; CUR_MAC=""; CUR_FW=""; CUR_HW=""; CUR_EQID=""; CUR_PASS=""
CUR_OLT=""; CUR_OMCC=""; CUR_LOID=""

if [ "$DRY_RUN" -eq 1 ]; then
	echo "      DRY-RUN: skipping live read; no current values available."
	: > "$TMP_READ"
else
	{
		printf '%s\n' "$LM_USER"
		pause 1
		printf '%s\n' "$LM_PASS"
		pause 1
		printf 'leox print\n'
		pause 1
		printf 'cat /config/scfg.txt\n'
		pause 1
		printf 'cat /config/omci.conf\n'
		pause 1
		printf 'exit\n'
	} | nc "$LM_IP" "$LM_PORT" > "$TMP_READ" 2>&1

	CUR_EQSN=$(get_val eqsn)
	CUR_MAC=$(get_val mac)
	CUR_FW=$(get_val swver0)
	CUR_HW=$(get_val hwver)
	CUR_EQID=$(get_val eqid)
	CUR_PASS=$(get_val passwd)
	CUR_OLT=$(get_val olt_type)
	CUR_OMCC=$(get_val omcc_ver)
	CUR_LOID=$(get_val loid)

	echo "      --------------------------------------------------------"
	echo "      eqsn   = ${CUR_EQSN:-(not set)}"
	echo "      mac    = ${CUR_MAC:-(not set)}"
	echo "      swver  = ${CUR_FW:-(not set)}"
	echo "      hwver  = ${CUR_HW:-(not set)}"
	echo "      eqid   = ${CUR_EQID:-(not set)}"
	echo "      passwd = ${CUR_PASS:-(empty)}"
	echo "      olt_type = ${CUR_OLT:-(not set)}"
	echo "      omcc_ver = ${CUR_OMCC:-(not set)}"
	echo "      loid     = ${CUR_LOID:-(not set)}"
	echo "      --------------------------------------------------------"

	ask_default "Save the current configuration to '${BACKUP_FILE}'? [Y/n]: " "y"
	case "$REPLY" in
		n|N|no|NO) echo "      Backup skipped." ;;
		*)
			{
				echo "# LEOX LXE-010S-H — configuration backup"
				echo "# Saved : $(date)"
				echo "# Module: ${LM_IP}:${LM_PORT}"
				echo
				echo "== parsed values =="
				echo "eqsn     = ${CUR_EQSN}"
				echo "mac      = ${CUR_MAC}"
				echo "swver0   = ${CUR_FW}"
				echo "hwver    = ${CUR_HW}"
				echo "eqid     = ${CUR_EQID}"
				echo "passwd   = ${CUR_PASS}"
				echo "olt_type = ${CUR_OLT}"
				echo "omcc_ver = ${CUR_OMCC}"
				echo "loid     = ${CUR_LOID}"
				echo
				echo "== raw telnet session =="
				cat "$TMP_READ"
			} > "$BACKUP_FILE"
			echo "      Saved to: $BACKUP_FILE"
			;;
	esac
fi

# ---------------------------------------------------------------------------
# 3. Ask for the authentication data (current values = defaults)
# ---------------------------------------------------------------------------
echo
echo "[3/5] Authentication data"
echo "      PON SN format: 4 vendor letters + 8 hex digits, e.g. SMBS12345678"
echo "      (SMBS = Sagemcom, used by Orange; ALCL = Nokia, HWTC = Huawei)"
echo "      Press Enter to keep the current value shown in [ ]."

while :; do
	ask_default "PON SN [${CUR_EQSN:-SMBS00000000}]: " "${CUR_EQSN:-SMBS00000000}"
	PON_SN=$(printf '%s' "$REPLY" | tr '[:lower:]' '[:upper:]')
	valid "$PON_SN" '^[A-Za-z]{4}[0-9A-Fa-f]{8}$' && break
	echo "      Invalid format — expected e.g. SMBS12345678"
done
VENDOR=$(printf '%s' "$PON_SN" | cut -c1-4)
echo "      Vendor-ID: $VENDOR"

while :; do
	ask_default "MAC address [${CUR_MAC:-00:00:00:00:00:00}]: " "${CUR_MAC:-00:00:00:00:00:00}"
	MAC_ADDR=$(printf '%s' "$REPLY" | tr '[:lower:]' '[:upper:]')
	valid "$MAC_ADDR" '^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$' && break
	echo "      Invalid MAC format."
done

while :; do
	ask_default "Firmware version (swver) [${CUR_FW:-V22.51.1L1}]: " "${CUR_FW:-V22.51.1L1}"
	FW_VER="$REPLY"
	valid "$FW_VER" '^[A-Za-z0-9._-]+$' && break
	echo "      Invalid characters in firmware version."
done

ask_default "Hardware version (hwver) [${CUR_HW:-LXE-010S-H}]: " "${CUR_HW:-LXE-010S-H}"
HW_VER="$REPLY"
valid "$HW_VER" '^[A-Za-z0-9._-]+$' || { echo "ERROR: invalid hwver"; exit 1; }

ask_default "Equipment ID (eqid) [${CUR_EQID:-LXE-010S-H}]: " "${CUR_EQID:-LXE-010S-H}"
EQ_ID="$REPLY"
valid "$EQ_ID" '^[A-Za-z0-9._-]+$' || { echo "ERROR: invalid eqid"; exit 1; }

ask_default "PLOAM password [${CUR_PASS:-empty}]: " "$CUR_PASS"
PLOAM_PASS="$REPLY"
[ -z "$PLOAM_PASS" ] || valid "$PLOAM_PASS" '^[A-Za-z0-9]+$' || {
	echo "ERROR: PLOAM password may contain letters and digits only"; exit 1; }

echo
echo "      Optional OMCI parameters"
ask_default "OLT type (ALCL=Nokia, HWTC=Huawei) [${CUR_OLT:-ALCL}]: " "${CUR_OLT:-ALCL}"
OLT_TYPE=$(printf '%s' "$REPLY" | tr '[:lower:]' '[:upper:]')
valid "$OLT_TYPE" '^[A-Za-z0-9]+$' || { echo "ERROR: invalid OLT type"; exit 1; }

ask_default "OMCC version [${CUR_OMCC:-B2}]: " "${CUR_OMCC:-B2}"
OMCC_VER=$(printf '%s' "$REPLY" | tr '[:lower:]' '[:upper:]')
valid "$OMCC_VER" '^[A-Za-z0-9]+$' || { echo "ERROR: invalid OMCC version"; exit 1; }

ask_default "LOID [${CUR_LOID:-LEOXFF000001}]: " "${CUR_LOID:-LEOXFF000001}"
LOID="$REPLY"
valid "$LOID" '^[A-Za-z0-9]+$' || { echo "ERROR: invalid LOID"; exit 1; }

ask_default "Also update /config/omci.conf? [y/N]: " "n"
case "$REPLY" in y|Y|yes|YES) CONFIGURE_OMCI=1 ;; *) CONFIGURE_OMCI=0 ;; esac

# ---------------------------------------------------------------------------
# 4. Build commands and confirm
# ---------------------------------------------------------------------------
CMDS="leox set eqsn=$PON_SN
leox set mac=$MAC_ADDR
leox set swver0=$FW_VER
leox set swver1=$FW_VER
leox set hwver=$HW_VER
leox set eqid=$EQ_ID"

[ -z "$PLOAM_PASS" ] || CMDS="$CMDS
leox set passwd=$PLOAM_PASS"

if [ "$CONFIGURE_OMCI" -eq 1 ]; then
	CMDS="$CMDS
sed -i 's/^olt_type.*/olt_type       = \"$OLT_TYPE\"/' /config/omci.conf
sed -i 's/^omcc_ver.*/omcc_ver       = \"$OMCC_VER\"/' /config/omci.conf
sed -i 's/^loid.*/loid           = \"$LOID\"/' /config/omci.conf"
fi

echo
echo "[4/5] Summary — the following commands will be sent:"
echo "------------------------------------------------"
printf '%s\n' "$CMDS" | sed '/^$/d'
echo "------------------------------------------------"

ask_default "Apply this configuration? [y/N]: " "n"
case "$REPLY" in
	y|Y|yes|YES) ;;
	*) echo "Cancelled."; exit 0 ;;
esac

ask_default "Reboot the module after saving? [Y/n]: " "y"
case "$REPLY" in n|N|no|NO) REBOOT_MOD=0 ;; *) REBOOT_MOD=1 ;; esac

# ---------------------------------------------------------------------------
# 5. Send commands over telnet
# ---------------------------------------------------------------------------
echo
echo "[5/5] Sending to ${LM_IP} ..."

emit() {
	printf '%s\n' "$LM_USER"
	pause 1
	printf '%s\n' "$LM_PASS"
	pause 1
	printf '%s\n' "$CMDS" | while IFS= read -r line; do
		[ -n "$line" ] || continue
		printf '%s\n' "$line"
		pause 0.3
	done
	printf 'leox print\n'
	pause 1
	if [ "$REBOOT_MOD" -eq 1 ]; then
		printf 'sync\n'
		pause 0.3
		printf 'reboot\n'
	else
		printf 'exit\n'
	fi
}

if [ "$DRY_RUN" -eq 1 ]; then
	emit
	echo
	echo "(DRY-RUN — nothing was sent)"
	exit 0
fi

emit | nc "$LM_IP" "$LM_PORT" > "$LOG" 2>&1

echo "Log: $LOG"
echo
echo "=== Configuration read back after write ==="
grep -E '^(eqsn|mac|hwver|eqid|passwd|swver)' "$LOG" || \
	echo "Could not read back — check the log manually."

echo
if [ "$REBOOT_MOD" -eq 1 ]; then
	echo "The module is rebooting. Once the fibre is plugged in it will reach"
	echo "O5 and the local LCT will be disabled again by OMCI."
else
	echo "Reboot the module yourself so the new PON identity takes effect."
fi

echo
echo "=== Remove temporary management address (optional) ==="
ask_default "Remove ${MGMT_LOCAL}/32 from ${MGMT_IF}? [y/N]: " "n"
case "$REPLY" in
	y|Y|yes|YES)
		ip -4 addr del "${MGMT_LOCAL}/32" dev "$MGMT_IF" 2>/dev/null || true
		ip -4 route del "${LM_IP}/32" dev "$MGMT_IF" 2>/dev/null || true
		echo "Removed."
		;;
	*) echo "Kept (useful if you still need telnet access to the module)." ;;
esac

exit 0
