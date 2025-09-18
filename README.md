# Restore DB Template

This repository contains a reusable template to restore a production SQL Server backup into a development instance using Windows Integrated Authentication.

Files
- `scripts/restore-prod-to-dev.ps1` - PowerShell script that downloads a backup and runs `RESTORE DATABASE` using `sqlcmd -E` (Integrated Auth).
- `scripts/dry_run_restore.ps1` - Helper script that prints the RESTORE SQL without executing it (safe dry-run).
- `.github/workflows/restore-db.yml` - GitHub Actions workflow template (manual `workflow_dispatch`) that runs the dry-run and optionally executes the restore.

Prerequisites
- A Windows runner (self-hosted recommended) joined to your AD domain if you need Integrated Authentication.
- `sqlcmd` (SQL Server command-line tools) installed and available on `PATH`.
- The runner account must have permission to read the backup (HTTP/UNC/local) and to restore databases on the target SQL Server.

Usage
- From GitHub: run the `Restore Prod Backup to Dev` workflow manually and provide:
  - `backup_url` (URL or UNC/local path to the backup file)
  - `target_database` (target DB name in dev)
  - optional `post_restore_script` (path on the runner)
  - set `execute` to `true` to perform the actual restore; otherwise the workflow performs a dry-run only.

- Locally (for testing): run the dry-run and/or restore scripts on a Windows machine with appropriate permissions:

```powershell
# dry-run
.\scripts\dry_run_restore.ps1 -BackupPath 'D:\backup\advent.bak' -TargetDatabase 'AdventureWorksDW2020_DEV'

# actual (destructive) restore - only run when ready
.\scripts\restore-prod-to-dev.ps1 -BackupUrl 'D:\backup\advent.bak' -TargetDatabase 'AdventureWorksDW2020_DEV'
```

Safety
- The workflow defaults to dry-run to avoid accidental destructive operations.
- The restore script uses Windows Integrated Authentication only (`sqlcmd -E`) and does not contain SQL credentials.

License
- No license specified.
