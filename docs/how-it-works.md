# How it works

## Pipeline

```text
freshclam
    |
    v
/opt/var/lib/clamav
    |
    v
qnap-av-db-sync.sh
    |
    v
/share/CACHEDEV1_DATA/.antivirus/usr/share/clamav
    |
    v
QNAP Antivirus
```

Paths shown are from the tested QNAP TS-469L. Detect and validate on your system before use.

## Mermaid diagram

```mermaid
flowchart TD
    A[ClamAV definition servers] --> B[Entware freshclam]
    B --> C["/opt/var/lib/clamav<br/>main.cvd daily.cvd bytecode.cvd"]
    C --> D[qnap-av-db-sync.sh]
    D --> E["QNAP Antivirus DB<br/>/share/CACHEDEV*_DATA/.antivirus/usr/share/clamav"]
    E --> F[QNAP Antivirus application]
```

## Step by step

1. **`freshclam` (Entware)** contacts ClamAV definition mirrors and updates CVD files under the Entware database directory (`DatabaseDirectory`, typically `/opt/var/lib/clamav`).
2. **`qnap-av-db-sync.sh`** verifies that `main.cvd`, `daily.cvd`, and `bytecode.cvd` exist and are non-empty.
3. The script stages copies, backs up existing QNAP CVD files when present, then installs the new files into the QNAP Antivirus database directory.
4. **Ownership and mode** are taken from existing QNAP CVD files when detectable (on the tested system: `clamav:clamav`), not hard-coded blindly.
5. **QNAP Antivirus** continues to use its own database path; it does not need to call Entware `freshclam` directly.

## Why synchronization is required

| Component | Database directory (reference host) |
|-----------|--------------------------------------|
| Entware ClamAV | `/opt/var/lib/clamav` |
| QNAP Antivirus | `/share/CACHEDEV1_DATA/.antivirus/usr/share/clamav` |

Without the sync step, only Entware’s copy of the definitions is updated.

## Scheduling

A nightly cron entry runs the sync script so definitions stay current without manual intervention. On QNAP, the job must be stored in `/etc/config/crontab` and reloaded so it survives reboot. See [installation.md](installation.md).

## What this does *not* do

- It does not replace QNAP Antivirus with Entware `clamscan`.
- It does not guarantee the QNAP GUI updater will start succeeding again.
- It does not claim identical paths on unverified QNAP models.
