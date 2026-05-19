$ErrorActionPreference = "Stop"

function Get-MetadataTitle {
  param([string]$XmlPath)

  [xml]$metadata = [IO.File]::ReadAllText($XmlPath, [Text.Encoding]::UTF8)
  $namespaceManager = New-Object System.Xml.XmlNamespaceManager($metadata.NameTable)
  $namespaceManager.AddNamespace("gmd", "http://www.isotc211.org/2005/gmd")
  $namespaceManager.AddNamespace("gco", "http://www.isotc211.org/2005/gco")

  $titleNode = $metadata.SelectSingleNode("//gmd:identificationInfo//gmd:citation//gmd:title/gco:CharacterString", $namespaceManager)
  if ($null -eq $titleNode -or [string]::IsNullOrWhiteSpace($titleNode.InnerText)) {
    return $null
  }

  return Repair-Mojibake -Text $titleNode.InnerText.Trim()
}

function Get-MetadataUuid {
  param([string]$XmlPath)

  [xml]$metadata = [IO.File]::ReadAllText($XmlPath, [Text.Encoding]::UTF8)
  $namespaceManager = New-Object System.Xml.XmlNamespaceManager($metadata.NameTable)
  $namespaceManager.AddNamespace("gmd", "http://www.isotc211.org/2005/gmd")
  $namespaceManager.AddNamespace("gco", "http://www.isotc211.org/2005/gco")

  $uuidNode = $metadata.SelectSingleNode("/gmd:MD_Metadata/gmd:fileIdentifier/gco:CharacterString", $namespaceManager)
  if ($null -eq $uuidNode -or [string]::IsNullOrWhiteSpace($uuidNode.InnerText)) {
    return $null
  }

  return $uuidNode.InnerText.Trim()
}

function Set-DataDictionaryFieldTypes {
  param(
    [string]$XmlContent,
    [hashtable]$AttributeTypes
  )

  if ($null -eq $AttributeTypes -or $AttributeTypes.Count -eq 0) {
    return @{
      Content = $XmlContent
      Count = 0
    }
  }

  $dictionaryMatch = [regex]::Match($XmlContent, "(?is)<data_dictionary\b[^>]*>.*?</data_dictionary>")
  if (-not $dictionaryMatch.Success) {
    return @{
      Content = $XmlContent
      Count = 0
    }
  }

  $counter = [pscustomobject]@{ Count = 0 }
  $dictionaryXml = $dictionaryMatch.Value
  $updatedDictionaryXml = [regex]::Replace($dictionaryXml, "(?is)<field\b[^>]*>.*?</field>", {
    param($match)

    $fieldXml = $match.Value
    $nameMatch = [regex]::Match($fieldXml, "(?is)<name>\s*([^<]+?)\s*</name>")
    if (-not $nameMatch.Success) {
      return $fieldXml
    }

    $fieldName = $nameMatch.Groups[1].Value.Trim()
    $newType = $null
    if ($AttributeTypes.ContainsKey($fieldName)) {
      $newType = $AttributeTypes[$fieldName]
    }
    elseif ($AttributeTypes.ContainsKey("sdb_$fieldName")) {
      $newType = $AttributeTypes["sdb_$fieldName"]
    }
    else {
      $suffixMatches = @($AttributeTypes.Keys | Where-Object { $_ -like "*_$fieldName" })
      if ($suffixMatches.Count -eq 1) {
        $newType = $AttributeTypes[$suffixMatches[0]]
      }
    }

    if ([string]::IsNullOrWhiteSpace($newType)) {
      return $fieldXml
    }

    $escapedType = ConvertTo-XmlEscapedText -Text $newType
    if ($fieldXml -match "(?is)<type>.*?</type>") {
      $updatedFieldXml = [regex]::Replace($fieldXml, "(?is)<type>.*?</type>", "<type>$escapedType</type>", 1)
    }
    else {
      $updatedFieldXml = [regex]::Replace($fieldXml, "(?is)(</field>)", "  <type>$escapedType</type>`r`n`$1", 1)
    }

    if ($updatedFieldXml -ne $fieldXml) {
      $counter.Count++
    }

    return $updatedFieldXml
  })

  $updatedContent = $XmlContent.Substring(0, $dictionaryMatch.Index) +
    $updatedDictionaryXml +
    $XmlContent.Substring($dictionaryMatch.Index + $dictionaryMatch.Length)

  return @{
    Content = $updatedContent
    Count = $counter.Count
  }
}

function New-MetadataXmlWithDataDictionaryLink {
  param(
    [string]$XmlPath,
    [string]$DataDictionaryBaseUrl,
    [hashtable]$AttributeTypes
  )

  $metadataUuid = Get-MetadataUuid -XmlPath $XmlPath
  if ([string]::IsNullOrWhiteSpace($metadataUuid)) {
    Write-Warning "Nao foi possivel identificar o UUID do XML; importando sem link do dicionario de dados."
    return $XmlPath
  }

  $dictionaryUrl = "$DataDictionaryBaseUrl`?key=$metadataUuid"
  $xmlContent = [IO.File]::ReadAllText($XmlPath, [Text.Encoding]::UTF8)
  $typeUpdateResult = Set-DataDictionaryFieldTypes -XmlContent $xmlContent -AttributeTypes $AttributeTypes
  $xmlContent = $typeUpdateResult.Content
  $updatedTypeCount = $typeUpdateResult.Count
  if ($xmlContent -like "*$dictionaryUrl*") {
    if ($updatedTypeCount -eq 0) {
      return $XmlPath
    }

    $tempXml = Join-Path ([IO.Path]::GetTempPath()) ("metadata_with_data_dictionary_{0}.xml" -f ([guid]::NewGuid()))
    $utf8NoBom = New-Object Text.UTF8Encoding $false
    [IO.File]::WriteAllText($tempXml, $xmlContent, $utf8NoBom)
    Write-Host "Tipos do dicionario de dados inseridos no XML temporario: $updatedTypeCount"
    return $tempXml
  }

  $escapedDictionaryUrl = ConvertTo-XmlEscapedText -Text $dictionaryUrl
  if ($xmlContent -match "<gmd:URL\s*/>") {
    $updatedContent = [regex]::Replace($xmlContent, "<gmd:URL\s*/>", "<gmd:URL>$escapedDictionaryUrl</gmd:URL>", 1)
  }
  elseif ($xmlContent -like "*Estrutura de 2 link associado*") {
    $updatedContent = $xmlContent.Replace("Estrutura de 2 link associado", $escapedDictionaryUrl)
  }
  else {
    Write-Warning "Nao encontrei <gmd:URL/> vazio nem placeholder do segundo link; importando sem inserir link do dicionario de dados."
    if ($updatedTypeCount -eq 0) {
      return $XmlPath
    }

    $tempXml = Join-Path ([IO.Path]::GetTempPath()) ("metadata_with_data_dictionary_{0}.xml" -f ([guid]::NewGuid()))
    $utf8NoBom = New-Object Text.UTF8Encoding $false
    [IO.File]::WriteAllText($tempXml, $xmlContent, $utf8NoBom)
    Write-Host "Tipos do dicionario de dados inseridos no XML temporario: $updatedTypeCount"
    return $tempXml
  }

  $tempXml = Join-Path ([IO.Path]::GetTempPath()) ("metadata_with_data_dictionary_{0}.xml" -f ([guid]::NewGuid()))
  $utf8NoBom = New-Object Text.UTF8Encoding $false
  [IO.File]::WriteAllText($tempXml, $updatedContent, $utf8NoBom)
  Write-Host "Link do dicionario de dados inserido no XML temporario:"
  Write-Host "  $dictionaryUrl"
  if ($updatedTypeCount -gt 0) {
    Write-Host "Tipos do dicionario de dados inseridos no XML temporario: $updatedTypeCount"
  }
  return $tempXml
}

