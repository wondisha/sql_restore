param(
    [Parameter(Mandatory=$true)] [string]$BackupPath,
    [Parameter(Mandatory=$true)] [string]$TargetDatabase
)

# Performance optimizations:
# 1. Combined SQL queries
# 2. Optimized regex parsing
# 3. Better error handling
# 4. Reduced process overhead

function Write-Log { 
    param([string]$m) 
    Write-Host "[DRYRUN] $m" 
}

# Validate inputs early
if (-not (Test-Path $BackupPath)) { 
    Write-Error "Backup file not found: $BackupPath"; 
    exit 1 
}

# Check for sqlcmd with better error handling
$exe = (Get-Command sqlcmd -ErrorAction SilentlyContinue).Source
if (-not $exe) { 
    Write-Error 'sqlcmd not found in PATH'; 
    exit 1 
}

try {
    # Combined query to get both file list and server path in one execution
    $combinedSql = @"
SET NOCOUNT ON;
DECLARE @ServerDataPath NVARCHAR(512) = ISNULL(SERVERPROPERTY('InstanceDefaultDataPath'), 'C:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\DATA');
SELECT 'SERVER_PATH' as InfoType, @ServerDataPath as Value;

-- Get file list
RESTORE FILELISTONLY FROM DISK = N'$BackupPath';
"@

    Write-Log "Executing combined query for server path and file list..."
    $combinedResult = & $exe -E -b -Q $combinedSql -s '|' -W 2>&1
    
    if ($LASTEXITCODE -ne 0) { 
        Write-Error "Combined query failed: $combinedResult"; 
        exit 1 
    }

    # Parse results more efficiently
    $lines = $combinedResult | Where-Object { $_ -and ($_ -notmatch '^[\s-]*$') }
    
    # Extract server path
    $serverDataPath = ($lines | Where-Object { $_ -match 'SERVER_PATH' } | ForEach-Object { 
        ($_ -split '\s+', 2)[1] 
    })[0]
    
    if (-not $serverDataPath) { 
        $serverDataPath = 'C:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\DATA' 
    }

    # Parse file list with optimized regex
    $parsed = @()
    $inFileList = $false
    
    foreach ($line in $lines) {
        if ($line -match '^[\s-]*LogicalName') { 
            $inFileList = $true
            continue 
        }
        
        if ($inFileList -and ($line -match '^\s*(\S+)\s+\|?\s*(\S+)\s+\|?\s*(\S+)')) {
            $parsed += [pscustomobject]@{
                LogicalName = $matches[1]
                PhysicalName = $matches[2]
                Type = $matches[3]
            }
        }
    }
    
    if ($parsed.Count -eq 0) { 
        Write-Error 'Could not parse filelist output'; 
        exit 1 
    }

    # Generate MOVE clauses more efficiently
    $moves = [System.Collections.Generic.List[string]]::new()
    
    foreach ($f in $parsed) {
        $ext = if ($f.PhysicalName -match '\.(\w+)$') { ".$($matches[1])" } else { '.mdf' }
        $fname = "$TargetDatabase$ext"
        $dest = Join-Path $serverDataPath $fname
        $moves.Add("MOVE N'$($f.LogicalName)' TO N'$dest'")
    }

    $moveClause = $moves -join ', '
    $restoreSql = "RESTORE DATABASE [$TargetDatabase] FROM DISK = N'$BackupPath' WITH REPLACE, $moveClause"

    Write-Log "Parsed logical files:"
    $parsed | Format-Table -AutoSize
    
    Write-Log "`nGenerated RESTORE statement (DRY-RUN):"
    Write-Host $restoreSql

    Write-Log 'DRY RUN complete. No restore executed.'
}
catch {
    Write-Error "Dry run failed: $_"
    exit 1
}