# Installation

You can use `scripts/install.sh` or follow this manual procedure. The manual steps are the source of truth: everything the installer does should be understandable here.

**Tested reference:** QNAP TS-469L | QTS 4.3.4.2814 | Entware | ClamAV 1.4.3

Paths below are defaults from that system. **Verify them on your NAS** before copying files.

---

## 1. Prerequisites

- SSH login with sufficient privileges (typically `admin`)
- Entware installed (`/opt` present, `opkg` working)
- QNAP Antivirus installed so its database directory exists
- Free disk space for CVD downloads and backups

Confirm Entware:

```sh
ls -ld /opt
/opt/bin/opkg --version
```

---

## 2. Install Entware ClamAV

Exact package names can vary by Entware feed. Typical approach:

```sh
/opt/bin/opkg update
/opt/bin/opkg install clamav
```

Confirm `freshclam`:

```sh
ls -l /opt/sbin/freshclam
/opt/sbin/freshclam --version
```

Create the Entware database directory if needed:

```sh
mkdir -p /opt/var/lib/clamav
```

---

## 3. Configure freshclam

Locate the Entware `freshclam.conf` (common locations):

- `/opt/etc/clamav/freshclam.conf`
- `/opt/etc/freshclam.conf`

**Always back up before changing:**

```sh
cp -a /opt/etc/clamav/freshclam.conf /opt/etc/clamav/freshclam.conf.bak.$(date +%Y%m%d%H%M%S)
```

Ensure at least:

```text
DatabaseDirectory /opt/var/lib/clamav
DatabaseOwner admin
```

An example file is shipped as [`config/freshclam.conf.example`](../config/freshclam.conf.example).

### Why `DatabaseOwner admin`?

On the reference host, an incorrect owner setting led to errors involving the `nobody` user. Setting `DatabaseOwner admin` matched the working Entware configuration on that system. If your Entware package expects a different owner, adjust carefully and confirm `freshclam` can write the database directory.

Do **not** overwrite an existing `freshclam.conf` without a backup.

---

## 4. Download definitions with freshclam

```sh
/opt/sbin/freshclam
```

Confirm database files (extensions may be `.cvd` and/or `.cld`):

```sh
ls -l /opt/var/lib/clamav/main.* \
      /opt/var/lib/clamav/daily.* \
      /opt/var/lib/clamav/bytecode.*
```

Each of `main`, `daily`, and `bytecode` should have a non-empty `.cld` and/or `.cvd`. After updates, `daily.cld` is common.

---

## 5. Locate the QNAP Antivirus database directory

On the tested TS-469L:

```text
/share/CACHEDEV1_DATA/.antivirus/usr/share/clamav
```

On other systems, probe without assuming `CACHEDEV1`:

```sh
ls -ld /share/CACHEDEV*_DATA/.antivirus/usr/share/clamav
ls -ld /share/*/.antivirus/usr/share/clamav
```

Inspect existing ownership (do not assume `clamav:clamav` everywhere):

```sh
ls -l /share/CACHEDEV1_DATA/.antivirus/usr/share/clamav/*.cvd
```

On the reference host, QNAP CVD files were owned by `clamav:clamav`.

---

## 6. Install the synchronization script

From this repository checkout:

```sh
cp scripts/qnap-av-db-sync.sh /opt/bin/qnap-av-db-sync.sh
chmod 755 /opt/bin/qnap-av-db-sync.sh
```

Optional environment overrides if your paths differ:

```sh
export FRESHCLAM_BIN=/opt/sbin/freshclam
export ENTWARE_DB_DIR=/opt/var/lib/clamav
export QNAP_AV_DB_DIR=/share/CACHEDEV1_DATA/.antivirus/usr/share/clamav
```

Run once manually:

```sh
/opt/bin/qnap-av-db-sync.sh
```

Confirm QNAP-side CVD files updated:

```sh
ls -l /share/CACHEDEV1_DATA/.antivirus/usr/share/clamav/*.cvd
```

The script stages copies, backs up previous CVD files with a `.bak.qnap-av-db-sync` suffix when replacing, preserves detected ownership/mode, and does not delete unrelated files in the QNAP antivirus directory.

---

## 7. Persistent cron on QNAP

Recommended schedule:

```cron
15 3 * * * /opt/bin/qnap-av-db-sync.sh >/dev/null 2>&1
```

### Important: survive reboot

QNAP may regenerate the active crontab after reboot. Official guidance is:

1. Edit **`/etc/config/crontab`** directly (do **not** rely on `crontab -e`).
2. Load and restart cron:

```sh
crontab /etc/config/crontab && /etc/init.d/crond.sh restart
```

Example append (after verifying no duplicate exists):

```sh
cp -a /etc/config/crontab /etc/config/crontab.bak.$(date +%Y%m%d%H%M%S)
grep -F 'qnap-av-db-sync.sh' /etc/config/crontab || \
  echo '15 3 * * * /opt/bin/qnap-av-db-sync.sh >/dev/null 2>&1' >> /etc/config/crontab
crontab /etc/config/crontab && /etc/init.d/crond.sh restart
```

### Entware `crontab` conflict

If Entware’s BusyBox `crontab` appears earlier on `PATH`, `crontab` may fail or manage a different spool. Prefer QNAP’s binary (often `/usr/bin/crontab`) or adjust `PATH` when loading `/etc/config/crontab`.

Verify:

```sh
grep -F 'qnap-av-db-sync.sh' /etc/config/crontab
/usr/bin/crontab -l 2>/dev/null || crontab -l
```

---

## 8. Verification

```sh
sh scripts/verify.sh
```

Or, if installed from the repo on another path, run the copy you checked out. The script is read-only and does not transmit data.

Also open QNAP Antivirus and confirm it can run scans. The GUI may still show that QNAP’s *own* definition updater failed; that does not necessarily mean the synchronized CVD files are unusable. See [troubleshooting.md](troubleshooting.md).

---

## Automated installer

```sh
sh scripts/install.sh
```

The installer:

1. Checks for QNAP markers and Entware/`freshclam`
2. Detects the Antivirus DB directory
3. Shows paths and asks for confirmation
4. Backs up files it changes
5. Installs `/opt/bin/qnap-av-db-sync.sh`
6. Optionally writes `freshclam.conf` from the example (only after backup/confirmation)
7. Optionally adds a non-duplicate persistent cron entry

Review the scripts before running them on a production NAS.
