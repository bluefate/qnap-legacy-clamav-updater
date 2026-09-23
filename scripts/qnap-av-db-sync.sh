#!/bin/sh
#
# qnap-av-db-sync.sh
#
# Download current ClamAV virus definitions with Entware freshclam and
# synchronize them into the QNAP Antivirus database directory.
#
# POSIX sh compatible for legacy QNAP / BusyBox environments.
#
# Tested on: QNAP TS-469L | QTS 4.3.4 | Entware | ClamAV 1.4.3
#
# IMPORTANT: Paths below are defaults from the tested system. Detect and
# validate paths on your NAS before relying on this script. Do not assume
# CACHEDEV1_DATA or ownership is universal across all QNAP models.
#
# ClamAV may publish databases as .cvd and/or .cld. After updates, daily
# definitions are often daily.cld rather than daily.cvd. This script syncs
# whichever form freshclam left in the Entware directory (.cld preferred
# when both exist for the same base name).
#

set -eu

# ---------------------------------------------------------------------------
# Configurable paths (override via environment variables if needed)
# ---------------------------------------------------------------------------
FRESHCLAM_BIN="${FRESHCLAM_BIN:-/opt/sbin/freshclam}"
ENTWARE_DB_DIR="${ENTWARE_DB_DIR:-/opt/var/lib/clamav}"
# Default QNAP Antivirus DB path from the tested TS-469L. Prefer auto-detect
# when QNAP_AV_DB_DIR is unset and a candidate exists.
QNAP_AV_DB_DIR="${QNAP_AV_DB_DIR:-}"
INSTALL_BIN="${INSTALL_BIN:-/opt/bin/qnap-av-db-sync.sh}"
LOG_TAG="${LOG_TAG:-qnap-av-db-sync}"
# Base database names (extensions resolved dynamically: .cld preferred, else .cvd).
DB_NAMES="${DB_NAMES:-main daily bytecode}"
BACKUP_SUFFIX="${BACKUP_SUFFIX:-.bak.qnap-av-db-sync}"
# When both .cld and .cvd exist for a synced name, move the unused one aside
# (backed up) so ClamAV does not keep loading a stale competitor.
DISABLE_COMPETING="${DISABLE_COMPETING:-yes}"
# Staging directory base. QNAP /tmp is often a tiny ramdisk — prefer the
# data volume. Override with STAGE_BASE or TMPDIR if needed.
STAGE_BASE="${STAGE_BASE:-}"

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
log() {
	_level="$1"
	shift
	_msg="$*"
	_ts="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo unknown-time)"
	printf '%s [%s] %s: %s\n' "$_ts" "$LOG_TAG" "$_level" "$_msg" >&2
}

info() { log INFO "$*"; }
warn() { log WARN "$*"; }
error() { log ERROR "$*"; }

die() {
	error "$*"
	exit 1
}

# ---------------------------------------------------------------------------
# Path helpers
# ---------------------------------------------------------------------------
detect_qnap_av_db_dir() {
	# Prefer an existing, non-empty configuration override.
	if [ -n "${QNAP_AV_DB_DIR}" ] && [ -d "${QNAP_AV_DB_DIR}" ]; then
		printf '%s\n' "${QNAP_AV_DB_DIR}"
		return 0
	fi

	# Known path from the tested TS-469L.
	_candidate="/share/CACHEDEV1_DATA/.antivirus/usr/share/clamav"
	if [ -d "$_candidate" ]; then
		printf '%s\n' "$_candidate"
		return 0
	fi

	# Probe other CACHEDEV volumes without assuming CACHEDEV1.
	for _dir in /share/CACHEDEV*_DATA/.antivirus/usr/share/clamav; do
		if [ -d "$_dir" ]; then
			printf '%s\n' "$_dir"
			return 0
		fi
	done

	# Broader fallback: look for .antivirus clamav dirs under /share.
	for _dir in /share/*/.antivirus/usr/share/clamav; do
		if [ -d "$_dir" ]; then
			printf '%s\n' "$_dir"
			return 0
		fi
	done

	return 1
}

file_nonempty() {
	[ -f "$1" ] && [ -s "$1" ]
}

# Prefer .cld over .cvd when both exist (ClamAV loads .cld preferentially).
# Prints the chosen filename (basename only) on success.
resolve_db_file() {
	_dir="$1"
	_name="$2"
	_cld="${_dir}/${_name}.cld"
	_cvd="${_dir}/${_name}.cvd"

	if file_nonempty "$_cld"; then
		printf '%s.cld\n' "$_name"
		return 0
	fi
	if file_nonempty "$_cvd"; then
		printf '%s.cvd\n' "$_name"
		return 0
	fi
	return 1
}

# Return "user:group" ownership of a reference file, or empty if unavailable.
detect_ownership() {
	_ref="$1"
	if [ ! -e "$_ref" ]; then
		return 1
	fi

	# Prefer GNU/BusyBox stat if available.
	if command -v stat >/dev/null 2>&1; then
		_ug="$(stat -c '%U:%G' "$_ref" 2>/dev/null || true)"
		if [ -n "$_ug" ] && [ "$_ug" != '%U:%G' ]; then
			printf '%s\n' "$_ug"
			return 0
		fi
		_ug="$(stat -f '%Su:%Sg' "$_ref" 2>/dev/null || true)"
		if [ -n "$_ug" ]; then
			printf '%s\n' "$_ug"
			return 0
		fi
	fi

	# Fallback via ls -ld (less ideal but works on many BusyBox builds).
	# shellcheck disable=SC2012
	_line="$(ls -ld "$_ref" 2>/dev/null || true)"
	if [ -n "$_line" ]; then
		_user="$(printf '%s\n' "$_line" | awk '{print $3}')"
		_group="$(printf '%s\n' "$_line" | awk '{print $4}')"
		if [ -n "$_user" ] && [ -n "$_group" ]; then
			printf '%s:%s\n' "$_user" "$_group"
			return 0
		fi
	fi

	return 1
}

detect_mode() {
	_ref="$1"
	if command -v stat >/dev/null 2>&1; then
		_mode="$(stat -c '%a' "$_ref" 2>/dev/null || true)"
		if [ -n "$_mode" ] && [ "$_mode" != '%a' ]; then
			printf '%s\n' "$_mode"
			return 0
		fi
		_mode="$(stat -f '%OLp' "$_ref" 2>/dev/null || true)"
		if [ -n "$_mode" ]; then
			printf '%s\n' "$_mode"
			return 0
		fi
	fi
	return 1
}

warn_competing_db() {
	_dest_dir="$1"
	_file="$2"
	_base="${_file%.*}"
	_ext="${_file##*.}"
	_other=""
	if [ "$_ext" = "cld" ]; then
		_other="${_dest_dir}/${_base}.cvd"
	elif [ "$_ext" = "cvd" ]; then
		_other="${_dest_dir}/${_base}.cld"
	else
		return 0
	fi
	if [ ! -e "$_other" ]; then
		return 0
	fi

	if [ "$DISABLE_COMPETING" != "yes" ]; then
		warn "Competing database also present (not modified): $_other"
		warn "ClamAV typically prefers .cld over .cvd when both exist. Set DISABLE_COMPETING=yes to move it aside."
		return 0
	fi

	_other_backup="${_other}${BACKUP_SUFFIX}"
	info "Moving competing database aside: $_other -> $_other_backup"
	if [ -e "$_other_backup" ]; then
		rm -f "$_other_backup" || warn "Could not remove previous backup $_other_backup"
	fi
	if mv -f "$_other" "$_other_backup"; then
		info "Competing database disabled (backed up): $_other_backup"
	else
		warn "Failed to move competing database aside: $_other"
	fi
}

# Choose a staging base with enough space for large CVD/CLD files.
# Prefer: STAGE_BASE, then <volume>/tmp next to QNAP AV DB, then TMPDIR, then /tmp.
choose_stage_base() {
	if [ -n "$STAGE_BASE" ]; then
		printf '%s\n' "$STAGE_BASE"
		return 0
	fi

	# Derive /share/CACHEDEVn_DATA from the antivirus DB path when possible.
	case "$QNAP_AV_DB_DIR" in
		/share/*_DATA/*|/share/*_DATA)
			_vol="$(printf '%s\n' "$QNAP_AV_DB_DIR" | sed -n 's|^\(/share/[^/]*_DATA\)/.*|\1|p')"
			if [ -z "$_vol" ]; then
				_vol="$(printf '%s\n' "$QNAP_AV_DB_DIR" | sed -n 's|^\(/share/[^/]*_DATA\)$|\1|p')"
			fi
			if [ -n "$_vol" ] && [ -d "$_vol" ]; then
				printf '%s/tmp\n' "$_vol"
				return 0
			fi
			;;
	esac

	if [ -n "${TMPDIR:-}" ] && [ -d "${TMPDIR}" ]; then
		printf '%s\n' "$TMPDIR"
		return 0
	fi

	printf '%s\n' "/tmp"
}

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------
info "Starting ClamAV definition sync"

if [ ! -x "$FRESHCLAM_BIN" ]; then
	die "freshclam not found or not executable: $FRESHCLAM_BIN"
fi

if [ ! -d "$ENTWARE_DB_DIR" ]; then
	die "Entware ClamAV database directory does not exist: $ENTWARE_DB_DIR"
fi

if ! QNAP_AV_DB_DIR="$(detect_qnap_av_db_dir)"; then
	die "QNAP Antivirus database directory not found. Set QNAP_AV_DB_DIR explicitly after verifying the path on this system."
fi

if [ ! -d "$QNAP_AV_DB_DIR" ]; then
	die "QNAP Antivirus database directory is not a directory: $QNAP_AV_DB_DIR"
fi

if [ ! -w "$QNAP_AV_DB_DIR" ]; then
	die "QNAP Antivirus database directory is not writable: $QNAP_AV_DB_DIR"
fi

info "freshclam:        $FRESHCLAM_BIN"
info "Entware DB dir:   $ENTWARE_DB_DIR"
info "QNAP AV DB dir:   $QNAP_AV_DB_DIR"

# Determine ownership/mode from an existing QNAP database file when present.
# Do not assume clamav:clamav on every system.
OWNERSHIP=""
MODE=""
for _name in $DB_NAMES; do
	for _ext in cld cvd; do
		_existing="${QNAP_AV_DB_DIR}/${_name}.${_ext}"
		if [ -e "$_existing" ]; then
			OWNERSHIP="$(detect_ownership "$_existing" || true)"
			MODE="$(detect_mode "$_existing" || true)"
			if [ -n "$OWNERSHIP" ]; then
				info "Preserving ownership from ${_name}.${_ext}: $OWNERSHIP"
			fi
			if [ -n "$MODE" ]; then
				info "Preserving mode from ${_name}.${_ext}: $MODE"
			fi
			break
		fi
	done
	if [ -n "$OWNERSHIP" ]; then
		break
	fi
done

if [ -z "$OWNERSHIP" ]; then
	warn "Could not determine existing QNAP DB ownership; copied files will keep the ownership produced by cp/chown defaults."
fi

# ---------------------------------------------------------------------------
# Run freshclam
# ---------------------------------------------------------------------------
info "Running freshclam..."
if ! "$FRESHCLAM_BIN"; then
	# freshclam may return nonzero when databases are already up to date on
	# some versions. Treat missing/empty DB files after the run as fatal;
	# otherwise continue if databases are present.
	warn "freshclam exited with a nonzero status; verifying databases before continuing"
fi

# Resolve which files to sync after freshclam (supports .cld and .cvd).
SYNC_FILES=""
MISSING=""
for _name in $DB_NAMES; do
	if _file="$(resolve_db_file "$ENTWARE_DB_DIR" "$_name")"; then
		info "Entware ${_name}: ${_file}"
		SYNC_FILES="${SYNC_FILES} ${_file}"
	else
		MISSING="${MISSING} ${_name}.cld|${_name}.cvd"
	fi
done

# Trim leading space
SYNC_FILES="$(printf '%s\n' "$SYNC_FILES" | sed 's/^ *//')"

if [ -n "$MISSING" ]; then
	die "Required Entware database files missing or empty after freshclam:${MISSING}"
fi

info "Entware database files verified: $SYNC_FILES"

# ---------------------------------------------------------------------------
# Stage, backup, and install database files safely
# ---------------------------------------------------------------------------
STAGE_DIR=""
cleanup() {
	# Invoked via trap; shellcheck may mark this as unreachable.
	# shellcheck disable=SC2317
	if [ -n "$STAGE_DIR" ] && [ -d "$STAGE_DIR" ]; then
		rm -rf "$STAGE_DIR"
	fi
}
trap cleanup EXIT INT TERM HUP

_stage_base="$(choose_stage_base)"
mkdir -p "$_stage_base" || die "Failed to create staging base directory: $_stage_base"
info "Staging base: $_stage_base"

STAGE_DIR=""
if command -v mktemp >/dev/null 2>&1; then
	STAGE_DIR="$(mktemp -d "${_stage_base}/qnap-av-db-sync.XXXXXX" 2>/dev/null || true)"
fi
if [ -z "$STAGE_DIR" ] || [ ! -d "$STAGE_DIR" ]; then
	STAGE_DIR="${_stage_base}/qnap-av-db-sync.$$"
	mkdir -p "$STAGE_DIR" || die "Failed to create staging directory"
fi

for _file in $SYNC_FILES; do
	_src="${ENTWARE_DB_DIR}/${_file}"
	_staged="${STAGE_DIR}/${_file}"

	if ! file_nonempty "$_src"; then
		die "Source database missing or empty before copy: $_src"
	fi

	# Copy to staging first so a failed transfer does not touch the live DB.
	cp -f "$_src" "$_staged" || die "Failed to stage $_file"
	if ! file_nonempty "$_staged"; then
		die "Staged database is empty: $_staged"
	fi

	# Compare sizes as a basic integrity check.
	_src_size="$(wc -c < "$_src" | tr -d ' ')"
	_stg_size="$(wc -c < "$_staged" | tr -d ' ')"
	if [ "$_src_size" != "$_stg_size" ]; then
		die "Staged size mismatch for ${_file}: source=${_src_size} staged=${_stg_size}"
	fi

	if [ -n "$OWNERSHIP" ] && command -v chown >/dev/null 2>&1; then
		chown "$OWNERSHIP" "$_staged" || warn "Could not apply ownership $OWNERSHIP to staged $_file"
	fi
	if [ -n "$MODE" ] && command -v chmod >/dev/null 2>&1; then
		chmod "$MODE" "$_staged" || warn "Could not apply mode $MODE to staged $_file"
	fi
done

info "Staged database files ready; installing into QNAP Antivirus directory"

for _file in $SYNC_FILES; do
	_staged="${STAGE_DIR}/${_file}"
	_dest="${QNAP_AV_DB_DIR}/${_file}"
	_backup="${_dest}${BACKUP_SUFFIX}"

	# Backup existing destination when present (overwrite prior script backup).
	if [ -e "$_dest" ]; then
		cp -f "$_dest" "$_backup" || warn "Could not back up existing $_dest"
	fi

	# Atomic-ish replace: copy staged file to a temp name in the destination
	# directory, then mv into place.
	_tmp_dest="${QNAP_AV_DB_DIR}/.${_file}.new.$$"
	cp -f "$_staged" "$_tmp_dest" || die "Failed to copy staged ${_file} into QNAP directory"
	if ! file_nonempty "$_tmp_dest"; then
		rm -f "$_tmp_dest"
		die "Temporary destination database empty: $_tmp_dest"
	fi

	if [ -n "$OWNERSHIP" ] && command -v chown >/dev/null 2>&1; then
		chown "$OWNERSHIP" "$_tmp_dest" || warn "Could not set ownership on temporary $_file"
	fi
	if [ -n "$MODE" ] && command -v chmod >/dev/null 2>&1; then
		chmod "$MODE" "$_tmp_dest" || warn "Could not set mode on temporary $_file"
	fi

	mv -f "$_tmp_dest" "$_dest" || die "Failed to install ${_file} into place"

	info "Installed ${_file} -> ${_dest}"
	warn_competing_db "$QNAP_AV_DB_DIR" "$_file"
done

# Final verification of destination files.
for _file in $SYNC_FILES; do
	_dest="${QNAP_AV_DB_DIR}/${_file}"
	if ! file_nonempty "$_dest"; then
		die "Destination database missing or empty after install: $_dest"
	fi
done

info "Synchronization completed successfully"
info "Synced files: $SYNC_FILES"
info "QNAP Antivirus database: $QNAP_AV_DB_DIR"
exit 0
