# AGENTS.md

Persistent technical context and development instructions for contributors and coding agents working on this repository.

This file is **not** end-user documentation. User-facing guidance belongs in `README.md` and `docs/`.

---

## Purpose of this project

This project documents and automates a workaround for **legacy QNAP NAS devices** where the built-in Antivirus application can no longer update ClamAV virus definitions.

The public repository name is:

`qnap-legacy-clamav-updater`

It is community maintained and is **not affiliated with or supported by QNAP or ClamAV**. That disclaimer must remain visible in the README.

---

## Reference implementation (known-good system)

Treat the following as the **original known reference implementation**, not as universal truth for every QNAP.

| Item | Value |
|------|--------|
| Model | QNAP TS-469L |
| QTS | 4.3.4.2814 |
| Environment | Legacy QNAP with Entware |
| RAM (reference host) | 3 GB |
| Entware ClamAV | 1.4.3 |

### Original symptom

QNAP Antivirus reported:

```text
[Antivirus] Failed to update virus definitions.
Please try again later or update the definitions manually.
```

The bundled QNAP ClamAV installation could no longer reliably retrieve current virus definitions.

### Working workaround on the reference host

1. Install a current ClamAV through Entware.
2. Use Entware `freshclam` to download definitions into the Entware database directory.
3. Synchronize those CVD files into the separate directory used by QNAP Antivirus.
4. Preserve ownership expected by QNAP Antivirus.
5. Schedule the sync with a persistent QNAP cron entry.

### Reference paths and settings

| Role | Path / value |
|------|----------------|
| Entware freshclam | `/opt/sbin/freshclam` |
| Entware DB directory | `/opt/var/lib/clamav` |
| Entware CVD files | `main.cvd`, `daily.cvd`, `bytecode.cvd` under the Entware DB directory |
| QNAP Antivirus DB directory | `/share/CACHEDEV1_DATA/.antivirus/usr/share/clamav` |
| Sync script install path | `/opt/bin/qnap-av-db-sync.sh` |
| freshclam `DatabaseDirectory` | `/opt/var/lib/clamav` |
| freshclam `DatabaseOwner` | `admin` |
| Observed QNAP CVD ownership | `clamav:clamav` |
| Recommended cron | `15 3 * * * /opt/bin/qnap-av-db-sync.sh >/dev/null 2>&1` |

### Important historical notes

- `DatabaseOwner admin` mattered on the reference host because an earlier configuration produced errors involving the `nobody` user.
- Updating Entware ClamAV alone does **not** fix QNAP Antivirus: the two installations use **different database directories**.
- QNAP’s GUI updater may still report failures even when this workaround successfully maintains the CVD files on disk.

---

## Non-negotiable rules for agents

### Do not assume universality

- Paths, users, groups, QTS versions, volume names (`CACHEDEV1_DATA`, etc.), and directory layouts may differ on other QNAP systems.
- The public project must **detect and validate** values wherever possible.
- Document that other legacy QNAP models *may* work if they use the same antivirus directory structure, but users must verify paths before installation.
- Do **not** claim compatibility with unverified models.

### Prefer live observation when available

- Before making implementation decisions about the reference NAS, inspect the current TS-469L if terminal/SSH access is available.
- Prefer current observations over assumptions based solely on this historical context.
- If the NAS is not reachable, fall back to this reference context and clearly treat paths as defaults that require validation.

### Privacy and publishing safety

Never commit or publish:

- NAS hostnames
- IP addresses
- credentials, SSH keys, API keys
- personal filesystem paths outside this repository
- other network-specific or private information

Keep examples generic. Use the reference paths above only as documented defaults from the tested system.

### Safety on a privileged NAS

Scripts may run with elevated privileges. They must fail safely.

Before changing QNAP antivirus databases:

1. Create backups where practical.
2. Verify source files exist and are non-empty.
3. Verify the destination directory exists.
4. Preserve permissions and ownership discovered on the target system.
5. Avoid deleting unrelated files.
6. Use staging / temp files so partial copies are not left as the live database.

Also:

- Do not modify unrelated QNAP configuration.
- Do not restart QNAP services unless absolutely necessary and documented.
- Do not overwrite an existing `freshclam.conf` without creating a backup first.
- Do not download or execute arbitrary remote scripts.
- Do not use `eval`.
- Quote shell variables correctly.
- Prefer POSIX `sh` compatible scripts for legacy QNAP / BusyBox environments. Avoid Bash-specific features unless compatibility is verified.

### Cron persistence on QNAP

Editing only the active crontab is **not** sufficient. QNAP can regenerate cron configuration after reboot.

Document and implement the persistent QNAP procedure:

1. Edit `/etc/config/crontab` (not `crontab -e`).
2. Load it with `crontab /etc/config/crontab`.
3. Restart cron with `/etc/init.d/crond.sh restart`.

Avoid duplicate cron entries. Be aware that Entware’s `crontab` on `PATH` can shadow QNAP’s crontab binary.

### Releases

- Create an initial release-ready tree, but **do not tag a release** until scripts have been tested on the TS-469L.
- Version the first successfully tested release as **1.0.0**.

---

## Repository layout

```text
qnap-legacy-clamav-updater/
├── AGENTS.md
├── README.md
├── LICENSE
├── .gitignore
├── scripts/
│   ├── install.sh
│   ├── qnap-av-db-sync.sh
│   └── verify.sh
├── config/
│   └── freshclam.conf.example
└── docs/
    ├── problem.md
    ├── how-it-works.md
    ├── installation.md
    ├── troubleshooting.md
    └── uninstall.md
```

### File responsibilities

| Path | Role |
|------|------|
| `AGENTS.md` | Persistent agent/developer context (this file) |
| `README.md` | User-facing overview only; do not dump this entire context into it |
| `LICENSE` | MIT |
| `scripts/qnap-av-db-sync.sh` | Run freshclam; sync CVD files into QNAP Antivirus DB safely |
| `scripts/install.sh` | Interactive installer with confirmation, backups, optional cron |
| `scripts/verify.sh` | Read-only diagnostics; never modify the system; never transmit data |
| `config/freshclam.conf.example` | Example Entware freshclam config |
| `docs/problem.md` | Original symptom and two-installation distinction |
| `docs/how-it-works.md` | Pipeline explanation + Mermaid diagram |
| `docs/installation.md` | Full manual install so users need not rely on `install.sh` |
| `docs/troubleshooting.md` | Common failures, including GUI still reporting update failure |
| `docs/uninstall.md` | Cron removal, script removal, config/DB restore |

---

## Script requirements (summary)

### `qnap-av-db-sync.sh`

- Configurable paths near the top; allow environment overrides.
- Verify freshclam and Entware DB dir.
- Detect/validate QNAP Antivirus DB dir (do not hard-require `CACHEDEV1_DATA` without probing).
- Run `/opt/sbin/freshclam` (or configured path).
- Verify `main.cvd`, `daily.cvd`, `bytecode.cvd`.
- Stage copies; backup existing destination CVD files when practical.
- Preserve ownership/mode discovered from existing QNAP CVD files (reference observed `clamav:clamav`, but do not assume it).
- Log useful status; nonzero exit on failure.
- Never delete unrelated files from the QNAP antivirus directory.

### `install.sh`

- Reasonable QNAP detection.
- Check Entware and freshclam.
- Detect antivirus DB directory.
- Show detected paths and require confirmation before changes.
- Back up configs that will change.
- Install sync script to `/opt/bin/qnap-av-db-sync.sh` and make it executable.
- Optionally configure persistent cron without duplicates.

### `verify.sh`

- Read-only only.
- Report model, QTS version (if detectable), Entware, ClamAV/freshclam versions, DB locations, CVD timestamps/sizes/ownership/permissions, cron state, last update info when available.
- Mark each check `OK` / `WARNING` / `ERROR`.
- Do not transmit any system information anywhere.

---

## Documentation tone

- Be precise about what was tested vs what is speculative.
- Explain *why* the workaround works (separate DB directories + sync).
- README covers user needs: problem, architecture, tested environment, requirements, install, verify, cron, troubleshooting pointers, uninstall, security, disclaimer.
- Keep a prominent status line near the top of the README, for example:

  `Tested: QNAP TS-469L | QTS 4.3.4 | Entware | ClamAV 1.4.3`

  More specific firmware detail such as `4.3.4.2814` may appear in docs where helpful; do not invent broader compatibility.

---

## Quality checklist for agents

- [ ] POSIX `sh` compatibility for legacy QNAP shells
- [ ] `shellcheck` run on all scripts when available
- [ ] No secrets or private network details in commits
- [ ] Detection/validation preferred over hard-coded assumptions
- [ ] Backups before overwriting configs or CVD files
- [ ] Persistent QNAP cron documented and used correctly
- [ ] README remains user-focused; detailed agent context stays in `AGENTS.md`
- [ ] Logical commits rather than one monolithic commit when initializing history
- [ ] No GitHub release tag until TS-469L testing succeeds

---

## Suggested commit themes

When building or restructuring the repository, prefer logical commits such as:

1. Initial project structure (including `AGENTS.md`, `LICENSE`, `.gitignore`)
2. Add ClamAV synchronization script
3. Add installer and verification tools
4. Add installation documentation
5. Add troubleshooting and recovery documentation
