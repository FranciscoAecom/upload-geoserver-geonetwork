$ErrorActionPreference = "Stop"

function New-SldWithStyleName {
  param(
    [string]$SldPath,
    [string]$StyleName,
    [string]$LayerName
  )

  [xml]$sld = [IO.File]::ReadAllText($SldPath, [Text.Encoding]::UTF8)
  $namespaceManager = New-Object System.Xml.XmlNamespaceManager($sld.NameTable)
  $namespaceManager.AddNamespace("sld", "http://www.opengis.net/sld")
  $namespaceManager.AddNamespace("se", "http://www.opengis.net/se")

  $namedLayerNode = $sld.SelectSingleNode("/sld:StyledLayerDescriptor/sld:NamedLayer/sld:Name", $namespaceManager)
  if ($null -eq $namedLayerNode) {
    $namedLayerNode = $sld.SelectSingleNode("/sld:StyledLayerDescriptor/sld:NamedLayer/se:Name", $namespaceManager)
  }
  if ($null -ne $namedLayerNode) {
    $namedLayerNode.InnerText = $LayerName
  }

  $userStyleNode = $sld.SelectSingleNode("/sld:StyledLayerDescriptor/sld:NamedLayer/sld:UserStyle/sld:Name", $namespaceManager)
  if ($null -eq $userStyleNode) {
    $userStyleNode = $sld.SelectSingleNode("/sld:StyledLayerDescriptor/sld:NamedLayer/sld:UserStyle/se:Name", $namespaceManager)
  }
  if ($null -eq $userStyleNode) {
    $userStyleNode = $sld.SelectSingleNode("/sld:StyledLayerDescriptor/sld:UserLayer/sld:UserStyle/sld:Name", $namespaceManager)
  }
  if ($null -eq $userStyleNode) {
    $userStyleNode = $sld.SelectSingleNode("/sld:StyledLayerDescriptor/sld:UserLayer/sld:UserStyle/se:Name", $namespaceManager)
  }
  if ($null -ne $userStyleNode) {
    $userStyleNode.InnerText = $StyleName
  }

  $tempSld = Join-Path ([IO.Path]::GetTempPath()) ("style_{0}.sld" -f ([guid]::NewGuid()))
  $settings = New-Object Xml.XmlWriterSettings
  $settings.Encoding = New-Object Text.UTF8Encoding $false
  $settings.Indent = $true
  $writer = [Xml.XmlWriter]::Create($tempSld, $settings)
  try {
    $sld.Save($writer)
  }
  finally {
    $writer.Close()
  }

  return $tempSld
}

