param(
  [string]$Folder = "L:\Secure_DCS\BRBLH1PINFW001\COE_Digital\coe_digital_data\silver_data\restricted\imb\uso_do_solo_2022\MapBiomas\20250815\00",
  [string]$GeoServer = "https://gisqas.iocasta.com.br/geoserver",
  [string]$Catalog = "https://catalogqas.iocasta.com.br",
  [string]$Workspace = "gold",
  [string]$Store,
  [string]$Layer,
  [string]$LayerTitle,
  [string]$Style,
  [string]$CatalogGroup = "2",
  [string]$CatalogCategory = "2",
  [string]$DataDictionaryBaseUrl = "https://etlapiqas.iocasta.com.br/get_geonetwork_data_dict",
  [switch]$SameCredentialForCatalog,
  [switch]$SkipGeoServer,
  [switch]$SkipGeoPackage,
  [switch]$SkipCatalog
)

$ErrorActionPreference = "Stop"
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptRoot "src\Core.ps1")
. (Join-Path $scriptRoot "src\Naming.ps1")
. (Join-Path $scriptRoot "src\Metadata.ps1")
. (Join-Path $scriptRoot "src\PublishContext.ps1")
. (Join-Path $scriptRoot "src\Sld.ps1")
. (Join-Path $scriptRoot "src\GeoNetwork.ps1")
. (Join-Path $scriptRoot "src\GeoServer.ps1")

if (-not (Test-Path -LiteralPath $Folder)) {
  throw "Pasta nao encontrada: $Folder"
}

$dataPath = Resolve-RequiredDataFile -Path $Folder
$sldPath = Resolve-RequiredFile -Path $Folder -Pattern "*.sld"
$xmlPath = Resolve-RequiredMetadataFile -Path $Folder

$publishContext = New-PublishContext -DataPath $dataPath -SldPath $sldPath -XmlPath $xmlPath -Store $Store -Layer $Layer -LayerTitle $LayerTitle -Style $Style

Write-Host "Arquivos encontrados:"
Write-Host "  $($publishContext.DataLabel): $($publishContext.DataPath)"
Write-Host "  SLD : $($publishContext.SldPath)"
Write-Host "  XML : $($publishContext.XmlPath)"
Write-Host ""
Write-Host "Destino GeoServer: $GeoServer"
Write-Host "Workspace: $Workspace"
Write-Host "Store: $($publishContext.Store)"
Write-Host "Layer: $($publishContext.Layer)"
Write-Host "Style: $($publishContext.Style)"
Write-Host "Titulo Catalogo: $($publishContext.LayerTitle)"
Write-Host "Titulo GeoServer: $($publishContext.GeoServerLayerTitle)"

$geoCredential = $null
$geoServerAttributeTypes = @{}

if ($SkipGeoServer) {
  Write-Host ""
  Write-Host "1-4/5 - Etapas do GeoServer ignoradas por parametro -SkipGeoServer."
}
else {
  $geoServerPublishResult = Invoke-GeoServerPublish `
    -GeoServer $GeoServer `
    -Workspace $Workspace `
    -PublishContext $publishContext `
    -SkipGeoPackage $SkipGeoPackage.IsPresent

  $geoCredential = $geoServerPublishResult.Credential
  $geoServerAttributeTypes = $geoServerPublishResult.AttributeTypes
}

if ($SkipCatalog) {
  Write-Host ""
  Write-Host "5/5 - Catalogo ignorado por parametro -SkipCatalog."
}
else {
  Import-GeoNetworkMetadata `
    -Catalog $Catalog `
    -XmlPath $publishContext.XmlPath `
    -DataDictionaryBaseUrl $DataDictionaryBaseUrl `
    -AttributeTypes $geoServerAttributeTypes `
    -CatalogGroup $CatalogGroup `
    -CatalogCategory $CatalogCategory `
    -GeoCredential $geoCredential `
    -SameCredentialForCatalog $SameCredentialForCatalog.IsPresent
}

Write-Host ""
Write-Host "Concluido."
Write-Host "GeoServer layer:"
Write-Host "  $GeoServer/rest/layers/$Workspace`:$($publishContext.Layer).json"
Write-Host "Map Preview:"
Write-Host "  $GeoServer/web/wicket/bookmarkable/org.geoserver.web.demo.MapPreviewPage"
