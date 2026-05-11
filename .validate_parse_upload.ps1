$token = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile((Get-Item .\upload_iocasta_qas.ps1).FullName, [ref]$token, [ref]$errors) | Out-Null
if ($errors -and $errors.Count -gt 0) {
  $errors | ForEach-Object { Write-Host $_.Message }
  exit 1
}
else {
  Write-Host 'PARSE OK'
}
