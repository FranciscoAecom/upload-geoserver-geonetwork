param(
  [string]$Folder = "L:\Secure_DCS\BRBLH1PINFW001\COE_Digital\coe_digital_data\silver_data\restricted\pcd\ur_car_rs\AECOM\20260514\00",
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

function Resolve-RequiredFile {
  param(
    [string]$Path,
    [string]$Pattern
  )

  $files = @(Get-ChildItem -LiteralPath $Path -Filter $Pattern -File)
  if ($files.Count -ne 1) {
    throw "Esperava 1 arquivo '$Pattern' em '$Path', mas encontrei $($files.Count)."
  }

  return $files[0].FullName
}

function Resolve-RequiredMetadataFile {
  param([string]$Path)

  $files = @(Get-ChildItem -LiteralPath $Path -Filter "*.xml" -File | Where-Object {
    $_.Name -notmatch '\.aux\.xml$'
  })

  if ($files.Count -ne 1) {
    throw "Esperava 1 arquivo de metadados XML em '$Path', mas encontrei $($files.Count)."
  }

  return $files[0].FullName
}

function Resolve-RequiredDataFile {
  param([string]$Path)

  $files = @(Get-ChildItem -LiteralPath $Path -File | Where-Object {
    $extension = $_.Extension.ToLowerInvariant()
    $extension -in '.gpkg', '.rst', '.tif'
  })

  if ($files.Count -ne 1) {
    throw "Esperava exatamente 1 arquivo de dados (.gpkg, .rst ou .tif) em '$Path', mas encontrei $($files.Count)."
  }

  return $files[0].FullName
}

function ConvertTo-BasicAuth {
  param([pscredential]$Credential)

  $user = $Credential.UserName
  $pass = $Credential.GetNetworkCredential().Password
  $pair = "$user`:$pass"
  return [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($pair))
}

function Repair-Mojibake {
  param([string]$Text)

  if ([string]::IsNullOrWhiteSpace($Text) -or $Text -notmatch "[ÃÂ]") {
    return $Text
  }

  $windows1252 = [Text.Encoding]::GetEncoding(1252)
  return [Text.Encoding]::UTF8.GetString($windows1252.GetBytes($Text))
}

function ConvertTo-XmlEscapedText {
  param([string]$Text)

  $builder = New-Object Text.StringBuilder
  foreach ($character in $Text.ToCharArray()) {
    $code = [int][char]$character
    switch ($character) {
      "<" { [void]$builder.Append("&lt;") }
      ">" { [void]$builder.Append("&gt;") }
      "&" { [void]$builder.Append("&amp;") }
      '"' { [void]$builder.Append("&quot;") }
      "'" { [void]$builder.Append("&apos;") }
      default {
        if ($code -lt 32 -or $code -gt 126) {
          [void]$builder.Append(("&#x{0:X4};" -f $code))
        }
        else {
          [void]$builder.Append($character)
        }
      }
    }
  }

  return $builder.ToString()
}

function ConvertTo-XmlMarkupEscapedText {
  param([string]$Text)

  if ($null -eq $Text) {
    return $null
  }

  return $Text.
    Replace("&", "&amp;").
    Replace("<", "&lt;").
    Replace(">", "&gt;").
    Replace('"', "&quot;").
    Replace("'", "&apos;")
}

function ConvertTo-JsonEscapedText {
  param([string]$Text)

  $builder = New-Object Text.StringBuilder
  foreach ($character in $Text.ToCharArray()) {
    $code = [int][char]$character
    switch ($character) {
      '"' { [void]$builder.Append('\"') }
      '\' { [void]$builder.Append('\\') }
      "`b" { [void]$builder.Append('\b') }
      "`f" { [void]$builder.Append('\f') }
      "`n" { [void]$builder.Append('\n') }
      "`r" { [void]$builder.Append('\r') }
      "`t" { [void]$builder.Append('\t') }
      default {
        if ($code -lt 32 -or $code -gt 126) {
          [void]$builder.Append(('\u{0:x4}' -f $code))
        }
        else {
          [void]$builder.Append($character)
        }
      }
    }
  }

  return $builder.ToString()
}

function ConvertTo-AsciiText {
  param([string]$Text)

  if ([string]::IsNullOrWhiteSpace($Text)) {
    return $Text
  }

  $normalized = $Text.Normalize([Text.NormalizationForm]::FormD)
  $builder = New-Object Text.StringBuilder
  foreach ($character in $normalized.ToCharArray()) {
    $category = [Globalization.CharUnicodeInfo]::GetUnicodeCategory($character)
    if ($category -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
      [void]$builder.Append($character)
    }
  }

  return $builder.ToString().Normalize([Text.NormalizationForm]::FormC)
}

function Get-StateNameFromLayer {
  param([string]$LayerName)

  $aAcute = [char]0x00E1
  $iAcute = [char]0x00ED
  $aTilde = [char]0x00E3
  $oCircumflex = [char]0x00F4

  $stateNames = @{
    "ac" = "Acre"
    "al" = "Alagoas"
    "am" = "Amazonas"
    "ap" = ("Amap" + $aAcute)
    "ba" = "Bahia"
    "ce" = ("Cear" + $aAcute)
    "df" = "Distrito Federal"
    "es" = ("Esp" + $iAcute + "rito Santo")
    "go" = ("Goi" + $aAcute + "s")
    "ma" = ("Maranh" + $aTilde + "o")
    "mg" = "Minas Gerais"
    "ms" = "Mato Grosso do Sul"
    "mt" = "Mato Grosso"
    "pa" = ("Par" + $aAcute)
    "pb" = ("Para" + $iAcute + "ba")
    "pe" = "Pernambuco"
    "pi" = ("Piau" + $iAcute)
    "pr" = ("Paran" + $aAcute)
    "rj" = "Rio de Janeiro"
    "rn" = "Rio Grande do Norte"
    "ro" = ("Rond" + $oCircumflex + "nia")
    "rr" = "Roraima"
    "rs" = "Rio Grande do Sul"
    "sc" = "Santa Catarina"
    "se" = "Sergipe"
    "sp" = ("S" + $aTilde + "o Paulo")
    "to" = "Tocantins"
  }

  if ($LayerName -match "_([a-z]{2})_\d{8}$") {
    $stateCode = $Matches[1].ToLowerInvariant()
    if ($stateNames.ContainsKey($stateCode)) {
      return $stateNames[$stateCode]
    }
  }

  return $null
}

function Get-AppCarLayerTitle {
  param([string]$LayerName)

  $stateName = Get-StateNameFromLayer -LayerName $LayerName
  if ([string]::IsNullOrWhiteSpace($stateName)) {
    return $null
  }

  $aAcuteUpper = [char]0x00C1
  $cCedilla = [char]0x00E7
  $aTilde = [char]0x00E3
  $oAcute = [char]0x00F3

  return ("{0}rea de Preserva{1}{2}o Permanente - Im{3}veis {4}" -f $aAcuteUpper, $cCedilla, $aTilde, $oAcute, $stateName)
}

function Get-SaCarLayerTitle {
  param([string]$LayerName)

  $stateName = Get-StateNameFromLayer -LayerName $LayerName
  if ([string]::IsNullOrWhiteSpace($stateName)) {
    return $null
  }

  $aTilde = [char]0x00E3
  $oAcute = [char]0x00F3

  return ("Servid{0}o Administrativa - Im{1}veis {2}" -f $aTilde, $oAcute, $stateName)
}

function Get-UrCarLayerTitle {
  param([string]$LayerName)

  $stateName = Get-StateNameFromLayer -LayerName $LayerName
  if ([string]::IsNullOrWhiteSpace($stateName)) {
    return $null
  }

  $oAcute = [char]0x00F3

  return ("Uso Restrito - Im{0}veis {1}" -f $oAcute, $stateName)
}

function Get-ImbLulcLayerTitle {
  param([string]$LayerName)

  if ($LayerName -notmatch "^rst_imb_lulc_(\d{4})(\d*)$") {
    return $null
  }

  $year = $Matches[1]
  $suffix = $Matches[2]
  $cCedilla = [char]0x00E7
  $aTilde = [char]0x00E3

  if ($suffix -match "^\d{3}") {
    $collection = [int]$Matches[0]
    return ("Uso e cobertura da terra de {0} - Cole{1}{2}o {3}" -f $year, $cCedilla, $aTilde, $collection)
  }

  return ("Uso e cobertura da terra de {0}" -f $year)
}

function Assert-KnownLayerNaming {
  param([string]$LayerName)

  if ($LayerName -match "^rst_imb_lulc_" -and [string]::IsNullOrWhiteSpace((Get-ImbLulcLayerTitle -LayerName $LayerName))) {
    Write-Warning "Nao consegui interpretar ano/colecao pelo nome da camada IMB LULC '$LayerName'. O script vai usar o titulo do XML ou o proprio nome da camada."
  }
}

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

function Invoke-Curl {
  param([string[]]$Arguments)

  $displayArguments = foreach ($argument in $Arguments) {
    if ($argument -like "Authorization: Basic *") {
      "Authorization: Basic ***"
    }
    else {
      $argument
    }
  }

  Write-Host ""
  Write-Host "curl.exe $($displayArguments -join ' ')"
  & curl.exe @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "curl.exe falhou com exit code $LASTEXITCODE."
  }
}

function Invoke-CurlCapture {
  param([string[]]$Arguments)

  $displayArguments = foreach ($argument in $Arguments) {
    if ($argument -like "Authorization: Basic *") {
      "Authorization: Basic ***"
    }
    elseif ($argument -like "X-XSRF-TOKEN: *") {
      "X-XSRF-TOKEN: ***"
    }
    else {
      $argument
    }
  }

  Write-Host ""
  Write-Host "curl.exe $($displayArguments -join ' ')"
  $output = & curl.exe @Arguments
  if ($LASTEXITCODE -ne 0) {
    $body = ($output -join "`n")
    if (-not [string]::IsNullOrWhiteSpace($body)) {
      throw "curl.exe falhou com exit code $LASTEXITCODE. Resposta: $body"
    }
    throw "curl.exe falhou com exit code $LASTEXITCODE."
  }

  return ($output -join "`n")
}

function Test-MeaningfulGeoNetworkErrorValue {
  param([object]$Value)

  if ($null -eq $Value) {
    return $false
  }

  if ($Value -is [bool]) {
    return $Value
  }

  if ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal]) {
    return $Value -ne 0
  }

  if ($Value -is [string]) {
    return -not [string]::IsNullOrWhiteSpace($Value)
  }

  if ($Value -is [array]) {
    return $Value.Count -gt 0
  }

  if ($Value -is [pscustomobject]) {
    return @($Value.PSObject.Properties).Count -gt 0
  }

  return $true
}

function Assert-GeoNetworkModernImportSucceeded {
  param([string]$Output)

  if ([string]::IsNullOrWhiteSpace($Output)) {
    throw "GeoNetwork retornou resposta vazia para a importacao."
  }

  if ($Output -match "(?is)<html|gnSearchSettings|catalog.search") {
    throw "GeoNetwork retornou HTML em vez de relatorio JSON de importacao."
  }

  try {
    $json = $Output | ConvertFrom-Json
  }
  catch {
    throw "GeoNetwork retornou uma resposta que nao e JSON valido: $Output"
  }

  $queue = New-Object System.Collections.Queue
  $queue.Enqueue($json)
  while ($queue.Count -gt 0) {
    $current = $queue.Dequeue()
    if ($null -eq $current) {
      continue
    }

    if ($current -is [array]) {
      foreach ($item in $current) {
        $queue.Enqueue($item)
      }
      continue
    }

    if ($current -isnot [pscustomobject]) {
      continue
    }

    foreach ($property in $current.PSObject.Properties) {
      $name = $property.Name
      $value = $property.Value

      if ($name -match "(?i)^(success|successful)$" -and $value -is [bool] -and -not $value) {
        throw "GeoNetwork indicou falha no relatorio de importacao: $Output"
      }

      if ($name -match "(?i)(error|errors|exception|rejected|failed|failure|invalid)" -and (Test-MeaningfulGeoNetworkErrorValue -Value $value)) {
        throw "GeoNetwork indicou erro no relatorio de importacao: $Output"
      }

      if ($value -is [array] -or $value -is [pscustomobject]) {
        $queue.Enqueue($value)
      }
    }
  }
}

function Get-CookieValue {
  param(
    [string]$CookieJar,
    [string]$CookieName
  )

  if (-not (Test-Path -LiteralPath $CookieJar)) {
    return $null
  }

  $line = Get-Content -LiteralPath $CookieJar |
    Where-Object { $_ -notmatch "^\s*#" -and $_ -match "\s$([regex]::Escape($CookieName))\s" } |
    Select-Object -Last 1

  if ([string]::IsNullOrWhiteSpace($line)) {
    return $null
  }

  return ($line -split "`t")[-1]
}

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
