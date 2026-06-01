$ErrorActionPreference = "Stop"

function Get-DataPublishInfo {
  param([string]$DataPath)

  $dataExtension = [IO.Path]::GetExtension($DataPath).ToLowerInvariant()
  switch ($dataExtension) {
    '.gpkg' {
      return [pscustomobject]@{
        Extension = $dataExtension
        Type = 'gpkg'
        ContentType = 'application/geopackage+vnd.sqlite3'
        Endpoint = 'datastores'
        LayerResource = 'featuretypes'
        Label = 'GPKG'
      }
    }
    '.rst' {
      return [pscustomobject]@{
        Extension = $dataExtension
        Type = 'rst'
        ContentType = 'application/octet-stream'
        Endpoint = 'coveragestores'
        LayerResource = 'coverages'
        Label = 'RST'
      }
    }
    '.tif' {
      return [pscustomobject]@{
        Extension = $dataExtension
        Type = 'geotiff'
        ContentType = 'image/tiff'
        Endpoint = 'coveragestores'
        LayerResource = 'coverages'
        Label = 'TIFF'
      }
    }
    default {
      throw "Tipo de arquivo nao suportado: $dataExtension"
    }
  }
}

function Resolve-StoreLayerNames {
  param(
    [string]$DataPath,
    [string]$Store,
    [string]$Layer
  )

  $derivedLayerName = [IO.Path]::GetFileNameWithoutExtension($DataPath)
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

  return [pscustomobject]@{
    Store = $Store
    Layer = $Layer
  }
}

function Resolve-GeoServerLayerTitle {
  param(
    [string]$Layer,
    [string]$LayerTitle
  )

  $geoServerLayerTitle = $null
  if ($Layer -match "_app_car_") {
    $geoServerLayerTitle = Get-AppCarLayerTitle -LayerName $Layer
  }
  elseif ($Layer -match "_sa_car_") {
    $geoServerLayerTitle = Get-SaCarLayerTitle -LayerName $Layer
  }
  elseif ($Layer -match "_ur_car_") {
    $geoServerLayerTitle = Get-UrCarLayerTitle -LayerName $Layer
  }
  elseif ($Layer -match "^rst_imb_lulc_") {
    $geoServerLayerTitle = Get-ImbLulcLayerTitle -LayerName $Layer
  }
  elseif ($Layer -match "^pnt_pcd_enov") {
    $geoServerLayerTitle = Get-AutosInfracaoLayerTitle -LayerName $Layer
  }
  elseif ($Layer -match "^pol_loc_cse_") {
    $geoServerLayerTitle = Get-SetorCensitarioLayerTitle -LayerName $Layer
  }
  elseif ($Layer -match "^pol_soc_ctbp_") {
    $geoServerLayerTitle = Get-CensoTerritorialBasicoParametrosLayerTitle -LayerName $Layer
  }

  if ([string]::IsNullOrWhiteSpace($geoServerLayerTitle)) {
    $geoServerLayerTitle = $LayerTitle
  }

  return $geoServerLayerTitle
}

function New-PublishContext {
  param(
    [string]$DataPath,
    [string]$SldPath,
    [string]$XmlPath,
    [string]$Store,
    [string]$Layer,
    [string]$LayerTitle,
    [string]$Style
  )

  $names = Resolve-StoreLayerNames -DataPath $DataPath -Store $Store -Layer $Layer
  Assert-KnownLayerNaming -LayerName $names.Layer

  $dataInfo = Get-DataPublishInfo -DataPath $DataPath

  if ([string]::IsNullOrWhiteSpace($Style)) {
    $Style = [IO.Path]::GetFileNameWithoutExtension($SldPath)
  }

  if ([string]::IsNullOrWhiteSpace($LayerTitle)) {
    $LayerTitle = Get-MetadataTitle -XmlPath $XmlPath
  }
  if ([string]::IsNullOrWhiteSpace($LayerTitle)) {
    $LayerTitle = $names.Layer
  }

  return [pscustomobject]@{
    DataPath = $DataPath
    SldPath = $SldPath
    XmlPath = $XmlPath
    Store = $names.Store
    Layer = $names.Layer
    Style = $Style
    LayerTitle = $LayerTitle
    GeoServerLayerTitle = Resolve-GeoServerLayerTitle -Layer $names.Layer -LayerTitle $LayerTitle
    DataExtension = $dataInfo.Extension
    DataType = $dataInfo.Type
    DataContentType = $dataInfo.ContentType
    DataEndpoint = $dataInfo.Endpoint
    LayerResource = $dataInfo.LayerResource
    DataLabel = $dataInfo.Label
  }
}
