param(
    [Parameter(Mandatory=$true)]
    [string]$BackupUrl,

    [Parameter(Mandatory=$true)]
    [string]$TargetDatabase,

    [Parameter(Mandatory=$false)]
    [string]$PostRestoreScript = ''
)

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $t = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$t] [$Level] $Message"
}

function Invoke-SqlCmd {
    param([string]$Sql)
    $escaped = $Sql -replace '"', '""'
    $cmd = 'sqlcmd -E -b -Q "' + $escaped + '"'
    Write-Log "Running: $cmd"
    $proc = Start-Process -FilePath pwsh -ArgumentList "-NoProfile","-Command",$cmd -Wait -PassThru -NoNewWindow
    if ($proc.ExitCode -ne 0) { throw "sqlcmd failed with exit code $($proc.ExitCode)" }
}

try {
    Write-Log "Starting restore for '$TargetDatabase' from '$BackupUrl'"

    $tmp = Join-Path $env:TEMP "restore-$(Get-Random)-$(Get-Date -Format yyyyMMddHHmmss)"
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null

    $backupFile = Join-Path $tmp (Split-Path $BackupUrl -Leaf)
    Write-Log "Downloading backup to $backupFile"
    Invoke-WebRequest -Uri $BackupUrl -OutFile $backupFile -UseBasicParsing

    # Get logical file list
    $fileListSql = "RESTORE FILELISTONLY FROM DISK = N'$backupFile'"
    $out = & sqlcmd -E -b -Q $fileListSql -s '|' -W 2>&1
    if ($LASTEXITCODE -ne 0) { throw "RESTORE FILELISTONLY failed: $out" }

    $lines = $out | Where-Object { $_ -and ($_ -notmatch '^\s*$') }

    $parsed = @()
    foreach ($line in $lines) {
        if ($line -match '^\s*LogicalName') { continue }
        $parts = $line -split '\|'
        if ($parts.Length -ge 2) {
            $parsed += [pscustomobject]@{
                LogicalName = ($parts[0].Trim())
                PhysicalName = ($parts[1].Trim())
                Type = ($parts[2].Trim())
            }
        }
    }

    if ($parsed.Count -eq 0) { throw "Could not parse RESTORE FILELISTONLY output." }

    # Attempt to get server default data path
    $serverDataPathRaw = & sqlcmd -E -b -h -1 -Q "SELECT SERVERPROPERTY('InstanceDefaultDataPath')"
    $serverDataPath = ($serverDataPathRaw | Where-Object { $_ -and ($_ -notmatch '^\s*$') }) -join "`n"
    if (-not $serverDataPath) { $serverDataPath = 'C:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\DATA' }

    $moves = @()
    foreach ($f in $parsed) {
        $ext = [System.IO.Path]::GetExtension($f.PhysicalName)
        if (-not $ext) { $ext = '.mdf' }
        $fname = "$TargetDatabase$ext"
        $dest = Join-Path $serverDataPath $fname
        $moves += "MOVE N'$($f.LogicalName)' TO N'$dest'"
    }

    $moveClause = $moves -join ', '

    $restoreSql = "RESTORE DATABASE [$TargetDatabase] FROM DISK = N'$backupFile' WITH REPLACE, $moveClause"

    Write-Log "Executing restore SQL"
    Write-Log $restoreSql
    & sqlcmd -E -b -Q $restoreSql
    if ($LASTEXITCODE -ne 0) { throw 'RESTORE DATABASE failed' }

    if ($PostRestoreScript -and (Test-Path $PostRestoreScript)) {
        Write-Log "Running post-restore script: $PostRestoreScript"
        $postSql = Get-Content -Raw -Path $PostRestoreScript
        & sqlcmd -E -b -Q $postSql
        if ($LASTEXITCODE -ne 0) { throw 'Post-restore script failed' }
    }

    Write-Log "Restore completed successfully for '$TargetDatabase'"
    Remove-Item -Recurse -Force $tmp
} catch {
    Write-Log "Error: $_" 'ERROR'
    exit 1
}
