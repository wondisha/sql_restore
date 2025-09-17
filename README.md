# Restore DB Template

This repository contains a reusable template to restore a production SQL Server backup into a development instance using Windows Integrated Authentication.

Files
- `scripts/restore-prod-to-dev.ps1` - PowerShell script that downloads a backup and runs `RESTORE DATABASE` using `sqlcmd -E` (Integrated Auth).
- `.github/workflows/restore-db.yml` - GitHub Actions workflow template (manual `workflow_dispatch`) that calls the script on a Windows runner.

Prerequisites
- A Windows runner (self-hosted recommended) with `sqlcmd` available and access to the target SQL Server instance.
- The runner account must have sufficient SQL permissions to restore databases and access to the paths used for MDF/LDF.

Usage
- From GitHub: run the `Restore Prod -> Dev (Template)` workflow manually and provide:
  - `backup_url` (URL to the backup file)
  - `target_database` (target DB name in dev)
  - optional `post_restore_script` (path on the runner)

- Locally (for testing): run the script on a Windows machine with permissions:

```powershell
.
\scripts\restore-prod-to-dev.ps1 -BackupUrl '<backup url>' -TargetDatabase 'dev_db'
```

Notes
- The script uses Windows Integrated Authentication only (`sqlcmd -E`). Do not include SQL credentials in the script.
- Review and adapt paths (MDF/LDF destination) to match your SQL Server instance.

License: none
