$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "TestSupport.ps1")
$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $repoRoot "src\Urls.ps1")

Assert-Equal (Join-UrlPath -BaseUrl "https://server/base/" -Segments @("/a/", "b")) "https://server/base/a/b" "URL deve normalizar barras"
Assert-Equal (Get-GeoNetworkRecordSharingUrl -Catalog "https://catalog" -MetadataUuid "uuid-teste") "https://catalog/srv/api/records/uuid-teste/sharing" "URL de compartilhamento deve incluir UUID"

Write-Host "URLS TESTS OK (2)"
