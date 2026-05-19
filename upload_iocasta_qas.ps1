param(
  [string]$Folder = "L:\Secure_DCS\BRBLH1PINFW001\COE_Digital\coe_digital_data\silver_data\restricted\pcd\ur_car_rr\AECOM\20260514\00",
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
. (Join-Path $scriptRoot "src\GeoNetwork.ps1")
. (Join-Path $scriptRoot "src\GeoServer.ps1")
. (Join-Path $scriptRoot "src\Metadata.ps1")
. (Join-Path $scriptRoot "src\Sld.ps1")

if (-not (Test-Path -LiteralPath $Folder)) {
  throw "Pasta nao encontrada: $Folder"
}

$dataPath = Resolve-RequiredDataFile -Path $Folder
$sldPath = Resolve-RequiredFile -Path $Folder -Pattern "*.sld"
$xmlPath = Resolve-RequiredMetadataFile -Path $Folder

$derivedLayerName = [IO.Path]::GetFileNameWithoutExtension($dataPath)
if ([string]::IsNullOrWhiteSpace($Store) -and [string]::IsNullOrWhiteSpace($Layer)) {
  $Store = $derivedLayerName
  $Layer = $derivedLayerName
}
elseif ([string]::IsNullOrWhiteSpace($Store)) {
  $Store = $Layer
}
elseif ([string]::IsNullOrWhiteSpace($Layer)) {
  $Layer = $Store
}

Assert-KnownLayerNaming -LayerName $Layer

$dataExtension = [IO.Path]::GetExtension($dataPath).ToLowerInvariant()
switch ($dataExtension) {
  '.gpkg' {
    $dataType = 'gpkg'
    $dataContentType = 'application/geopackage+vnd.sqlite3'
    $dataEndpoint = 'datastores'
    $layerResource = 'featuretypes'
    $dataLabel = 'GPKG'
  }
  '.rst' {
    $dataType = 'rst'
    $dataContentType = 'application/octet-stream'
    $dataEndpoint = 'coveragestores'
    $layerResource = 'coverages'
    $dataLabel = 'RST'
  }
  '.tif' {
    $dataType = 'geotiff'
    $dataContentType = 'image/tiff'
    $dataEndpoint = 'coveragestores'
    $layerResource = 'coverages'
    $dataLabel = 'TIFF'
  }
  default {
    throw "Tipo de arquivo nao suportado: $dataExtension"
  }
}

if ([string]::IsNullOrWhiteSpace($Style)) {
  $Style = [IO.Path]::GetFileNameWithoutExtension($sldPath)
}

if ([string]::IsNullOrWhiteSpace($LayerTitle)) {
  $LayerTitle = Get-MetadataTitle -XmlPath $xmlPath
}
if ([string]::IsNullOrWhiteSpace($LayerTitle)) {
  $LayerTitle = $Layer
}
$GeoServerLayerTitle = $null
if ($Layer -match "_app_car_") {
  $GeoServerLayerTitle = Get-AppCarLayerTitle -LayerName $Layer
}
elseif ($Layer -match "_sa_car_") {
  $GeoServerLayerTitle = Get-SaCarLayerTitle -LayerName $Layer
}
elseif ($Layer -match "_ur_car_") {
  $GeoServerLayerTitle = Get-UrCarLayerTitle -LayerName $Layer
}
elseif ($Layer -match "^rst_imb_lulc_") {
  $GeoServerLayerTitle = Get-ImbLulcLayerTitle -LayerName $Layer
}
if ([string]::IsNullOrWhiteSpace($GeoServerLayerTitle)) {
  $GeoServerLayerTitle = $LayerTitle
}

Write-Host "Arquivos encontrados:"
Write-Host "  $($dataLabel): $dataPath"
Write-Host "  SLD : $sldPath"
Write-Host "  XML : $xmlPath"
Write-Host ""
Write-Host "Destino GeoServer: $GeoServer"
Write-Host "Workspace: $Workspace"
Write-Host "Store: $Store"
Write-Host "Layer: $Layer"
Write-Host "Style: $Style"
Write-Host "Titulo Catalogo: $LayerTitle"
Write-Host "Titulo GeoServer: $GeoServerLayerTitle"

$geoCredential = $null
$geoAuth = $null
$geoServerAttributeTypes = @{}

if ($SkipGeoServer) {
  Write-Host ""
  Write-Host "1-4/5 - Etapas do GeoServer ignoradas por parametro -SkipGeoServer."
}
else {
  $geoCredential = Get-Credential -Message "Credenciais do GeoServer QAS"
  $geoAuth = ConvertTo-BasicAuth -Credential $geoCredential

  if ($SkipGeoPackage) {
    Write-Host ""
    Write-Host "1/5 - Upload de dados ignorado por parametro -SkipGeoPackage."
  }
  else {
    Write-Host ""
    Write-Host "1/5 - Publicando $dataLabel no GeoServer..."
    Invoke-Curl -Arguments @(
      "--fail-with-body",
      "--show-error",
      "--location",
      "--retry", "3",
      "--retry-delay", "10",
      "--connect-timeout", "60",
      "--max-time", "0",
      "--request", "PUT",
      "--header", "Authorization: Basic $geoAuth",
      "--header", "Content-Type: $dataContentType",
      "--upload-file", $dataPath,
      "$GeoServer/rest/workspaces/$Workspace/$dataEndpoint/$Store/file.${dataType}?configure=all"
    )
  }

  Write-Host ""
  Write-Host "2/5 - Ajustando titulo da camada..."
  $escapedLayerTitle = ConvertTo-XmlMarkupEscapedText -Text $GeoServerLayerTitle

  if ($layerResource -eq 'featuretypes') {
    $resourceBody = @"
<?xml version="1.0" encoding="UTF-8"?>
<featureType>
  <title>$escapedLayerTitle</title>
</featureType>
"@
  }
  else {
    $resourceBody = @"
<?xml version="1.0" encoding="UTF-8"?>
<coverage>
  <title>$escapedLayerTitle</title>
</coverage>
"@
  }

  $tmpFeatureTypeBody = New-TemporaryFile
  try {
    $utf8NoBom = New-Object Text.UTF8Encoding $false
    [IO.File]::WriteAllText($tmpFeatureTypeBody.FullName, $resourceBody, $utf8NoBom)
    try {
      Invoke-Curl -Arguments @(
        "--fail-with-body",
        "--show-error",
        "--location",
        "--retry", "3",
        "--retry-delay", "5",
        "--connect-timeout", "60",
        "--max-time", "0",
        "--request", "PUT",
        "--header", "Authorization: Basic $geoAuth",
        "--header", "Content-Type: application/xml; charset=UTF-8",
        "--data-binary", "@$($tmpFeatureTypeBody.FullName)",
        "$GeoServer/rest/workspaces/$Workspace/$dataEndpoint/$Store/$layerResource/$Layer"
      )
    }
    catch {
      Write-Warning "Nao foi possivel ajustar o titulo automaticamente. O script vai continuar. Detalhe: $($_.Exception.Message)"
    }
  }
  finally {
    Remove-Item -LiteralPath $tmpFeatureTypeBody.FullName -Force -ErrorAction SilentlyContinue
  }

  Write-Host ""
  Write-Host "3/5 - Criando estilo SLD no GeoServer..."
  $sldUploadPath = New-SldWithStyleName -SldPath $sldPath -StyleName $Style -LayerName $Layer
  try {
    Invoke-Curl -Arguments @(
      "--fail-with-body",
      "--show-error",
      "--location",
      "--retry", "3",
      "--retry-delay", "5",
      "--connect-timeout", "60",
      "--max-time", "0",
      "--request", "POST",
      "--header", "Authorization: Basic $geoAuth",
      "--header", "Content-Type: application/vnd.ogc.sld+xml",
      "--data-binary", "@$sldUploadPath",
      "$GeoServer/rest/workspaces/$Workspace/styles?name=${Style}&raw=true"
    )
  }
  catch {
    Write-Warning "Nao foi possivel criar o estilo; tentando atualizar estilo existente. Detalhe: $($_.Exception.Message)"
    Invoke-Curl -Arguments @(
      "--fail-with-body",
      "--show-error",
      "--location",
      "--retry", "3",
      "--retry-delay", "5",
      "--connect-timeout", "60",
      "--max-time", "0",
      "--request", "PUT",
      "--header", "Authorization: Basic $geoAuth",
      "--header", "Content-Type: application/vnd.ogc.sld+xml",
      "--data-binary", "@$sldUploadPath",
      "$GeoServer/rest/workspaces/$Workspace/styles/${Style}?raw=true"
    )
  }
  finally {
    Remove-Item -LiteralPath $sldUploadPath -Force -ErrorAction SilentlyContinue
  }

  Write-Host ""
  Write-Host "4/5 - Associando estilo a camada..."
  $layerBody = @"
{
  "layer": {
    "defaultStyle": {
      "name": "$Style",
      "workspace": "$Workspace"
    }
  }
}
"@
  $tmpBody = New-TemporaryFile
  try {
    Set-Content -LiteralPath $tmpBody.FullName -Value $layerBody -Encoding ASCII
    Invoke-Curl -Arguments @(
      "--fail-with-body",
      "--show-error",
      "--location",
      "--retry", "3",
      "--retry-delay", "5",
      "--connect-timeout", "60",
      "--max-time", "0",
      "--request", "PUT",
      "--header", "Authorization: Basic $geoAuth",
      "--header", "Content-Type: application/json",
      "--data-binary", "@$($tmpBody.FullName)",
      "$GeoServer/rest/layers/$Workspace`:$Layer"
    )
  }
  finally {
    Remove-Item -LiteralPath $tmpBody.FullName -Force -ErrorAction SilentlyContinue
  }

  if ($layerResource -eq 'featuretypes') {
    Write-Host ""
    Write-Host "Coletando tipos dos atributos publicados no GeoServer..."
    $geoServerAttributeTypes = Get-GeoServerAttributeTypes -GeoServer $GeoServer -Workspace $Workspace -Store $Store -Layer $Layer -GeoAuth $geoAuth
    if ($geoServerAttributeTypes.Count -gt 0) {
      Write-Host "Tipos coletados: $($geoServerAttributeTypes.Count)"
    }
  }
}

if ($SkipCatalog) {
  Write-Host ""
  Write-Host "5/5 - Catalogo ignorado por parametro -SkipCatalog."
}
else {
  Write-Host ""
  Write-Host "5/5 - Importando XML no catalogo GeoNetwork..."
  Write-Host "Abrindo sessao e capturando token XSRF do GeoNetwork..."
  $metadataUploadPath = New-MetadataXmlWithDataDictionaryLink -XmlPath $xmlPath -DataDictionaryBaseUrl $DataDictionaryBaseUrl -AttributeTypes $geoServerAttributeTypes
  if ($SameCredentialForCatalog) {
    if ($null -eq $geoCredential) {
      $catalogCredential = Get-Credential -Message "Credenciais do Catalogo QAS / GeoNetwork"
    }
    else {
      $catalogCredential = $geoCredential
    }
  }
  else {
    $catalogCredential = Get-Credential -Message "Credenciais do Catalogo QAS / GeoNetwork"
  }
  $catalogAuth = ConvertTo-BasicAuth -Credential $catalogCredential
  $cookieJar = New-TemporaryFile

  Invoke-Curl -Arguments @(
    "--fail-with-body",
    "--show-error",
    "--location",
    "--connect-timeout", "60",
    "--max-time", "0",
    "--cookie-jar", $cookieJar.FullName,
    "--cookie", $cookieJar.FullName,
    "--header", "Authorization: Basic $catalogAuth",
    "--header", "Accept: application/json",
    "$Catalog/srv/api/me"
  )

  $xsrfToken = Get-CookieValue -CookieJar $cookieJar.FullName -CookieName "XSRF-TOKEN"
  if ([string]::IsNullOrWhiteSpace($xsrfToken)) {
    throw "Nao foi possivel obter XSRF-TOKEN do GeoNetwork em $Catalog/srv/api/me."
  }

  $recordsImportQuery = @(
    "metadataType=METADATA",
    "uuidProcessing=OVERWRITE",
    "group=$CatalogGroup",
    "category=$CatalogCategory",
    "rejectIfInvalid=false",
    "publishToAll=true",
    "transformWith=_none_",
    "schema=iso19139",
    "allowEditGroupMembers=true"
  ) -join "&"
  $recordsImportUrls = @(
    "$Catalog/srv/api/records?$recordsImportQuery",
    "$Catalog/srv/api/records/?$recordsImportQuery",
    "$Catalog/srv/por/api/records?$recordsImportQuery",
    "$Catalog/srv/por/api/records/?$recordsImportQuery"
  )

  try {
    $modernSuccess = $false
    $modernErrors = @()
    foreach ($recordsImportUrl in $recordsImportUrls) {
      if ($modernSuccess) {
        continue
      }

      Write-Host ""
      Write-Host "Tentando importacao moderna em $recordsImportUrl"
      try {
        $modernOutput = Invoke-CurlCapture -Arguments @(
          "--fail-with-body",
          "--show-error",
          "--location",
          "--retry", "0",
          "--connect-timeout", "60",
          "--max-time", "0",
          "--request", "POST",
          "--cookie-jar", $cookieJar.FullName,
          "--cookie", $cookieJar.FullName,
          "--header", "Authorization: Basic $catalogAuth",
          "--header", "X-XSRF-TOKEN: $xsrfToken",
          "--header", "Accept: application/json",
          "--form", "file=@$metadataUploadPath;type=application/xml",
          $recordsImportUrl
        )
        Assert-GeoNetworkModernImportSucceeded -Output $modernOutput
        $modernSuccess = $true
      }
      catch {
        $modernErrors += "$recordsImportUrl -> $($_.Exception.Message)"
        Write-Warning "Falhou em $recordsImportUrl"
      }
    }

    if (-not $modernSuccess) {
      throw "Tentativas modernas falharam: $($modernErrors -join ' | ')"
    }
  }
  catch {
    Write-Warning "Importacao pela API moderna falhou; tentando endpoints legados. Detalhe: $($_.Exception.Message)"
    $legacyEndpoints = @(
      "$Catalog/srv/por/metadata.insert",
      "$Catalog/srv/por/xml.metadata.insert",
      "$Catalog/srv/api/0.1/records"
    )

    $legacySuccess = $false
    $legacyErrors = @()
    foreach ($legacyEndpoint in $legacyEndpoints) {
      if ($legacySuccess) {
        continue
      }

      Write-Host ""
      Write-Host "Tentando importacao legada em $legacyEndpoint"
      try {
        Invoke-Curl -Arguments @(
          "--fail-with-body",
          "--show-error",
          "--retry", "0",
          "--connect-timeout", "60",
          "--max-time", "0",
          "--request", "POST",
          "--cookie-jar", $cookieJar.FullName,
          "--cookie", $cookieJar.FullName,
          "--header", "Authorization: Basic $catalogAuth",
          "--header", "X-XSRF-TOKEN: $xsrfToken",
          "--form", "data=<$metadataUploadPath",
          "--form", "group=$CatalogGroup",
          "--form", "category=$CatalogCategory",
          "--form", "styleSheet=_none_",
          "--form", "uuidAction=overwrite",
          "--form", "isTemplate=n",
          "--form", "validate=off",
          $legacyEndpoint
        )
        $legacySuccess = $true
      }
      catch {
        $legacyErrors += "$legacyEndpoint -> $($_.Exception.Message)"
        Write-Warning "Falhou em $legacyEndpoint"
      }
    }

    if (-not $legacySuccess) {
      throw "Nao foi possivel importar no GeoNetwork. Tentativas: $($legacyErrors -join ' | ')"
    }
  }
  finally {
    Remove-Item -LiteralPath $cookieJar.FullName -Force -ErrorAction SilentlyContinue
    if ($metadataUploadPath -ne $xmlPath) {
      Remove-Item -LiteralPath $metadataUploadPath -Force -ErrorAction SilentlyContinue
    }
  }
}

Write-Host ""
Write-Host "Concluido."
Write-Host "GeoServer layer:"
Write-Host "  $GeoServer/rest/layers/$Workspace`:$Layer.json"
Write-Host "Map Preview:"
Write-Host "  $GeoServer/web/wicket/bookmarkable/org.geoserver.web.demo.MapPreviewPage"
