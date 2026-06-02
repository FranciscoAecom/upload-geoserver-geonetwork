$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "TestSupport.ps1")
$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $repoRoot "src\Core.ps1")
. (Join-Path $repoRoot "src\Urls.ps1")
. (Join-Path $repoRoot "src\GeoNetwork.ps1")

$session = New-GeoNetworkSession -Catalog "https://catalog" -DryRun $true
try {
  Assert-Equal $session.Auth "DRYRUN" "Sessao simulada deve usar auth neutra"
  Assert-Equal $session.XsrfToken "DRYRUN-XSRF-TOKEN" "Sessao simulada deve fornecer token"
  Assert-True (Test-Path -LiteralPath $session.CookieJar) "Sessao deve criar cookie jar temporario"
}
finally {
  Remove-GeoNetworkSession -Session $session
}
Assert-True (-not (Test-Path -LiteralPath $session.CookieJar)) "Remocao da sessao deve limpar cookie jar"

Write-Host "GEONETWORK TESTS OK (4)"
