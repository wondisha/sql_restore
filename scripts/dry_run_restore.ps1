param(
    [Parameter(Mandatory=$true)] [string]$BackupPath,
    [Parameter(Mandatory=$true)] [string]$TargetDatabase
)

function Write-Log { param([string]$m) Write-Host "[DRYRUN] $m" }

if (-not (Test-Path $BackupPath)) { Write-Error "Backup file not found: $BackupPath"; exit 1 }

# Get logical file list using sqlcmd
$exe = (Get-Command sqlcmd -ErrorAction SilentlyContinue).Source
if (-not $exe) { Write-Error 'sqlcmd not found in PATH'; exit 1 }

$flOut = & $exe -E -b -Q "RESTORE FILELISTONLY FROM DISK = N'$BackupPath'" -s '|' -W 2>&1
if ($LASTEXITCODE -ne 0) { Write-Error "RESTORE FILELISTONLY failed: $flOut"; exit 1 }

$lines = $flOut | Where-Object { $_ -and ($_ -notmatch '^[\s-]*$') }
$parsed = @()
foreach ($line in $lines) {
    if ($line -match '^[\s-]*LogicalName') { continue }
    $parts = $line -split '\|'
    if ($parts.Length -ge 3) {
        $parsed += [pscustomobject]@{
            LogicalName = $parts[0].Trim()
            PhysicalName = $parts[1].Trim()
            Type = $parts[2].Trim()
        }
    }
}
if ($parsed.Count -eq 0) { Write-Error 'Could not parse filelist output'; exit 1 }

# Attempt to get server default data path
$serverPathOut = & $exe -E -b -h -1 -Q "SET NOCOUNT ON; SELECT SERVERPROPERTY('InstanceDefaultDataPath');" 2>&1
$serverDataPath = ($serverPathOut | Where-Object { $_ -and ($_ -notmatch '^[\s-]*$') }) -join "`n"
if (-not $serverDataPath) { $serverDataPath = 'C:\\Program Files\\Microsoft SQL Server\\MSSQL15.MSSQLSERVER\\MSSQL\\DATA' }

$moves = @()
foreach ($f in $parsed) {
    $ext = [System.IO.Path]::GetExtension($f.PhysicalName)
    if (-not $ext) { $ext = '.mdf' }
    $fname = "$TargetDatabase$ext"
    $dest = Join-Path $serverDataPath $fname
    $moves += "MOVE N'$($f.LogicalName)' TO N'$dest'"
}

$moveClause = $moves -join ', '
$restoreSql = "RESTORE DATABASE [$TargetDatabase] FROM DISK = N'$BackupPath' WITH REPLACE, $moveClause"

Write-Log "Parsed logical files:"
$parsed | Format-Table -AutoSize
Write-Log "\nGenerated RESTORE statement (DRY-RUN):"
Write-Host $restoreSql

Write-Log 'DRY RUN complete. No restore executed.'
