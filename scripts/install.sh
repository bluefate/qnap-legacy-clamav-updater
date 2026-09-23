#!/bin/sh
#
# install.sh
#
# Interactive installer for qnap-legacy-clamav-updater.
# POSIX sh compatible for legacy QNAP / BusyBox environments.
#
# Reference tested system: QNAP TS-469L | QTS 4.3.4 | Entware | ClamAV 1.4.3
#
# This installer detects and validates paths. It does not assume the
# reference paths are universal across all QNAP models.
#

set -eu

REPO_ROOT="$(CDPATH=''; cd -- "$(dirname "$0")/.." && pwd)"
SYNC_SRC="${REPO_ROOT}/scripts/qnap-av-db-sync.sh"
FRESHCLAM_EXAMPLE="${REPO_ROOT}/config/freshclam.conf.example"

# Defaults from the reference TS-469L (validated/overridden by detection).
FRESHCLAM_BIN="${FRESHCLAM_BIN:-/opt/sbin/freshclam}"
ENTWARE_DB_DIR="${ENTWARE_DB_DIR:-/opt/var/lib/clamav}"
INSTALL_BIN="${INSTALL_BIN:-/opt/bin/qnap-av-db-sync.sh}"
QNAP_CRONTAB_FILE="${QNAP_CRONTAB_FILE:-/etc/config/crontab}"
CRON_LINE="${CRON_LINE:-15 3 * * * /opt/bin/qnap-av-db-sync.sh >/dev/null 2>&1}"
BACKUP_TS="$(date '+%Y%m%d%H%M%S' 2>/dev/null || echo manual)"

QNAP_AV_DB_DIR="${QNAP_AV_DB_DIR:-}"
FRESHCLAM_CONF=""
DETECTED_MODEL=""
DETECTED_QTS=""

log() { printf '%s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
error() { printf 'ERROR: %s\n' "$*" >&2; }
die() { error "$*"; exit 1; }

confirm() {
	_prompt="$1"
	printf '%s [y/N]: ' "$_prompt"
	# Read from the controlling terminal when possible.
	if [ -r /dev/tty ]; then
		read -r _ans </dev/tty || _ans=""
	else
		read -r _ans || _ans=""
	fi
	case "$_ans" in
		y|Y|yes|YES) return 0 ;;
		*) return 1 ;;
	esac
}

is_qnap() {
	if [ -x /sbin/getcfg ] || [ -x /usr/sbin/getcfg ]; then
		return 0
	fi
	if [ -f /etc/config/uLinux.conf ] || [ -f /etc/platform.conf ]; then
		return 0
	fi
	if [ -d /mnt/HDA_ROOT ] && [ -d /share ]; then
		return 0
	fi
	return 1
}

detect_model() {
	if command -v getcfg >/dev/null 2>&1; then
		getcfg System Model 2>/dev/null || getcfg "System" "Model" 2>/dev/null || true
	elif [ -x /sbin/getcfg ]; then
		/sbin/getcfg System Model 2>/dev/null || true
	elif [ -f /etc/platform.conf ]; then
		# shellcheck disable=SC2002
		cat /etc/platform.conf 2>/dev/null | sed -n 's/.*Model[=: ]*//p' | head -n 1 || true
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
		if [ -n "$_ver" ]; then
			printf '%s\n' "$_ver"
			return 0
		fi
	fi
	if [ -f /etc/config/uLinux.conf ]; then
		# Best-effort parse; may vary by firmware.
		_ver="$(sed -n 's/^Version = //p' /etc/config/uLinux.conf 2>/dev/null | head -n 1 || true)"
		_num="$(sed -n 's/^Build Number = //p' /etc/config/uLinux.conf 2>/dev/null | head -n 1 || true)"
		if [ -n "$_ver" ] && [ -n "$_num" ]; then
			printf '%s.%s\n' "$_ver" "$_num"
			return 0
		fi
		if [ -n "$_ver" ]; then
			printf '%s\n' "$_ver"
			return 0
		fi
	fi
	return 0
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
		if [ -d "$_dir" ]; then
			printf '%s\n' "$_dir"
			return 0
		fi
	done

	for _dir in /share/*/.antivirus/usr/share/clamav; do
		if [ -d "$_dir" ]; then
			printf '%s\n' "$_dir"
			return 0
		fi
	done

	return 1
}

find_freshclam_conf() {
	for _c in \
		/opt/etc/clamav/freshclam.conf \
		/opt/etc/freshclam.conf \
		/opt/etc/clamav/freshclam.conf.sample
	do
		if [ -f "$_c" ]; then
			printf '%s\n' "$_c"
			return 0
		fi
	done
	# Prefer the common Entware path even if missing (installer may create it).
	if [ -d /opt/etc/clamav ]; then
		printf '%s\n' "/opt/etc/clamav/freshclam.conf"
		return 0
	fi
	if [ -d /opt/etc ]; then
		printf '%s\n' "/opt/etc/freshclam.conf"
		return 0
	fi
	return 1
}

qnap_crontab_bin() {
	# Prefer QNAP crontab over Entware's BusyBox crontab when both exist.
	for _b in /usr/bin/crontab /bin/crontab /sbin/crontab; do
		if [ -x "$_b" ]; then
			printf '%s\n' "$_b"
			return 0
		fi
	done
	if command -v crontab >/dev/null 2>&1; then
		command -v crontab
		return 0
	fi
	return 1
}

cron_entry_present() {
	_file="$1"
	_needle="/opt/bin/qnap-av-db-sync.sh"
	if [ -f "$_file" ] && grep -F "$_needle" "$_file" >/dev/null 2>&1; then
		return 0
	fi
	return 1
}

backup_file() {
	_src="$1"
	if [ ! -e "$_src" ]; then
		return 0
	fi
	_dst="${_src}.bak.${BACKUP_TS}"
	cp -f "$_src" "$_dst" || die "Failed to back up $_src"
	log "Backed up: $_src -> $_dst"
}

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
log "=== qnap-legacy-clamav-updater installer ==="
log ""

if [ ! -f "$SYNC_SRC" ]; then
	die "Cannot find sync script at $SYNC_SRC (run this from a full repository checkout)."
fi

if ! is_qnap; then
	warn "This does not look like a QNAP system (getcfg / uLinux.conf / platform.conf not found)."
	if ! confirm "Continue anyway"; then
		die "Aborted."
	fi
else
	log "QNAP system markers: detected"
fi

DETECTED_MODEL="$(detect_model || true)"
DETECTED_QTS="$(detect_qts || true)"
if [ -n "$DETECTED_MODEL" ]; then
	log "Detected model: $DETECTED_MODEL"
else
	warn "Could not detect QNAP model"
fi
if [ -n "$DETECTED_QTS" ]; then
	log "Detected QTS:   $DETECTED_QTS"
else
	warn "Could not detect QTS version"
fi

if [ ! -d /opt ] || [ ! -x /opt/bin/opkg ] && [ ! -d /opt/etc ]; then
	if [ ! -d /opt ]; then
		die "Entware does not appear to be installed (/opt missing)."
	fi
	warn "Entware markers incomplete; /opt exists but opkg may be missing."
else
	log "Entware: /opt present"
fi

if [ ! -x "$FRESHCLAM_BIN" ]; then
	die "freshclam not found at $FRESHCLAM_BIN. Install Entware ClamAV first (see docs/installation.md)."
fi
log "freshclam: $FRESHCLAM_BIN"

if [ ! -d "$ENTWARE_DB_DIR" ]; then
	warn "Entware DB directory missing: $ENTWARE_DB_DIR (will be created if you proceed with freshclam config)."
fi

if ! QNAP_AV_DB_DIR="$(detect_qnap_av_db_dir)"; then
	die "QNAP Antivirus database directory not found. Install/enable QNAP Antivirus, or set QNAP_AV_DB_DIR to the correct path after verifying it on this NAS."
fi
log "QNAP AV DB: $QNAP_AV_DB_DIR"

if ! FRESHCLAM_CONF="$(find_freshclam_conf)"; then
	die "Could not determine a freshclam.conf location under /opt/etc."
fi
log "freshclam.conf target: $FRESHCLAM_CONF"

log ""
log "Planned actions:"
log "  1. Back up existing freshclam.conf if present"
log "  2. Optionally install example freshclam settings (DatabaseDirectory / DatabaseOwner)"
log "  3. Install sync script to: $INSTALL_BIN"
log "  4. Optionally add persistent cron entry to: $QNAP_CRONTAB_FILE"
log "       $CRON_LINE"
log ""
log "Reference ownership on the tested TS-469L QNAP CVD files was clamav:clamav."
log "The sync script preserves whatever ownership it finds on this system."
log ""

if ! confirm "Proceed with installation"; then
	die "Aborted by user."
fi

# ---------------------------------------------------------------------------
# Install sync script
# ---------------------------------------------------------------------------
mkdir -p "$(dirname "$INSTALL_BIN")" || die "Cannot create $(dirname "$INSTALL_BIN")"
backup_file "$INSTALL_BIN"
cp -f "$SYNC_SRC" "$INSTALL_BIN" || die "Failed to install $INSTALL_BIN"
chmod 755 "$INSTALL_BIN" || die "Failed to chmod $INSTALL_BIN"
log "Installed: $INSTALL_BIN"

# ---------------------------------------------------------------------------
# Optional freshclam.conf
# ---------------------------------------------------------------------------
log ""
if [ -f "$FRESHCLAM_CONF" ]; then
	log "Existing freshclam.conf found."
	if confirm "Back up and merge/replace with project example settings"; then
		backup_file "$FRESHCLAM_CONF"
		# Write a conservative conf from the example without downloading anything.
		if [ -f "$FRESHCLAM_EXAMPLE" ]; then
			cp -f "$FRESHCLAM_EXAMPLE" "$FRESHCLAM_CONF" || die "Failed to write $FRESHCLAM_CONF"
			log "Wrote example freshclam.conf to $FRESHCLAM_CONF"
			log "NOTE: DatabaseOwner admin avoids 'nobody' ownership issues seen on the reference host."
		else
			warn "Example config missing; left existing freshclam.conf in place (backup created)."
		fi
	else
		log "Left existing freshclam.conf unchanged."
	fi
else
	if confirm "Create freshclam.conf from project example at $FRESHCLAM_CONF"; then
		mkdir -p "$(dirname "$FRESHCLAM_CONF")" || die "Cannot create $(dirname "$FRESHCLAM_CONF")"
		cp -f "$FRESHCLAM_EXAMPLE" "$FRESHCLAM_CONF" || die "Failed to create $FRESHCLAM_CONF"
		log "Created $FRESHCLAM_CONF"
	else
		warn "No freshclam.conf created. Configure DatabaseDirectory and DatabaseOwner manually before syncing."
	fi
fi

mkdir -p "$ENTWARE_DB_DIR" || warn "Could not create $ENTWARE_DB_DIR"

# ---------------------------------------------------------------------------
# Optional persistent cron
# ---------------------------------------------------------------------------
log ""
log "QNAP cron note:"
log "  Do NOT use crontab -e alone. QNAP may regenerate the active crontab on reboot."
log "  Persistent method: edit $QNAP_CRONTAB_FILE, then:"
log "    crontab $QNAP_CRONTAB_FILE && /etc/init.d/crond.sh restart"
log ""

if confirm "Add nightly cron entry now"; then
	if [ ! -f "$QNAP_CRONTAB_FILE" ]; then
		die "Persistent crontab file not found: $QNAP_CRONTAB_FILE"
	fi

	if cron_entry_present "$QNAP_CRONTAB_FILE"; then
		log "Cron entry for qnap-av-db-sync.sh already present in $QNAP_CRONTAB_FILE (no duplicate added)."
	else
		backup_file "$QNAP_CRONTAB_FILE"
		# Ensure the previous line is terminated before appending.
		if [ -s "$QNAP_CRONTAB_FILE" ]; then
			printf '\n' >>"$QNAP_CRONTAB_FILE"
		fi
		printf '%s\n' "$CRON_LINE" >>"$QNAP_CRONTAB_FILE" || die "Failed to append cron line"
		log "Appended cron line to $QNAP_CRONTAB_FILE"
	fi

	_crontab_bin="$(qnap_crontab_bin || true)"
	if [ -z "$_crontab_bin" ]; then
		warn "crontab binary not found; cron file updated but not loaded."
	else
		"$_crontab_bin" "$QNAP_CRONTAB_FILE" || warn "Failed to load crontab from $QNAP_CRONTAB_FILE"
		if [ -x /etc/init.d/crond.sh ]; then
			/etc/init.d/crond.sh restart || warn "Failed to restart crond"
		else
			warn "/etc/init.d/crond.sh not found; restart cron manually if needed."
		fi
		log "Cron loaded from $QNAP_CRONTAB_FILE"
	fi
else
	log "Skipped cron configuration."
fi

log ""
log "Installation complete."
log "Next steps:"
log "  1. Review freshclam.conf (DatabaseDirectory / DatabaseOwner)."
log "  2. Run: $INSTALL_BIN"
log "  3. Run: sh ${REPO_ROOT}/scripts/verify.sh"
log "  4. Confirm QNAP Antivirus can use the updated definitions."
log ""
log "See docs/installation.md and docs/troubleshooting.md for details."
exit 0
