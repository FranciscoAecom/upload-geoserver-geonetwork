param(
  [string]$Folder = "C:\Users\RibeiroF\Downloads\app_car_ba\SICAR\20260301\00",
  [string]$GeoServer = "https://gisqas.iocasta.com.br/geoserver",
  [string]$Catalog = "https://catalogqas.iocasta.com.br",
  [string]$Workspace = "gold",
  [string]$Store = "pol_pcd_app_car_ba_20260301",
  [string]$Layer = "pol_pcd_app_car_ba_20260301",
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

function New-MetadataXmlWithDataDictionaryLink {
  param(
    [string]$XmlPath,
    [string]$DataDictionaryBaseUrl
  )

  $metadataUuid = Get-MetadataUuid -XmlPath $XmlPath
  if ([string]::IsNullOrWhiteSpace($metadataUuid)) {
    Write-Warning "Nao foi possivel identificar o UUID do XML; importando sem link do dicionario de dados."
    return $XmlPath
  }

  $dictionaryUrl = "$DataDictionaryBaseUrl`?key=$metadataUuid"
  $xmlContent = [IO.File]::ReadAllText($XmlPath, [Text.Encoding]::UTF8)
  if ($xmlContent -like "*$dictionaryUrl*") {
    return $XmlPath
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
    return $XmlPath
  }

  $tempXml = Join-Path ([IO.Path]::GetTempPath()) ("metadata_with_data_dictionary_{0}.xml" -f ([guid]::NewGuid()))
  $utf8NoBom = New-Object Text.UTF8Encoding $false
  [IO.File]::WriteAllText($tempXml, $updatedContent, $utf8NoBom)
  Write-Host "Link do dicionario de dados inserido no XML temporario:"
  Write-Host "  $dictionaryUrl"
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

  $namedLayerNode = $sld.SelectSingleNode("/sld:StyledLayerDescriptor/sld:NamedLayer/se:Name", $namespaceManager)
  if ($null -ne $namedLayerNode) {
    $namedLayerNode.InnerText = $LayerName
  }

  $userStyleNode = $sld.SelectSingleNode("/sld:StyledLayerDescriptor/sld:NamedLayer/sld:UserStyle/se:Name", $namespaceManager)
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

$gpkgPath = Resolve-RequiredFile -Path $Folder -Pattern "*.gpkg"
$sldPath = Resolve-RequiredFile -Path $Folder -Pattern "*.sld"
$xmlPath = Resolve-RequiredFile -Path $Folder -Pattern "*.xml"

if ([string]::IsNullOrWhiteSpace($Style)) {
  $Style = [IO.Path]::GetFileNameWithoutExtension($sldPath)
}

if ([string]::IsNullOrWhiteSpace($LayerTitle)) {
  $LayerTitle = Get-MetadataTitle -XmlPath $xmlPath
}
if ([string]::IsNullOrWhiteSpace($LayerTitle)) {
  $LayerTitle = $Layer
}
$GeoServerLayerTitle = Get-AppCarLayerTitle -LayerName $Layer
if ([string]::IsNullOrWhiteSpace($GeoServerLayerTitle)) {
  $GeoServerLayerTitle = $LayerTitle
}

Write-Host "Arquivos encontrados:"
Write-Host "  GPKG: $gpkgPath"
Write-Host "  SLD : $sldPath"
Write-Host "  XML : $xmlPath"
Write-Host ""
Write-Host "Destino GeoServer: $GeoServer"
Write-Host "Workspace: $Workspace"
Write-Host "Store/Layer/Style: $Store"
Write-Host "Titulo Catalogo: $LayerTitle"
Write-Host "Titulo GeoServer: $GeoServerLayerTitle"

$geoCredential = $null
$geoAuth = $null

if ($SkipGeoServer) {
  Write-Host ""
  Write-Host "1-4/5 - Etapas do GeoServer ignoradas por parametro -SkipGeoServer."
}
else {
  $geoCredential = Get-Credential -Message "Credenciais do GeoServer QAS"
  $geoAuth = ConvertTo-BasicAuth -Credential $geoCredential

  if ($SkipGeoPackage) {
    Write-Host ""
    Write-Host "1/5 - GeoPackage ignorado por parametro -SkipGeoPackage."
  }
  else {
    Write-Host ""
    Write-Host "1/5 - Publicando GeoPackage no GeoServer..."
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
      "--header", "Content-Type: application/geopackage+vnd.sqlite3",
      "--upload-file", $gpkgPath,
      "$GeoServer/rest/workspaces/$Workspace/datastores/$Store/file.gpkg?configure=all"
    )
  }

  Write-Host ""
  Write-Host "2/5 - Ajustando titulo da camada..."
  $escapedLayerTitle = ConvertTo-XmlEscapedText -Text $GeoServerLayerTitle
  $featureTypeBody = @"
<?xml version="1.0" encoding="UTF-8"?>
<featureType>
  <title>$escapedLayerTitle</title>
</featureType>
"@
  $tmpFeatureTypeBody = New-TemporaryFile
  try {
    $utf8NoBom = New-Object Text.UTF8Encoding $false
    [IO.File]::WriteAllText($tmpFeatureTypeBody.FullName, $featureTypeBody, $utf8NoBom)
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
        "$GeoServer/rest/workspaces/$Workspace/datastores/$Store/featuretypes/$Layer"
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
}

if ($SkipCatalog) {
  Write-Host ""
  Write-Host "5/5 - Catalogo ignorado por parametro -SkipCatalog."
}
else {
  Write-Host ""
  Write-Host "5/5 - Importando XML no catalogo GeoNetwork..."
  Write-Host "Abrindo sessao e capturando token XSRF do GeoNetwork..."
  $metadataUploadPath = New-MetadataXmlWithDataDictionaryLink -XmlPath $xmlPath -DataDictionaryBaseUrl $DataDictionaryBaseUrl
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
        if ($modernOutput -match "(?is)<html|gnSearchSettings|catalog.search") {
          throw "GeoNetwork retornou HTML em vez de relatorio JSON de importacao."
        }
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
