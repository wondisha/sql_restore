param(
    [string]$BakPath = 'D:\backup\advent.bak'
)

$exe = 'C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\SQLCMD.EXE'
if (-not (Test-Path $exe)) {
    $cmd = Get-Command sqlcmd -ErrorAction SilentlyContinue
    if ($cmd) { $exe = $cmd.Source } else { Write-Error "sqlcmd not found"; exit 1 }
}

$arguments = @(
    '-E',
    '-b',
    '-Q',
    "RESTORE FILELISTONLY FROM DISK='$BakPath'",
    '-s','|','-W'
)

Write-Output "Running: $exe $($arguments -join ' ')"
& $exe @arguments
