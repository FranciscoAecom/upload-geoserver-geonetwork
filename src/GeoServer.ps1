$ErrorActionPreference = "Stop"

function ConvertFrom-GeoServerBinding {
  param([string]$Binding)

  switch -Regex ($Binding) {
    "String$" { return "String" }
    "(Long|Integer|Short|BigInteger)$" { return "Integer64" }
    "(Double|Float|BigDecimal)$" { return "Real" }
    "(Boolean)$" { return "Boolean" }
    "(Date|Timestamp|Time)$" { return "Date" }
    default { return $null }
  }
}

function Get-GeoServerAttributeTypes {
  param(
    [string]$GeoServer,
    [string]$Workspace,
    [string]$Store,
    [string]$Layer,
    [string]$GeoAuth
  )

  $attributeTypes = @{}
  $featureTypeUrl = Get-GeoServerFeatureTypeUrl -GeoServer $GeoServer -Workspace $Workspace -Store $Store -Layer $Layer

  try {
    $featureTypeJson = Invoke-CurlCapture -Arguments @(
      "--fail-with-body",
      "--show-error",
      "--location",
      "--retry", "3",
      "--retry-delay", "5",
      "--connect-timeout", "60",
      "--max-time", "0",
      "--header", "Authorization: Basic $GeoAuth",
      "--header", "Accept: application/json",
      $featureTypeUrl
    )
    $featureType = $featureTypeJson | ConvertFrom-Json
    $attributes = @($featureType.featureType.attributes.attribute)
    foreach ($attribute in $attributes) {
      if ([string]::IsNullOrWhiteSpace($attribute.name) -or $attribute.name -eq "geom") {
        continue
      }

      $type = ConvertFrom-GeoServerBinding -Binding $attribute.binding
      if (-not [string]::IsNullOrWhiteSpace($type)) {
        $attributeTypes[$attribute.name] = $type
      }
    }
  }
  catch {
    Write-Warning "Nao foi possivel ler os tipos no GeoServer em $featureTypeUrl. Detalhe: $($_.Exception.Message)"
  }

  if (-not $attributeTypes.ContainsKey("fid")) {
    $attributeTypes["fid"] = "Integer64"
  }

  return $attributeTypes
}

function Publish-GeoServerData {
  param(
    [string]$GeoServer,
    [string]$Workspace,
    [string]$Store,
    [string]$DataEndpoint,
    [string]$DataType,
    [string]$DataContentType,
    [string]$DataPath,
    [string]$DataLabel,
    [string]$GeoAuth,
    [bool]$DryRun = $false
  )

  Write-Host ""
  Write-Host "1/5 - Publicando $DataLabel no GeoServer..."
  Invoke-Curl -Arguments @(
    "--fail-with-body",
    "--show-error",
    "--location",
    "--retry", "3",
    "--retry-delay", "10",
    "--connect-timeout", "60",
    "--max-time", "0",
    "--request", "PUT",
    "--header", "Authorization: Basic $GeoAuth",
    "--header", "Content-Type: $DataContentType",
    "--upload-file", $DataPath,
    (Get-GeoServerDataUploadUrl -GeoServer $GeoServer -Workspace $Workspace -DataEndpoint $DataEndpoint -Store $Store -DataType $DataType)
  ) -DryRun $DryRun
}

function Test-GeoServerCredential {
  param(
    [string]$GeoServer,
    [string]$GeoAuth,
    [bool]$DryRun = $false
  )

  Write-Host ""
  Write-Host "Validando credenciais do GeoServer..."
  try {
    [void](Invoke-CurlCapture -Arguments @(
      "--fail-with-body",
      "--show-error",
      "--location",
      "--retry", "1",
      "--retry-delay", "2",
      "--connect-timeout", "30",
      "--max-time", "60",
      "--header", "Authorization: Basic $GeoAuth",
      "--header", "Accept: application/json",
      (Get-GeoServerVersionUrl -GeoServer $GeoServer)
    ) -DryRun $DryRun)
  }
  catch {
    throw "GeoServer recusou as credenciais ou o usuario nao tem permissao REST em $(Get-GeoServerVersionUrl -GeoServer $GeoServer). Detalhe: $($_.Exception.Message)"
  }
}

function Set-GeoServerLayerTitle {
  param(
    [string]$GeoServer,
    [string]$Workspace,
    [string]$Store,
    [string]$Layer,
    [string]$DataEndpoint,
    [string]$LayerResource,
    [string]$LayerTitle,
    [string]$GeoAuth,
    [bool]$DryRun = $false
  )

  Write-Host ""
  Write-Host "2/5 - Ajustando titulo da camada..."
  $escapedLayerTitle = ConvertTo-XmlMarkupEscapedText -Text $LayerTitle

  if ($LayerResource -eq 'featuretypes') {
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
        "--header", "Authorization: Basic $GeoAuth",
        "--header", "Content-Type: application/xml; charset=UTF-8",
        "--data-binary", "@$($tmpFeatureTypeBody.FullName)",
        (Get-GeoServerLayerResourceUrl -GeoServer $GeoServer -Workspace $Workspace -DataEndpoint $DataEndpoint -Store $Store -LayerResource $LayerResource -Layer $Layer)
      ) -DryRun $DryRun
    }
    catch {
      Write-Warning "Nao foi possivel ajustar o titulo automaticamente. O script vai continuar. Detalhe: $($_.Exception.Message)"
    }
  }
  finally {
    Remove-Item -LiteralPath $tmpFeatureTypeBody.FullName -Force -ErrorAction SilentlyContinue
  }
}

function Publish-GeoServerStyle {
  param(
    [string]$GeoServer,
    [string]$Workspace,
    [string]$Style,
    [string]$Layer,
    [string]$SldPath,
    [string]$GeoAuth,
    [bool]$DryRun = $false
  )

  Write-Host ""
  Write-Host "3/5 - Criando estilo SLD no GeoServer..."
  $sldUploadPath = New-SldWithStyleName -SldPath $SldPath -StyleName $Style -LayerName $Layer
  $sldContentType = Get-SldContentType -SldPath $SldPath
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
      "--header", "Authorization: Basic $GeoAuth",
      "--header", "Content-Type: $sldContentType",
      "--data-binary", "@$sldUploadPath",
      (Get-GeoServerStyleCollectionUrl -GeoServer $GeoServer -Workspace $Workspace -Style $Style)
    ) -DryRun $DryRun
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
      "--header", "Authorization: Basic $GeoAuth",
      "--header", "Content-Type: $sldContentType",
      "--data-binary", "@$sldUploadPath",
      (Get-GeoServerStyleUrl -GeoServer $GeoServer -Workspace $Workspace -Style $Style)
    ) -DryRun $DryRun
  }
  finally {
    Remove-Item -LiteralPath $sldUploadPath -Force -ErrorAction SilentlyContinue
  }
}

function Set-GeoServerDefaultStyle {
  param(
    [string]$GeoServer,
    [string]$Workspace,
    [string]$Layer,
    [string]$Style,
    [string]$GeoAuth,
    [bool]$DryRun = $false
  )

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
      "--header", "Authorization: Basic $GeoAuth",
      "--header", "Content-Type: application/json",
      "--data-binary", "@$($tmpBody.FullName)",
      (Get-GeoServerLayerUrl -GeoServer $GeoServer -Workspace $Workspace -Layer $Layer)
    ) -DryRun $DryRun
  }
  finally {
    Remove-Item -LiteralPath $tmpBody.FullName -Force -ErrorAction SilentlyContinue
  }
}

function Invoke-GeoServerPublish {
  param(
    [string]$GeoServer,
    [string]$Workspace,
    [pscustomobject]$PublishContext,
    [bool]$SkipGeoPackage,
    [bool]$DryRun = $false
  )

  $geoCredential = $null
  $geoAuth = "DRYRUN"
  if ($DryRun) {
    Write-Host ""
    Write-Host "DRY-RUN: credenciais do GeoServer nao solicitadas."
  }
  else {
    $geoCredential = Get-Credential -Message "Credenciais do GeoServer QAS"
    $geoAuth = ConvertTo-BasicAuth -Credential $geoCredential
  }

  Test-GeoServerCredential -GeoServer $GeoServer -GeoAuth $geoAuth -DryRun $DryRun

  if ($SkipGeoPackage) {
    Write-Host ""
    Write-Host "1/5 - Upload de dados ignorado por parametro -SkipGeoPackage."
  }
  else {
    Publish-GeoServerData -GeoServer $GeoServer -Workspace $Workspace -Store $PublishContext.Store -DataEndpoint $PublishContext.DataEndpoint -DataType $PublishContext.DataType -DataContentType $PublishContext.DataContentType -DataPath $PublishContext.DataPath -DataLabel $PublishContext.DataLabel -GeoAuth $geoAuth -DryRun $DryRun
  }

  Set-GeoServerLayerTitle -GeoServer $GeoServer -Workspace $Workspace -Store $PublishContext.Store -Layer $PublishContext.Layer -DataEndpoint $PublishContext.DataEndpoint -LayerResource $PublishContext.LayerResource -LayerTitle $PublishContext.GeoServerLayerTitle -GeoAuth $geoAuth -DryRun $DryRun
  Publish-GeoServerStyle -GeoServer $GeoServer -Workspace $Workspace -Style $PublishContext.Style -Layer $PublishContext.Layer -SldPath $PublishContext.SldPath -GeoAuth $geoAuth -DryRun $DryRun
  Set-GeoServerDefaultStyle -GeoServer $GeoServer -Workspace $Workspace -Layer $PublishContext.Layer -Style $PublishContext.Style -GeoAuth $geoAuth -DryRun $DryRun

  $geoServerAttributeTypes = @{}
  if ($PublishContext.LayerResource -eq 'featuretypes' -and -not $DryRun) {
    Write-Host ""
    Write-Host "Coletando tipos dos atributos publicados no GeoServer..."
    $geoServerAttributeTypes = Get-GeoServerAttributeTypes -GeoServer $GeoServer -Workspace $Workspace -Store $PublishContext.Store -Layer $PublishContext.Layer -GeoAuth $geoAuth
    if ($geoServerAttributeTypes.Count -gt 0) {
      Write-Host "Tipos coletados: $($geoServerAttributeTypes.Count)"
    }
  }

  return @{
    Credential = $geoCredential
    Auth = $geoAuth
    AttributeTypes = $geoServerAttributeTypes
  }
}

