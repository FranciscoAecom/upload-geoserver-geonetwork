$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $repoRoot "src\Core.ps1")
. (Join-Path $repoRoot "src\Naming.ps1")
. (Join-Path $repoRoot "src\Metadata.ps1")
. (Join-Path $repoRoot "src\PublishContext.ps1")
. (Join-Path $repoRoot "src\GeoNetwork.ps1")

$script:testCount = 0

function Assert-Equal {
  param(
    [object]$Actual,
    [object]$Expected,
    [string]$Message
  )

  $script:testCount++
  if ($Actual -ne $Expected) {
    throw "$Message. Esperado: '$Expected'. Recebido: '$Actual'."
  }
}

function Assert-True {
  param(
    [bool]$Condition,
    [string]$Message
  )

  $script:testCount++
  if (-not $Condition) {
    throw $Message
  }
}

function Assert-Throws {
  param(
    [scriptblock]$ScriptBlock,
    [string]$Message
  )

  $script:testCount++
  try {
    & $ScriptBlock
  }
  catch {
    return
  }

  throw $Message
}

function New-TestMetadataXml {
  param(
    [string]$Path,
    [string]$Title = "Titulo Teste",
    [string]$Uuid = "uuid-teste"
  )

  $content = @"
<?xml version="1.0" encoding="UTF-8"?>
<gmd:MD_Metadata xmlns:gmd="http://www.isotc211.org/2005/gmd" xmlns:gco="http://www.isotc211.org/2005/gco">
  <gmd:fileIdentifier>
    <gco:CharacterString>$Uuid</gco:CharacterString>
  </gmd:fileIdentifier>
  <gmd:identificationInfo>
    <gmd:MD_DataIdentification>
      <gmd:citation>
        <gmd:CI_Citation>
          <gmd:title>
            <gco:CharacterString>$Title</gco:CharacterString>
          </gmd:title>
        </gmd:CI_Citation>
      </gmd:citation>
    </gmd:MD_DataIdentification>
  </gmd:identificationInfo>
</gmd:MD_Metadata>
"@

  $utf8NoBom = New-Object Text.UTF8Encoding $false
  [IO.File]::WriteAllText($Path, $content, $utf8NoBom)
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("upload_unit_tests_{0}" -f ([guid]::NewGuid()))
New-Item -ItemType Directory -Path $tempRoot | Out-Null

try {
  $aAcuteUpper = [char]0x00C1
  $cCedilla = [char]0x00E7
  $aTilde = [char]0x00E3
  $oAcute = [char]0x00F3
  $expectedAppCarTitle = ("{0}rea de Preserva{1}{2}o Permanente - Im{3}veis Bahia" -f $aAcuteUpper, $cCedilla, $aTilde, $oAcute)
  $expectedImbLulcTitle = ("Uso e cobertura da terra de 2011 - Cole{0}{1}o 10" -f $cCedilla, $aTilde)

  Assert-Equal (Get-StateNameFromLayer -LayerName "pol_pcd_app_car_ba_20260301") "Bahia" "Deve identificar UF pelo nome da camada"
  Assert-Equal (Get-AppCarLayerTitle -LayerName "pol_pcd_app_car_ba_20260301") $expectedAppCarTitle "Deve montar titulo APP CAR"
  Assert-Equal (Get-ImbLulcLayerTitle -LayerName "rst_imb_lulc_20110101") $expectedImbLulcTitle "Deve montar titulo IMB LULC com colecao"

  $inputFolder = Join-Path $tempRoot "input"
  New-Item -ItemType Directory -Path $inputFolder | Out-Null
  $dataPath = Join-Path $inputFolder "pol_pcd_app_car_ba_20260301.gpkg"
  $sldPath = Join-Path $inputFolder "style.sld"
  $xmlPath = Join-Path $inputFolder "metadata.xml"
  New-Item -ItemType File -Path $dataPath | Out-Null
  Set-Content -LiteralPath $sldPath -Value "<StyledLayerDescriptor />" -Encoding UTF8
  New-TestMetadataXml -Path $xmlPath

  Assert-Equal (Resolve-RequiredDataFile -Path $inputFolder) $dataPath "Deve localizar arquivo de dados unico"
  Assert-Equal (Resolve-RequiredFile -Path $inputFolder -Pattern "*.sld") $sldPath "Deve localizar SLD unico"
  Assert-Equal (Resolve-RequiredMetadataFile -Path $inputFolder) $xmlPath "Deve localizar XML de metadados unico"

  $dataInfo = Get-DataPublishInfo -DataPath $dataPath
  Assert-Equal $dataInfo.Type "gpkg" "Deve mapear gpkg para tipo de publicacao"
  Assert-Equal $dataInfo.Endpoint "datastores" "Deve publicar gpkg em datastores"
  Assert-Equal $dataInfo.LayerResource "featuretypes" "Deve mapear gpkg para featuretypes"

  $tifInfo = Get-DataPublishInfo -DataPath (Join-Path $inputFolder "rst_imb_lulc_20220101.tif")
  Assert-Equal $tifInfo.Type "geotiff" "Deve mapear tif para geotiff"
  Assert-Equal $tifInfo.Endpoint "coveragestores" "Deve publicar tif em coveragestores"
  Assert-Throws { Get-DataPublishInfo -DataPath (Join-Path $inputFolder "arquivo.zip") } "Deve rejeitar extensao nao suportada"

  Assert-Equal (Get-MetadataTitle -XmlPath $xmlPath) "Titulo Teste" "Deve ler titulo do XML"
  Assert-Equal (Get-MetadataUuid -XmlPath $xmlPath) "uuid-teste" "Deve ler UUID do XML"

  $context = New-PublishContext -DataPath $dataPath -SldPath $sldPath -XmlPath $xmlPath
  Assert-Equal $context.Store "pol_pcd_app_car_ba_20260301" "Contexto deve derivar store do arquivo"
  Assert-Equal $context.Layer "pol_pcd_app_car_ba_20260301" "Contexto deve derivar layer do arquivo"
  Assert-Equal $context.Style "style" "Contexto deve derivar estilo do SLD"
  Assert-Equal $context.LayerTitle "Titulo Teste" "Contexto deve usar titulo do XML"
  Assert-Equal $context.GeoServerLayerTitle $expectedAppCarTitle "Contexto deve usar titulo amigavel no GeoServer"

  $dictionaryXml = @"
<root>
  <data_dictionary>
    <field>
      <name>codigo</name>
    </field>
  </data_dictionary>
</root>
"@
  $dictionaryResult = Set-DataDictionaryFieldTypes -XmlContent $dictionaryXml -AttributeTypes @{ codigo = "Integer64" }
  Assert-Equal $dictionaryResult.Count 1 "Deve inserir tipo no dicionario de dados"
  Assert-True ($dictionaryResult.Content -like "*<type>Integer64</type>*") "XML atualizado deve conter tipo inserido"

  Assert-Throws { Assert-GeoNetworkModernImportSucceeded -Output "" } "Deve rejeitar resposta vazia do GeoNetwork"
  Assert-Throws { Assert-GeoNetworkModernImportSucceeded -Output "<html></html>" } "Deve rejeitar HTML do GeoNetwork"
  Assert-Throws { Assert-GeoNetworkModernImportSucceeded -Output '{"errors":["falha"]}' } "Deve rejeitar relatorio com erros"
  Assert-GeoNetworkModernImportSucceeded -Output '{"success":true,"records":[{"uuid":"abc"}]}'
  $script:testCount++

  Write-Host "UNIT TESTS OK ($script:testCount)"
}
finally {
  Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
