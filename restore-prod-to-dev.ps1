<#
.SYNOPSIS
  Restore a SQL Server database from a production backup to a development instance.

.DESCRIPTION
  This script downloads a backup file from a URL (supports SAS token or private URL),
  copies it to the SQL Server backup folder, and restores the database to the target
  instance. It supports renaming the database, moving MDF/LDF files, and running
  optional post-restore SQL (e.g., set single user, reset logins).

.NOTES
  - Intended for use in CI pipelines. Keep secrets out of repo; provide via environment
    variables or pipeline secrets.
  - Tested on Windows agents with SqlServer PowerShell module or sqlcmd available.
#>

param(
    [Parameter(Mandatory=$true)] [string]$BackupUrl,
    [Parameter(Mandatory=$true)] [string]$TargetSqlInstance,
    [Parameter(Mandatory=$true)] [string]$TargetDatabaseName,
    [string]$TargetBackupFolder = "C:\\Temp\\sql_backups",
    [string]$MdfPath = "C:\\Program Files\\Microsoft SQL Server\\MSSQL15.MSSQLSERVER\\MSSQL\\DATA",
    [string]$LdfPath = "C:\\Program Files\\Microsoft SQL Server\\MSSQL15.MSSQLSERVER\\MSSQL\\DATA",
    [switch]$ReplaceExisting,
    [string]$SqlAuthUser,
    [string]$SqlAuthPassword,
    [string]$PostRestoreSqlPath
)

Set-StrictMode -Version Latest

function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format o
    Write-Host "[$ts] $Message"
}

Write-Log "Starting restore script"

if (-not (Test-Path $TargetBackupFolder)) { New-Item -ItemType Directory -Path $TargetBackupFolder | Out-Null }

$backupFileName = [System.IO.Path]::GetFileName($BackupUrl)
$localBackupPath = Join-Path $TargetBackupFolder $backupFileName

Write-Log "Downloading backup from $BackupUrl to $localBackupPath"
try {
    Invoke-WebRequest -Uri $BackupUrl -OutFile $localBackupPath -UseBasicParsing -ErrorAction Stop
} catch {
    Write-Log "Failed to download backup: $_"
    exit 2
}

Write-Log "Determining logical file names from backup"
$sql = @"
RESTORE FILELISTONLY FROM DISK = N'$localBackupPath'
"@

function Invoke-Sql {
    param([string]$Query)
    if ($SqlAuthUser -and $SqlAuthPassword) {
        sqlcmd -S $TargetSqlInstance -U $SqlAuthUser -P $SqlAuthPassword -Q $Query -b -r1
    } else {
        sqlcmd -S $TargetSqlInstance -Q $Query -b -r1
    }
}

$fileListOutput = Invoke-Sql -Query $sql
if ($LASTEXITCODE -ne 0) {
    Write-Log "RESTORE FILELISTONLY failed"
    exit 3
}

# Parse file list output to extract logical names and types; fallback to default names
$logicalFiles = @()
$lines = $fileListOutput -split "`n"
foreach ($line in $lines) {
    if ($line -match "^\s*LogicalName") { continue }
    $cols = $line -split "\|"
    if ($cols.Count -ge 2) {
        $logical = $cols[0].Trim()
        $physical = $cols[1].Trim()
        $logicalFiles += @{LogicalName=$logical; PhysicalName=$physical}
    }
}

if ($logicalFiles.Count -eq 0) {
    Write-Log "Could not parse logical file names; aborting"
    exit 4
}

Write-Log "Preparing MOVE clauses"
$moveClauses = @()
foreach ($f in $logicalFiles) {
    $logical = $f.LogicalName
    if ($f.PhysicalName -match '\.mdf$') {
        $dest = Join-Path $MdfPath ("$TargetDatabaseName.mdf")
    } else {
        $dest = Join-Path $LdfPath ("$TargetDatabaseName_log.ldf")
    }
    $moveClauses += "MOVE N'$logical' TO N'$dest'"
}

$replace = $ReplaceExisting.IsPresent ? "REPLACE" : ""

$restoreSql = "RESTORE DATABASE [$TargetDatabaseName] FROM DISK = N'$localBackupPath' WITH " + ($moveClauses -join ', ') + " $replace"

Write-Log "Running restore"
Invoke-Sql -Query $restoreSql
if ($LASTEXITCODE -ne 0) {
    Write-Log "RESTORE DATABASE failed"
    exit 5
}

Write-Log "Restore completed successfully"

if ($PostRestoreSqlPath -and (Test-Path $PostRestoreSqlPath)) {
    Write-Log "Executing post-restore SQL: $PostRestoreSqlPath"
    $postSql = Get-Content $PostRestoreSqlPath -Raw
    Invoke-Sql -Query $postSql
    if ($LASTEXITCODE -ne 0) { Write-Log "Post-restore SQL failed"; exit 6 }
}

Write-Log "Done"
