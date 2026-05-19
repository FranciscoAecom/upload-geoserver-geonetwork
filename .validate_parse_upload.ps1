$parseErrors = @()
$scriptPaths = @(
  (Get-Item .\upload_iocasta_qas.ps1).FullName
) + @(
  Get-ChildItem -LiteralPath .\src -Filter *.ps1 -File | Sort-Object Name | ForEach-Object { $_.FullName }
)

foreach ($scriptPath in $scriptPaths) {
  $token = $null
  $errors = $null
  [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$token, [ref]$errors) | Out-Null
  if ($errors -and $errors.Count -gt 0) {
    foreach ($errorItem in $errors) {
      $parseErrors += "$scriptPath - $($errorItem.Message)"
    }
  }
}

if ($parseErrors.Count -gt 0) {
  $parseErrors | ForEach-Object { Write-Host $_ }
  exit 1
}

Write-Host 'PARSE OK'
