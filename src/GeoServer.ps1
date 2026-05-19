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
  $featureTypeUrl = "$GeoServer/rest/workspaces/$Workspace/datastores/$Store/featuretypes/$Layer.json"

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

