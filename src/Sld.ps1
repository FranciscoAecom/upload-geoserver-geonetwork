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

