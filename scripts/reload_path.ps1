# Reload machine + user PATH into the current PowerShell session and check for sqlcmd
$m = [System.Environment]::GetEnvironmentVariable('Path','Machine')
$u = [System.Environment]::GetEnvironmentVariable('Path','User')
if ($m -eq $null) { $m = '' }
if ($u -eq $null) { $u = '' }
$new = $m
if ($u -ne '') { if ($new -ne '') { $new = $new + ';' + $u } else { $new = $u } }
$env:Path = $new.TrimEnd(';')
Write-Output "Reloaded PATH length: $($env:Path.Length)"
if (Get-Command sqlcmd -ErrorAction SilentlyContinue) {
    Write-Output "sqlcmd found at: $((Get-Command sqlcmd).Path)"
} else {
    Write-Output 'sqlcmd not found in PATH'
    Write-Output 'where.exe results:'
    & where.exe sqlcmd 2>&1 | ForEach-Object { Write-Output " - $_" }
}
Write-Output "Done. To persist changes in new shells, reopen your terminal."