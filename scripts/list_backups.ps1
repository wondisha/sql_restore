# List .bak files in D:\backup, newest first
$path = 'D:\backup'
if (-not (Test-Path $path)) {
    Write-Output "Backup path not found: $path"
    exit 0
}
$files = Get-ChildItem -Path $path -Filter '*.bak' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
if (-not $files) {
    Write-Output "No .bak files found in $path"
    exit 0
}
$files | Select-Object Name,FullName,@{Name='SizeMB';Expression={ [math]::Round($_.Length/1MB,2)}},LastWriteTime | Format-Table -AutoSize
# Output the full path of the newest file for downstream use
Write-Output "NEWEST::" + $files[0].FullName
