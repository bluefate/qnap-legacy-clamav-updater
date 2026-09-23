# Uninstall and recovery

This project’s removable pieces are the sync script, optional cron entry, and optional `freshclam.conf` changes. Entware ClamAV can remain installed if you still want it for other uses.

---

## 1. Remove the cron entry

Edit the persistent crontab:

```sh
cp -a /etc/config/crontab /etc/config/crontab.bak.$(date +%Y%m%d%H%M%S)
vi /etc/config/crontab
```

Delete any line containing `qnap-av-db-sync.sh`, then reload:

```sh
crontab /etc/config/crontab && /etc/init.d/crond.sh restart
```

Verify:

```sh
grep -F qnap-av-db-sync.sh /etc/config/crontab || echo 'No sync cron entry'
```

---

## 2. Remove the synchronization script

```sh
rm -f /opt/bin/qnap-av-db-sync.sh
```

If the installer created a timestamped backup such as `/opt/bin/qnap-av-db-sync.sh.bak.*`, you may remove those as well after you are sure you do not need them.

---

## 3. Restore backed-up freshclam configuration

If you changed Entware `freshclam.conf`, restore the backup created by the installer or by your manual `cp`:

```sh
# Example — use your actual backup name
ls -l /opt/etc/clamav/freshclam.conf.bak.*
cp -a /opt/etc/clamav/freshclam.conf.bak.YYYYMMDDHHMMSS /opt/etc/clamav/freshclam.conf
```

Also check `/opt/etc/freshclam.conf.bak.*` if that path was used.

Leaving the Entware ClamAV package installed is fine. Restoring `freshclam.conf` only reverts configuration this project may have altered.

---

## 4. Leave Entware ClamAV installed (optional)

You do **not** need to remove Entware ClamAV to uninstall this workaround.

If you explicitly want to remove the package (optional, unrelated to QNAP Antivirus itself):

```sh
/opt/bin/opkg remove clamav
```

Only do this if you understand it will remove Entware’s ClamAV binaries and may remove related files under `/opt`. Prefer leaving it installed unless you are sure.

---

## 5. Restore QNAP Antivirus database backups if necessary

The sync script may create per-file backups next to the QNAP CVD files, named like:

```text
main.cvd.bak.qnap-av-db-sync
daily.cvd.bak.qnap-av-db-sync
bytecode.cvd.bak.qnap-av-db-sync
```

under the QNAP Antivirus database directory (reference path):

```text
/share/CACHEDEV1_DATA/.antivirus/usr/share/clamav
```

To restore a previous CVD (example for `main.cvd`):

```sh
AVDB=/share/CACHEDEV1_DATA/.antivirus/usr/share/clamav   # verify on your NAS
cp -a "$AVDB/main.cvd.bak.qnap-av-db-sync" "$AVDB/main.cvd"
```

Repeat for `daily.cvd` and `bytecode.cvd` if needed. Preserve ownership afterward if your restore path changed it:

```sh
ls -l "$AVDB"/*.cvd
# chown to match what QNAP expects on your system, e.g. clamav:clamav on the reference host
```

Only restore backups when you intend to roll back definitions. Do not delete the live `.antivirus` tree.

---

## 6. What this uninstall does not undo

- It does not uninstall QNAP Antivirus.
- It does not automatically reverse unrelated QTS settings.
- It does not claim to make QNAP’s built-in definition updater work again.

After uninstall, QNAP Antivirus will again depend solely on QNAP’s own update mechanism unless you reinstall this workaround.
