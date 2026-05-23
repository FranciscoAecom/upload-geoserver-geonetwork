param(
  [string]$Folder = "C:\Users\RibeiroF\Downloads\Nova pasta",
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
  [switch]$SkipCatalog,
  [switch]$SkipCertificateRevocationCheck,
  [switch]$DryRun,
  [string]$Environment = "qas",
  [string]$ConfigPath
)

$ErrorActionPreference = "Stop"
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptRoot "src\Core.ps1")
. (Join-Path $scriptRoot "src\Config.ps1")
. (Join-Path $scriptRoot "src\Naming.ps1")
. (Join-Path $scriptRoot "src\Metadata.ps1")
. (Join-Path $scriptRoot "src\PublishContext.ps1")
. (Join-Path $scriptRoot "src\Sld.ps1")
. (Join-Path $scriptRoot "src\Urls.ps1")
. (Join-Path $scriptRoot "src\GeoNetwork.ps1")
. (Join-Path $scriptRoot "src\GeoServer.ps1")

$script:SkipCurlCertificateRevocationCheck = $SkipCertificateRevocationCheck.IsPresent

$config = Import-PublishConfig -ScriptRoot $scriptRoot -Environment $Environment -ConfigPath $ConfigPath
$GeoServer = Get-ConfigValue -Config $config -BoundParameters $PSBoundParameters -Name "GeoServer" -CurrentValue $GeoServer
$Catalog = Get-ConfigValue -Config $config -BoundParameters $PSBoundParameters -Name "Catalog" -CurrentValue $Catalog
$Workspace = Get-ConfigValue -Config $config -BoundParameters $PSBoundParameters -Name "Workspace" -CurrentValue $Workspace
$CatalogGroup = Get-ConfigValue -Config $config -BoundParameters $PSBoundParameters -Name "CatalogGroup" -CurrentValue $CatalogGroup
$CatalogCategory = Get-ConfigValue -Config $config -BoundParameters $PSBoundParameters -Name "CatalogCategory" -CurrentValue $CatalogCategory
$DataDictionaryBaseUrl = Get-ConfigValue -Config $config -BoundParameters $PSBoundParameters -Name "DataDictionaryBaseUrl" -CurrentValue $DataDictionaryBaseUrl

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
Write-Host "Config: $($config.Path)"
Write-Host "Ambiente: $Environment"
Write-Host "Destino GeoServer: $GeoServer"
Write-Host "Workspace: $Workspace"
Write-Host "Store: $($publishContext.Store)"
Write-Host "Layer: $($publishContext.Layer)"
Write-Host "Style: $($publishContext.Style)"
Write-Host "Titulo Catalogo: $($publishContext.LayerTitle)"
Write-Host "Titulo GeoServer: $($publishContext.GeoServerLayerTitle)"
if ($DryRun) {
  Write-Host "Modo: DRY-RUN (nenhum curl sera executado)"
}
if ($SkipCertificateRevocationCheck) {
  Write-Host "TLS: verificacao de revogacao de certificado desativada para curl.exe (--ssl-no-revoke)"
}

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
    -SkipGeoPackage $SkipGeoPackage.IsPresent `
    -DryRun $DryRun.IsPresent

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
    -SameCredentialForCatalog $SameCredentialForCatalog.IsPresent `
    -DryRun $DryRun.IsPresent
}

Write-Host ""
Write-Host "Concluido."
Write-Host "GeoServer layer:"
Write-Host "  $(Get-GeoServerLayerJsonUrl -GeoServer $GeoServer -Workspace $Workspace -Layer $publishContext.Layer)"
Write-Host "Map Preview:"
Write-Host "  $(Get-GeoServerMapPreviewUrl -GeoServer $GeoServer)"
