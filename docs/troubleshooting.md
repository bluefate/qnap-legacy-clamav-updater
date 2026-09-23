# Troubleshooting

This guide covers common failures with the Entware `freshclam` + QNAP database sync workaround.

Reference host: QNAP TS-469L | QTS 4.3.4.2814 | Entware ClamAV 1.4.3

---

## Stale .cld still used after syncing newer .cvd

**Symptoms:** Sync reports success for `main.cvd` / `bytecode.cvd`, but definitions still look old.

**Cause:** ClamAV prefers `.cld` when both `.cld` and `.cvd` exist. An ancient `main.cld` can override a fresh `main.cvd`.

**Fix:** Use a sync script with `DISABLE_COMPETING=yes` (default in this project). It moves the unused competitor to `*.bak.qnap-av-db-sync` after installing the Entware file. Confirm with:

```sh
ls -l /share/CACHEDEV*_DATA/.antivirus/usr/share/clamav/main.* \
      /share/CACHEDEV*_DATA/.antivirus/usr/share/clamav/daily.* \
      /share/CACHEDEV*_DATA/.antivirus/usr/share/clamav/bytecode.*
```

---

## No space left on device while staging

**Symptoms:** Sync fails copying into `/tmp/...` with `No space left on device`.

**Cause:** On many QNAP systems `/tmp` is a small ramdisk and cannot hold `main.cvd`.

**Fix:** Current scripts stage under `/share/CACHEDEV*_DATA/tmp` when the Antivirus path is on that volume. Override with `STAGE_BASE=/path/with/space` if needed.

---

## Sync aborts looking for daily.cvd / missing CVD after successful freshclam

**Symptoms:** `freshclam` reports databases up to date, but the sync script logs `Missing or empty .../daily.cvd` and does not copy files. Entware may show `daily.cld` instead of `daily.cvd`.

**Cause:** Older sync scripts only copied `main.cvd`, `daily.cvd`, and `bytecode.cvd`. Current ClamAV often maintains `daily.cld` after incremental updates.

**Fix:** Use a sync script that resolves each of `main` / `daily` / `bytecode` to `.cld` (preferred) or `.cvd`. Re-run the sync after updating the script.

---

## freshclam command not found

**Symptoms:** `freshclam: not found` or sync script exits because `/opt/sbin/freshclam` is missing.

**Checks:**

```sh
ls -l /opt/sbin/freshclam
/opt/bin/opkg list-installed | grep -i clam
```

**Fix:** Install Entware ClamAV (see [installation.md](installation.md)). If the binary lives elsewhere, set:

```sh
export FRESHCLAM_BIN=/path/to/freshclam
```

---

## ClamAV database download failure

**Symptoms:** `freshclam` errors contacting mirrors, timeouts, or HTTP failures; CVD files missing afterward.

**Checks:**

```sh
/opt/sbin/freshclam
ls -l /opt/var/lib/clamav/
```

**Fix ideas:**

- Confirm DNS and outbound HTTPS/HTTP from the NAS.
- Retry later (mirror rate limits).
- Review `freshclam.conf` for invalid custom mirrors.
- Ensure `/opt/var/lib/clamav` exists and is writable by `DatabaseOwner`.

The sync script will refuse to copy if CVD files are missing or empty.

---

## DatabaseOwner errors / “user nobody” errors

**Symptoms:** `freshclam` complains about user `nobody`, cannot drop privileges, or cannot write databases.

**Background:** On the reference host, an incorrect database owner configuration produced errors involving `nobody`. The working setting was:

```text
DatabaseOwner admin
```

**Fix:**

1. Back up `freshclam.conf`.
2. Set `DatabaseOwner admin` (or the account that should own Entware DB files on your system).
3. Ensure `DatabaseDirectory /opt/var/lib/clamav` is writable by that owner.
4. Re-run `/opt/sbin/freshclam`.

Do not confuse Entware DB ownership (`DatabaseOwner`) with QNAP Antivirus CVD ownership (often `clamav:clamav` on the reference host). They serve different directories.

---

## Permission denied

**Symptoms:** Cannot write Entware DB dir, cannot copy into QNAP Antivirus dir, or `chown` fails.

**Checks:**

```sh
ls -ld /opt/var/lib/clamav
ls -ld /share/CACHEDEV*_DATA/.antivirus/usr/share/clamav
whoami
```

**Fix:** Run the sync script with sufficient privileges (typically `admin`). Confirm the Antivirus database directory is writable. Avoid weakening permissions broadly; fix the specific path ownership/mode instead.

---

## QNAP antivirus database directory not found

**Symptoms:** Installer or sync script cannot locate `.antivirus/usr/share/clamav`.

**Checks:**

```sh
ls -ld /share/CACHEDEV*_DATA/.antivirus/usr/share/clamav
ls -ld /share/*/.antivirus/usr/share/clamav
```

**Fix:**

- Ensure QNAP Antivirus is installed.
- Identify the correct volume (not every system uses `CACHEDEV1_DATA`).
- Set the path explicitly:

```sh
export QNAP_AV_DB_DIR=/share/CACHEDEVn_DATA/.antivirus/usr/share/clamav
```

Never invent a path under a data volume without confirming it is the Antivirus database directory.

---

## Incorrect file ownership

**Symptoms:** Files sync, but QNAP Antivirus behaves as if definitions are missing or unreadable.

**Checks:**

```sh
ls -l /share/CACHEDEV*_DATA/.antivirus/usr/share/clamav/*.cvd
```

On the tested TS-469L, QNAP CVD files were `clamav:clamav`. Other systems may differ.

**Fix:** The sync script preserves ownership detected from existing QNAP CVD files. If files were previously copied with the wrong owner, restore correct ownership based on what QNAP created, then re-run the sync script.

---

## Cron works manually but not after reboot

**Symptoms:** Manual `/opt/bin/qnap-av-db-sync.sh` works; scheduled runs stop after reboot.

**Cause:** QNAP can regenerate the active crontab. Jobs added only via `crontab -e` (or only in memory) may disappear.

**Fix (persistent method):**

1. Put the job in `/etc/config/crontab`.
2. Load and restart:

```sh
crontab /etc/config/crontab && /etc/init.d/crond.sh restart
```

Also check for Entware shadowing QNAP’s `crontab` binary on `PATH`.

**Verify:**

```sh
grep -F qnap-av-db-sync.sh /etc/config/crontab
/usr/bin/crontab -l 2>/dev/null || crontab -l
```

---

## QNAP GUI still reports an update failure

**Symptoms:** CVD files on disk are current, scans may work, but the Antivirus UI still shows:

```text
[Antivirus] Failed to update virus definitions.
```

**Explanation:** The GUI message often reflects **QNAP’s own updater**, not whether the workaround maintained the database files. This project bypasses QNAP’s updater by synchronizing definitions from Entware `freshclam`. The GUI can continue to report updater failure even when the CVD files used for scanning are successfully refreshed.

**What to trust instead:**

- Timestamps/sizes from `scripts/verify.sh`
- Successful completion of `/opt/bin/qnap-av-db-sync.sh`
- Actual Antivirus scan behavior

---

## QNAP Antivirus does not recognize copied databases

**Symptoms:** Files are present in the QNAP clamav directory but Antivirus still acts outdated or fails scans.

**Checks:**

1. Confirm you copied into the directory Antivirus actually uses (verify path).
2. Confirm `main.cvd`, `daily.cvd`, and `bytecode.cvd` are non-empty.
3. Confirm ownership/permissions match prior QNAP CVD files.
4. Confirm you did not leave partial `.*.new.*` temp files as the only copies (the sync script should clean/replace atomically via `mv`).

**Avoid:** Deleting unrelated files under `.antivirus`. Only replace the CVD files you intend to update, with backups.

If needed, restore from `.bak.qnap-av-db-sync` backups created by the sync script (see [uninstall.md](uninstall.md)).

---

## Sync script reports freshclam nonzero but continues or warns

Some `freshclam` versions exit nonzero when databases are already up to date or on soft warnings. The sync script verifies CVD presence/size after the run and fails hard only if required files are missing or empty.

---

## Still stuck?

Re-run read-only diagnostics:

```sh
sh scripts/verify.sh
```

Compare Entware vs QNAP CVD timestamps and ownership side by side before making further changes.
