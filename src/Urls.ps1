$ErrorActionPreference = "Stop"

function Join-UrlPath {
  param(
    [string]$BaseUrl,
    [string[]]$Segments
  )

  $url = $BaseUrl.TrimEnd("/")
  foreach ($segment in $Segments) {
    $url = "$url/$($segment.Trim('/'))"
  }

  return $url
}

function Get-GeoServerDataUploadUrl {
  param(
    [string]$GeoServer,
    [string]$Workspace,
    [string]$DataEndpoint,
    [string]$Store,
    [string]$DataType
  )

  return "$(Join-UrlPath -BaseUrl $GeoServer -Segments @("rest", "workspaces", $Workspace, $DataEndpoint, $Store, "file.${DataType}"))?configure=all"
}

function Get-GeoServerVersionUrl {
  param([string]$GeoServer)

  return Join-UrlPath -BaseUrl $GeoServer -Segments @("rest", "about", "version.json")
}

function Get-GeoServerLayerResourceUrl {
  param(
    [string]$GeoServer,
    [string]$Workspace,
    [string]$DataEndpoint,
    [string]$Store,
    [string]$LayerResource,
    [string]$Layer
  )

  return Join-UrlPath -BaseUrl $GeoServer -Segments @("rest", "workspaces", $Workspace, $DataEndpoint, $Store, $LayerResource, $Layer)
}

function Get-GeoServerStyleCollectionUrl {
  param(
    [string]$GeoServer,
    [string]$Workspace,
    [string]$Style
  )

  return "$(Join-UrlPath -BaseUrl $GeoServer -Segments @("rest", "workspaces", $Workspace, "styles"))?name=${Style}&raw=true"
}

function Get-GeoServerStyleUrl {
  param(
    [string]$GeoServer,
    [string]$Workspace,
    [string]$Style
  )

  return "$(Join-UrlPath -BaseUrl $GeoServer -Segments @("rest", "workspaces", $Workspace, "styles", $Style))?raw=true"
}

function Get-GeoServerLayerUrl {
  param(
    [string]$GeoServer,
    [string]$Workspace,
    [string]$Layer
  )

  return Join-UrlPath -BaseUrl $GeoServer -Segments @("rest", "layers", "$Workspace`:$Layer")
}

function Get-GeoServerLayerJsonUrl {
  param(
    [string]$GeoServer,
    [string]$Workspace,
    [string]$Layer
  )

  return "$(Get-GeoServerLayerUrl -GeoServer $GeoServer -Workspace $Workspace -Layer $Layer).json"
}

function Get-GeoServerFeatureTypeUrl {
  param(
    [string]$GeoServer,
    [string]$Workspace,
    [string]$Store,
    [string]$Layer
  )

  return "$(Join-UrlPath -BaseUrl $GeoServer -Segments @("rest", "workspaces", $Workspace, "datastores", $Store, "featuretypes", $Layer)).json"
}

function Get-GeoServerMapPreviewUrl {
  param([string]$GeoServer)

  return Join-UrlPath -BaseUrl $GeoServer -Segments @("web", "wicket", "bookmarkable", "org.geoserver.web.demo.MapPreviewPage")
}

function Get-GeoNetworkMeUrl {
  param([string]$Catalog)

  return Join-UrlPath -BaseUrl $Catalog -Segments @("srv", "api", "me")
}

function Get-GeoNetworkRecordsImportQuery {
  param(
    [string]$CatalogGroup,
    [string]$CatalogCategory
  )

  return @(
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
}

function Get-GeoNetworkRecordsImportUrls {
  param(
    [string]$Catalog,
    [string]$CatalogGroup,
    [string]$CatalogCategory
  )

  $query = Get-GeoNetworkRecordsImportQuery -CatalogGroup $CatalogGroup -CatalogCategory $CatalogCategory
  $apiRecords = Join-UrlPath -BaseUrl $Catalog -Segments @("srv", "api", "records")
  $porApiRecords = Join-UrlPath -BaseUrl $Catalog -Segments @("srv", "por", "api", "records")
  return @(
    "$($apiRecords)?$query",
    "$($apiRecords)/?$query",
    "$($porApiRecords)?$query",
    "$($porApiRecords)/?$query"
  )
}

function Get-GeoNetworkLegacyImportUrls {
  param([string]$Catalog)

  return @(
    (Join-UrlPath -BaseUrl $Catalog -Segments @("srv", "por", "metadata.insert")),
    (Join-UrlPath -BaseUrl $Catalog -Segments @("srv", "por", "xml.metadata.insert")),
    (Join-UrlPath -BaseUrl $Catalog -Segments @("srv", "api", "0.1", "records"))
  )
}
