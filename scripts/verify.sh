#!/bin/sh
#
# verify.sh
#
# Read-only diagnostic script for qnap-legacy-clamav-updater.
# POSIX sh compatible. Does not modify the system and does not transmit data.
#
# Reference tested system: QNAP TS-469L | QTS 4.3.4 | Entware | ClamAV 1.4.3
#

set -eu

FRESHCLAM_BIN="${FRESHCLAM_BIN:-/opt/sbin/freshclam}"
CLAMSCAN_BIN="${CLAMSCAN_BIN:-/opt/bin/clamscan}"
ENTWARE_DB_DIR="${ENTWARE_DB_DIR:-/opt/var/lib/clamav}"
INSTALL_BIN="${INSTALL_BIN:-/opt/bin/qnap-av-db-sync.sh}"
QNAP_CRONTAB_FILE="${QNAP_CRONTAB_FILE:-/etc/config/crontab}"
QNAP_AV_DB_DIR="${QNAP_AV_DB_DIR:-}"
DB_NAMES="${DB_NAMES:-main daily bytecode}"

OK_COUNT=0
WARN_COUNT=0
ERR_COUNT=0

ok() {
	OK_COUNT=$((OK_COUNT + 1))
	printf '[OK]      %s\n' "$*"
}

warn() {
	WARN_COUNT=$((WARN_COUNT + 1))
	printf '[WARNING] %s\n' "$*"
}

err() {
	ERR_COUNT=$((ERR_COUNT + 1))
	printf '[ERROR]   %s\n' "$*"
}

info() {
	printf '[INFO]    %s\n' "$*"
}

section() {
	printf '\n== %s ==\n' "$*"
}

file_nonempty() {
	[ -f "$1" ] && [ -s "$1" ]
}

# Prefer .cld over .cvd when reporting the active Entware/QNAP database file.
resolve_db_file() {
	_dir="$1"
	_name="$2"
	if file_nonempty "${_dir}/${_name}.cld"; then
		printf '%s.cld\n' "$_name"
		return 0
	fi
	if file_nonempty "${_dir}/${_name}.cvd"; then
		printf '%s.cvd\n' "$_name"
		return 0
	fi
	return 1
}

detect_model() {
	if command -v getcfg >/dev/null 2>&1; then
		getcfg System Model 2>/dev/null || true
	elif [ -x /sbin/getcfg ]; then
		/sbin/getcfg System Model 2>/dev/null || true
	fi
}

detect_qts() {
	if command -v getcfg >/dev/null 2>&1; then
		_ver="$(getcfg System Version 2>/dev/null || true)"
		_num="$(getcfg System "Build Number" 2>/dev/null || getcfg System BuildNumber 2>/dev/null || true)"
		if [ -n "$_ver" ] && [ -n "$_num" ]; then
			printf '%s.%s\n' "$_ver" "$_num"
			return 0
		fi
		[ -n "$_ver" ] && printf '%s\n' "$_ver"
	fi
}

detect_qnap_av_db_dir() {
	if [ -n "${QNAP_AV_DB_DIR}" ] && [ -d "${QNAP_AV_DB_DIR}" ]; then
		printf '%s\n' "${QNAP_AV_DB_DIR}"
		return 0
	fi
	_candidate="/share/CACHEDEV1_DATA/.antivirus/usr/share/clamav"
	if [ -d "$_candidate" ]; then
		printf '%s\n' "$_candidate"
		return 0
	fi
	for _dir in /share/CACHEDEV*_DATA/.antivirus/usr/share/clamav; do
		[ -d "$_dir" ] && { printf '%s\n' "$_dir"; return 0; }
	done
	for _dir in /share/*/.antivirus/usr/share/clamav; do
		[ -d "$_dir" ] && { printf '%s\n' "$_dir"; return 0; }
	done
	return 1
}

file_info() {
	_path="$1"
	if [ ! -e "$_path" ]; then
		err "Missing: $_path"
		return 1
	fi
	if [ ! -s "$_path" ]; then
		err "Empty:   $_path"
		return 1
	fi

	_size="$(wc -c < "$_path" 2>/dev/null | tr -d ' ' || echo unknown)"
	_mtime="unknown"
	if command -v stat >/dev/null 2>&1; then
		_mtime="$(stat -c '%y' "$_path" 2>/dev/null || stat -f '%Sm' "$_path" 2>/dev/null || echo unknown)"
	fi
	_owner="unknown"
	_mode="unknown"
	if command -v stat >/dev/null 2>&1; then
		_owner="$(stat -c '%U:%G' "$_path" 2>/dev/null || stat -f '%Su:%Sg' "$_path" 2>/dev/null || echo unknown)"
		_mode="$(stat -c '%a' "$_path" 2>/dev/null || stat -f '%OLp' "$_path" 2>/dev/null || echo unknown)"
	else
		# shellcheck disable=SC2012
		_line="$(ls -ld "$_path" 2>/dev/null || true)"
		if [ -n "$_line" ]; then
			_owner="$(printf '%s\n' "$_line" | awk '{print $3 ":" $4}')"
			_mode="$(printf '%s\n' "$_line" | awk '{print $1}')"
		fi
	fi

	ok "$_path"
	info "  size=$_size  mtime=$_mtime  owner=$_owner  mode=$_mode"
}

# ---------------------------------------------------------------------------
printf 'qnap-legacy-clamav-updater verification (read-only)\n'
printf 'Nothing on this system will be modified. No data is transmitted.\n'

section "System"
_model="$(detect_model || true)"
_qts="$(detect_qts || true)"
if [ -n "$_model" ]; then
	ok "QNAP model: $_model"
else
	warn "QNAP model not detected"
fi
if [ -n "$_qts" ]; then
	ok "QTS version: $_qts"
else
	warn "QTS version not detected"
fi
if [ -x /sbin/getcfg ] || [ -f /etc/config/uLinux.conf ] || [ -f /etc/platform.conf ]; then
	ok "QNAP system markers present"
else
	warn "QNAP system markers not found"
fi

section "Entware"
if [ -d /opt ]; then
	ok "Entware root /opt exists"
else
	err "Entware root /opt missing"
fi
if [ -x /opt/bin/opkg ]; then
	ok "opkg available: /opt/bin/opkg"
else
	warn "opkg not found at /opt/bin/opkg"
fi

section "ClamAV / freshclam"
if [ -x "$FRESHCLAM_BIN" ]; then
	ok "freshclam binary: $FRESHCLAM_BIN"
	_fc_ver="$("$FRESHCLAM_BIN" --version 2>/dev/null || true)"
	if [ -n "$_fc_ver" ]; then
		ok "freshclam version: $_fc_ver"
	else
		warn "Could not read freshclam version"
	fi
else
	err "freshclam missing or not executable: $FRESHCLAM_BIN"
fi

if [ -x "$CLAMSCAN_BIN" ]; then
	_cs_ver="$("$CLAMSCAN_BIN" --version 2>/dev/null || true)"
	if [ -n "$_cs_ver" ]; then
		ok "clamscan version: $_cs_ver"
	else
		warn "clamscan present but version unread: $CLAMSCAN_BIN"
	fi
else
	warn "clamscan not found at $CLAMSCAN_BIN (optional for this workaround)"
fi

section "Database locations"
if [ -d "$ENTWARE_DB_DIR" ]; then
	ok "Entware DB directory: $ENTWARE_DB_DIR"
else
	err "Entware DB directory missing: $ENTWARE_DB_DIR"
fi

if QNAP_AV_DB_DIR="$(detect_qnap_av_db_dir)"; then
	ok "QNAP Antivirus DB directory: $QNAP_AV_DB_DIR"
else
	err "QNAP Antivirus DB directory not found (set QNAP_AV_DB_DIR after verifying on this NAS)"
	QNAP_AV_DB_DIR=""
fi

section "Entware database files"
for _name in $DB_NAMES; do
	if _file="$(resolve_db_file "$ENTWARE_DB_DIR" "$_name")"; then
		file_info "${ENTWARE_DB_DIR}/${_file}" || true
		# Note competing extension if present.
		_other=""
		case "$_file" in
			*.cld) _other="${ENTWARE_DB_DIR}/${_name}.cvd" ;;
			*.cvd) _other="${ENTWARE_DB_DIR}/${_name}.cld" ;;
		esac
		if [ -n "$_other" ] && [ -e "$_other" ]; then
			info "  also present: $_other"
		fi
	else
		err "Entware ${_name}: neither ${_name}.cld nor ${_name}.cvd found/non-empty"
	fi
done

section "QNAP Antivirus database files"
if [ -n "$QNAP_AV_DB_DIR" ]; then
	for _name in $DB_NAMES; do
		if _file="$(resolve_db_file "$QNAP_AV_DB_DIR" "$_name")"; then
			file_info "${QNAP_AV_DB_DIR}/${_file}" || true
			_other=""
			case "$_file" in
				*.cld) _other="${QNAP_AV_DB_DIR}/${_name}.cvd" ;;
				*.cvd) _other="${QNAP_AV_DB_DIR}/${_name}.cld" ;;
			esac
			if [ -n "$_other" ] && [ -e "$_other" ]; then
				warn "Competing file also present: $_other (ClamAV usually prefers .cld)"
			fi
		else
			err "QNAP ${_name}: neither ${_name}.cld nor ${_name}.cvd found/non-empty"
		fi
	done
else
	err "Skipping QNAP database inspection (directory unknown)"
fi

section "Sync script"
if [ -x "$INSTALL_BIN" ]; then
	ok "Installed sync script: $INSTALL_BIN"
elif [ -f "$INSTALL_BIN" ]; then
	warn "Sync script exists but is not executable: $INSTALL_BIN"
else
	warn "Sync script not installed at $INSTALL_BIN"
fi

section "Cron"
if [ -f "$QNAP_CRONTAB_FILE" ]; then
	ok "Persistent crontab file present: $QNAP_CRONTAB_FILE"
	if grep -F "qnap-av-db-sync.sh" "$QNAP_CRONTAB_FILE" >/dev/null 2>&1; then
		ok "Sync job found in $QNAP_CRONTAB_FILE"
		info "Matching lines:"
		grep -F "qnap-av-db-sync.sh" "$QNAP_CRONTAB_FILE" | while IFS= read -r _line; do
			info "  $_line"
		done
	else
		warn "No qnap-av-db-sync.sh entry in $QNAP_CRONTAB_FILE"
	fi
else
	warn "Persistent crontab file missing: $QNAP_CRONTAB_FILE"
fi

# Active crontab view (read-only). Prefer QNAP binary if present.
_crontab_bin=""
for _b in /usr/bin/crontab /bin/crontab; do
	if [ -x "$_b" ]; then
		_crontab_bin="$_b"
		break
	fi
done
if [ -z "$_crontab_bin" ] && command -v crontab >/dev/null 2>&1; then
	_crontab_bin="$(command -v crontab)"
fi
if [ -n "$_crontab_bin" ]; then
	info "Active crontab binary: $_crontab_bin"
	_cron_list="$("$_crontab_bin" -l 2>/dev/null || true)"
	if [ -n "$_cron_list" ]; then
		if printf '%s\n' "$_cron_list" | grep -F "qnap-av-db-sync.sh" >/dev/null 2>&1; then
			ok "Sync job visible in active crontab (-l)"
		else
			warn "Sync job not visible in active crontab (-l)"
		fi
	else
		warn "Could not list active crontab with $_crontab_bin -l (empty or unavailable)"
	fi
else
	warn "crontab binary not found"
fi

section "freshclam configuration hints"
for _c in /opt/etc/clamav/freshclam.conf /opt/etc/freshclam.conf; do
	if [ -f "$_c" ]; then
		ok "Found $_c"
		if grep -E '^[[:space:]]*DatabaseDirectory' "$_c" >/dev/null 2>&1; then
			info "  $(grep -E '^[[:space:]]*DatabaseDirectory' "$_c" | head -n 1)"
		else
			warn "  DatabaseDirectory not set in $_c"
		fi
		if grep -E '^[[:space:]]*DatabaseOwner' "$_c" >/dev/null 2>&1; then
			info "  $(grep -E '^[[:space:]]*DatabaseOwner' "$_c" | head -n 1)"
		else
			warn "  DatabaseOwner not set in $_c (reference host needed: admin)"
		fi
	fi
done

section "Summary"
info "OK=$OK_COUNT  WARNING=$WARN_COUNT  ERROR=$ERR_COUNT"
info "This report stays local. It was not sent anywhere."

if [ "$ERR_COUNT" -gt 0 ]; then
	exit 2
fi
if [ "$WARN_COUNT" -gt 0 ]; then
	exit 1
fi
exit 0
