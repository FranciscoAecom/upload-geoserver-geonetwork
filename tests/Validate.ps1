$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot
try {
  & .\.validate_parse_upload.ps1

  & .\tests\Run-UnitTests.ps1

  & git diff --check
  if ($LASTEXITCODE -ne 0) {
    throw "git diff --check encontrou problemas."
  }

  Write-Host ""
  Write-Host "VALIDATION OK"
}
finally {
  Pop-Location
}
