# The problem

## Symptom

On the reference legacy QNAP system, the built-in Antivirus application reported:

```text
[Antivirus] Failed to update virus definitions.
Please try again later or update the definitions manually.
```

Virus definition updates through QNAP’s own Antivirus updater were no longer reliable.

## Two ClamAV installations

It is easy to confuse two separate ClamAV stacks that can coexist on the same NAS:

### 1. QNAP’s bundled ClamAV (Antivirus application)

- Managed by QNAP’s Antivirus software and QTS packaging.
- Stores definition databases in the QNAP Antivirus directory tree.
- On the tested TS-469L this was:

  `/share/CACHEDEV1_DATA/.antivirus/usr/share/clamav`

- The QNAP GUI “update definitions” action targets **this** installation.

### 2. Entware ClamAV

- Installed through Entware (`opkg`), independent of QNAP’s Antivirus app.
- Provides a current `freshclam` binary, commonly at `/opt/sbin/freshclam`.
- Stores definition databases under Entware’s directory, commonly:

  `/opt/var/lib/clamav`

- Can successfully download current `main.cvd`, `daily.cvd`, and `bytecode.cvd` even when QNAP’s updater cannot.

## Why installing newer ClamAV alone does not fix Antivirus

Entware ClamAV and QNAP Antivirus do **not** share a database directory by default.

So this sequence is incomplete:

1. Install Entware ClamAV.
2. Run `freshclam` successfully.
3. Expect QNAP Antivirus to “just work.”

QNAP Antivirus continues reading from its own database path. Until those CVD files are synchronized into the QNAP directory (with appropriate ownership/permissions), the Antivirus application still sees stale or missing definitions—even though Entware’s databases are current.

## What this project does

1. Uses Entware `freshclam` to keep `/opt/var/lib/clamav` current.
2. Copies the verified CVD files into the QNAP Antivirus database directory.
3. Preserves ownership discovered on the existing QNAP CVD files (observed as `clamav:clamav` on the tested TS-469L).
4. Optionally schedules the sync with QNAP’s persistent cron mechanism.

## Reference environment

| Item | Value |
|------|--------|
| Model | QNAP TS-469L |
| QTS | 4.3.4.2814 |
| Entware ClamAV | 1.4.3 |

Paths and users above are from that system. Other QNAP models may differ—always verify before relying on defaults.
