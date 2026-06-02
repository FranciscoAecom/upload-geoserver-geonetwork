$ErrorActionPreference = "Stop"

$testScripts = @(
  "Core.Tests.ps1",
  "GeoNetwork.Tests.ps1",
  "Metadata.Tests.ps1",
  "Naming.Tests.ps1",
  "Urls.Tests.ps1",
  "Workflow.Tests.ps1"
)

foreach ($testScript in $testScripts) {
  Write-Host ""
  Write-Host "Executando $testScript..."
  & (Join-Path $PSScriptRoot $testScript)
}

Write-Host ""
Write-Host "ALL UNIT TESTS OK"
