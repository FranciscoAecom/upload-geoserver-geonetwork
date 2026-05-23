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

function Get-DataDictionaryFieldType {
  param(
    [string]$FieldName,
    [hashtable]$AttributeTypes
  )

  if ($AttributeTypes.ContainsKey($FieldName)) {
    return $AttributeTypes[$FieldName]
  }

  if ($AttributeTypes.ContainsKey("sdb_$FieldName")) {
    return $AttributeTypes["sdb_$FieldName"]
  }

  $suffixMatches = @($AttributeTypes.Keys | Where-Object { $_ -like "*_$FieldName" })
  if ($suffixMatches.Count -eq 1) {
    return $AttributeTypes[$suffixMatches[0]]
  }

  return $null
}

function Set-DataDictionaryFieldTypesWithXmlParser {
  param(
    [string]$DictionaryXml,
    [hashtable]$AttributeTypes
  )

  $document = New-Object Xml.XmlDocument
  $document.PreserveWhitespace = $true
  $document.LoadXml($DictionaryXml)

  $counter = 0
  $fieldNodes = @($document.DocumentElement.SelectNodes(".//*[local-name()='field']"))
  foreach ($fieldNode in $fieldNodes) {
    $nameNode = $fieldNode.SelectSingleNode("./*[local-name()='name']")
    if ($null -eq $nameNode -or [string]::IsNullOrWhiteSpace($nameNode.InnerText)) {
      continue
    }

    $fieldName = $nameNode.InnerText.Trim()
    $newType = Get-DataDictionaryFieldType -FieldName $fieldName -AttributeTypes $AttributeTypes
    if ([string]::IsNullOrWhiteSpace($newType)) {
      continue
    }

    $typeNode = $fieldNode.SelectSingleNode("./*[local-name()='type']")
    if ($null -eq $typeNode) {
      $typeNode = $document.CreateElement("type", $fieldNode.NamespaceURI)
      [void]$fieldNode.AppendChild($typeNode)
    }

    if ($typeNode.InnerText -ne $newType) {
      $typeNode.InnerText = $newType
      $counter++
    }
  }

  return @{
    Content = $document.DocumentElement.OuterXml
    Count = $counter
  }
}

function Set-DataDictionaryFieldTypesWithRegex {
  param(
    [string]$DictionaryXml,
    [hashtable]$AttributeTypes
  )

  $counter = [pscustomobject]@{ Count = 0 }
  $updatedDictionaryXml = [regex]::Replace($DictionaryXml, "(?is)<field\b[^>]*>.*?</field>", {
    param($match)

    $fieldXml = $match.Value
    $nameMatch = [regex]::Match($fieldXml, "(?is)<name>\s*([^<]+?)\s*</name>")
    if (-not $nameMatch.Success) {
      return $fieldXml
    }

    $fieldName = $nameMatch.Groups[1].Value.Trim()
    $newType = Get-DataDictionaryFieldType -FieldName $fieldName -AttributeTypes $AttributeTypes
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

  return @{
    Content = $updatedDictionaryXml
    Count = $counter.Count
  }
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

  $dictionaryXml = $dictionaryMatch.Value
  try {
    $updateResult = Set-DataDictionaryFieldTypesWithXmlParser -DictionaryXml $dictionaryXml -AttributeTypes $AttributeTypes
  }
  catch {
    $updateResult = Set-DataDictionaryFieldTypesWithRegex -DictionaryXml $dictionaryXml -AttributeTypes $AttributeTypes
  }

  $updatedContent = $XmlContent.Substring(0, $dictionaryMatch.Index) +
    $updateResult.Content +
    $XmlContent.Substring($dictionaryMatch.Index + $dictionaryMatch.Length)

  return @{
    Content = $updatedContent
    Count = $updateResult.Count
  }
}

function Get-DataDictionaryUrl {
  param(
    [string]$DataDictionaryBaseUrl,
    [string]$MetadataUuid
  )

  return "$DataDictionaryBaseUrl`?key=$MetadataUuid"
}

function Add-DataDictionaryLink {
  param(
    [string]$XmlContent,
    [string]$DictionaryUrl
  )

  $escapedDictionaryUrl = ConvertTo-XmlEscapedText -Text $DictionaryUrl
  if ($XmlContent -like "*Estrutura de 2 link associado*") {
    return @{
      Content = $XmlContent.Replace("Estrutura de 2 link associado", $escapedDictionaryUrl)
      Inserted = $true
    }
  }

  if ($XmlContent -match "<gmd:URL\s*/>") {
    return @{
      Content = [regex]::Replace($XmlContent, "<gmd:URL\s*/>", "<gmd:URL>$escapedDictionaryUrl</gmd:URL>", 1)
      Inserted = $true
    }
  }

  return @{
    Content = $XmlContent
    Inserted = $false
  }
}

function Write-TemporaryMetadataXml {
  param([string]$XmlContent)

  $tempXml = Join-Path ([IO.Path]::GetTempPath()) ("metadata_with_data_dictionary_{0}.xml" -f ([guid]::NewGuid()))
  $utf8NoBom = New-Object Text.UTF8Encoding $false
  [IO.File]::WriteAllText($tempXml, $XmlContent, $utf8NoBom)
  return $tempXml
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

  $dictionaryUrl = Get-DataDictionaryUrl -DataDictionaryBaseUrl $DataDictionaryBaseUrl -MetadataUuid $metadataUuid
  $xmlContent = [IO.File]::ReadAllText($XmlPath, [Text.Encoding]::UTF8)
  $typeUpdateResult = Set-DataDictionaryFieldTypes -XmlContent $xmlContent -AttributeTypes $AttributeTypes
  $xmlContent = $typeUpdateResult.Content
  $updatedTypeCount = $typeUpdateResult.Count
  if ($xmlContent -like "*$dictionaryUrl*") {
    if ($updatedTypeCount -eq 0) {
      return $XmlPath
    }

    $tempXml = Write-TemporaryMetadataXml -XmlContent $xmlContent
    Write-Host "Tipos do dicionario de dados inseridos no XML temporario: $updatedTypeCount"
    return $tempXml
  }

  $linkResult = Add-DataDictionaryLink -XmlContent $xmlContent -DictionaryUrl $dictionaryUrl
  if (-not $linkResult.Inserted) {
    Write-Warning "Nao encontrei <gmd:URL/> vazio nem placeholder do segundo link; importando sem inserir link do dicionario de dados."
    if ($updatedTypeCount -eq 0) {
      return $XmlPath
    }

    $tempXml = Write-TemporaryMetadataXml -XmlContent $xmlContent
    Write-Host "Tipos do dicionario de dados inseridos no XML temporario: $updatedTypeCount"
    return $tempXml
  }

  $tempXml = Write-TemporaryMetadataXml -XmlContent $linkResult.Content
  Write-Host "Link do dicionario de dados inserido no XML temporario:"
  Write-Host "  $dictionaryUrl"
  if ($updatedTypeCount -gt 0) {
    Write-Host "Tipos do dicionario de dados inseridos no XML temporario: $updatedTypeCount"
  }
  return $tempXml
}

