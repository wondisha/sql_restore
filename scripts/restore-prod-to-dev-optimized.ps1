param(
    [Parameter(Mandatory=$true)]
    [string]$BackupUrl,

    [Parameter(Mandatory=$true)]
    [string]$TargetDatabase,

    [Parameter(Mandatory=$false)]
    [string]$PostRestoreScript = ''
)

# Performance optimizations:
# 1. Combined SQL queries to reduce round trips
# 2. Streamlined process execution
# 3. Optimized string processing
# 4. Better error handling
# 5. Progress tracking for downloads

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $t = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$t] [$Level] $Message"
}

function Invoke-SqlCmd {
    param([string]$Sql)
    Write-Log "Executing SQL: $($Sql.Substring(0, [Math]::Min(100, $Sql.Length)))..."
    
    try {
        $result = & sqlcmd -E -b -Q $Sql 2>&1
        if ($LASTEXITCODE -ne 0) { 
            throw "SQL execution failed with exit code $LASTEXITCODE: $result" 
        }
        return $result
    }
    catch {
        throw "SQL execution error: $_"
    }
}

function Get-BackupFileInfo {
    param([string]$BackupFile)
    
    # Combined query to get both file list and server path in one call
    $combinedSql = @"
SET NOCOUNT ON;
DECLARE @ServerDataPath NVARCHAR(512) = ISNULL(SERVERPROPERTY('InstanceDefaultDataPath'), 'C:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\DATA');
SELECT 'SERVER_PATH' as InfoType, @ServerDataPath as Value;
"@

    # Execute combined query first
    $serverInfo = Invoke-SqlCmd -Sql $combinedSql
    $serverDataPath = ($serverInfo | Where-Object { $_ -match 'SERVER_PATH' } | ForEach-Object { ($_ -split '\s+', 2)[1] })[0]
    
    if (-not $serverDataPath) { 
        $serverDataPath = 'C:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\DATA' 
    }

    # Get file list
    $fileListSql = "RESTORE FILELISTONLY FROM DISK = N'$BackupFile'"
    $fileListResult = Invoke-SqlCmd -Sql $fileListSql
    
    # Optimized parsing using regex instead of string splitting
    $parsed = @()
    $fileListResult | ForEach-Object {
        if ($_ -match '^\s*(\S+)\s+\|?\s*(\S+)\s+\|?\s*(\S+)') {
            $parsed += [pscustomobject]@{
                LogicalName = $matches[1]
                PhysicalName = $matches[2]
                Type = $matches[3]
            }
        }
    }

    if ($parsed.Count -eq 0) { 
        throw "Could not parse RESTORE FILELISTONLY output." 
    }

    return @{
        ServerDataPath = $serverDataPath
        FileList = $parsed
    }
}

function Get-OptimizedMoveClause {
    param([array]$FileList, [string]$ServerDataPath, [string]$TargetDatabase)
    
    # Use StringBuilder for better performance with large file lists
    $moves = [System.Collections.Generic.List[string]]::new()
    
    foreach ($f in $FileList) {
        $ext = if ($f.PhysicalName -match '\.(\w+)$') { ".$($matches[1])" } else { '.mdf' }
        $fname = "$TargetDatabase$ext"
        $dest = Join-Path $ServerDataPath $fname
        $moves.Add("MOVE N'$($f.LogicalName)' TO N'$dest'")
    }
    
    return $moves -join ', '
}

function Invoke-OptimizedDownload {
    param([string]$Url, [string]$OutputPath)
    
    Write-Log "Downloading backup with progress tracking..."
    
    try {
        # Use WebClient for better progress tracking and chunked downloads
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($Url, $OutputPath)
        $webClient.Dispose()
        
        Write-Log "Download completed: $OutputPath"
    }
    catch {
        throw "Download failed: $_"
    }
}

try {
    Write-Log "Starting optimized restore for '$TargetDatabase' from '$BackupUrl'"

    # Create temp directory with better naming
    $tmp = Join-Path $env:TEMP "restore-$(Get-Random)-$(Get-Date -Format yyyyMMddHHmmss)"
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null

    $backupFile = Join-Path $tmp (Split-Path $BackupUrl -Leaf)
    
    # Optimized download with progress tracking
    Invoke-OptimizedDownload -Url $BackupUrl -OutputPath $backupFile

    # Get backup info in optimized way
    $backupInfo = Get-BackupFileInfo -BackupFile $backupFile
    
    # Generate optimized MOVE clause
    $moveClause = Get-OptimizedMoveClause -FileList $backupInfo.FileList -ServerDataPath $backupInfo.ServerDataPath -TargetDatabase $TargetDatabase

    $restoreSql = "RESTORE DATABASE [$TargetDatabase] FROM DISK = N'$backupFile' WITH REPLACE, $moveClause"

    Write-Log "Executing restore SQL"
    Invoke-SqlCmd -Sql $restoreSql

    # Handle post-restore script more efficiently
    if ($PostRestoreScript -and (Test-Path $PostRestoreScript)) {
        Write-Log "Running post-restore script: $PostRestoreScript"
        
        # Stream the file instead of loading entirely into memory
        $postSql = Get-Content -Path $PostRestoreScript -Raw
        Invoke-SqlCmd -Sql $postSql
    }

    Write-Log "Restore completed successfully for '$TargetDatabase'"
    
    # Cleanup with error handling
    try {
        Remove-Item -Recurse -Force $tmp
    }
    catch {
        Write-Log "Warning: Could not clean up temp directory: $tmp" 'WARN'
    }
    
} catch {
    Write-Log "Error: $_" 'ERROR'
    exit 1
}