$ErrorActionPreference = "Stop"

function New-SldWithStyleName {
  param(
    [string]$SldPath,
    [string]$StyleName,
    [string]$LayerName
  )

  $tempSld = Join-Path ([IO.Path]::GetTempPath()) ("style_{0}.sld" -f ([guid]::NewGuid()))
  Copy-Item -LiteralPath $SldPath -Destination $tempSld -Force

  return $tempSld
}

function Get-SldContentType {
  param([string]$SldPath)

  $sldContent = [IO.File]::ReadAllText($SldPath, [Text.Encoding]::UTF8)
  if ($sldContent -match 'version\s*=\s*["'']1\.1\.0["'']' -or $sldContent -match 'http://www\.opengis\.net/se') {
    return "application/vnd.ogc.se+xml"
  }

  return "application/vnd.ogc.sld+xml"
}

