$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $repoRoot "src\Core.ps1")
. (Join-Path $repoRoot "src\Config.ps1")
. (Join-Path $repoRoot "src\Naming.ps1")
. (Join-Path $repoRoot "src\Metadata.ps1")
. (Join-Path $repoRoot "src\PublishContext.ps1")
. (Join-Path $repoRoot "src\Sld.ps1")
. (Join-Path $repoRoot "src\Urls.ps1")
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
  $expectedAutosInfracaoTitle = ("Autos de Infra{0}{1}o" -f $cCedilla, $aTilde)
  $expectedAutosInfracaoBrasilTitle = ("Autos de Infra{0}{1}o - Brasil" -f $cCedilla, $aTilde)
  $expectedAutosInfracaoBboxTitle = ("Autos de Infra{0}{1}o - BBox Brasil" -f $cCedilla, $aTilde)

  Assert-Equal (Get-StateNameFromLayer -LayerName "pol_pcd_app_car_ba_20260301") "Bahia" "Deve identificar UF pelo nome da camada"
  Assert-Equal (Get-AppCarLayerTitle -LayerName "pol_pcd_app_car_ba_20260301") $expectedAppCarTitle "Deve montar titulo APP CAR"
  Assert-Equal (Get-ImbLulcLayerTitle -LayerName "rst_imb_lulc_20110101") $expectedImbLulcTitle "Deve montar titulo IMB LULC com colecao"
  Assert-Equal (Get-AutosInfracaoLayerTitle -LayerName "pnt_pcd_enov_20260514") $expectedAutosInfracaoTitle "Deve montar titulo de autos de infracao"
  Assert-Equal (Get-AutosInfracaoLayerTitle -LayerName "pnt_pcd_enov_brasil_20260514") $expectedAutosInfracaoBrasilTitle "Deve montar titulo de autos de infracao Brasil"
  Assert-Equal (Get-AutosInfracaoLayerTitle -LayerName "pnt_pcd_enov_bbox_brasil_20260514") $expectedAutosInfracaoBboxTitle "Deve montar titulo de autos de infracao com bbox Brasil"

  $configPath = Join-Path $tempRoot "test.psd1"
  Set-Content -LiteralPath $configPath -Value @"
@{
  GeoServer = 'https://gis-test/geoserver'
  Catalog = 'https://catalog-test'
  Workspace = 'silver'
  CatalogGroup = '9'
  CatalogCategory = '8'
  DataDictionaryBaseUrl = 'https://etl-test/get_geonetwork_data_dict'
}
"@ -Encoding UTF8
  $config = Import-PublishConfig -ScriptRoot $repoRoot -Environment "test" -ConfigPath $configPath
  Assert-Equal $config.GeoServer "https://gis-test/geoserver" "Deve carregar GeoServer do config"
  Assert-Equal $config.Workspace "silver" "Deve carregar Workspace do config"
  Assert-Equal (Get-ConfigValue -Config $config -BoundParameters @{} -Name "CatalogGroup" -CurrentValue "2") "9" "Config deve preencher parametro nao informado"
  Assert-Equal (Get-ConfigValue -Config $config -BoundParameters @{ CatalogGroup = "2" } -Name "CatalogGroup" -CurrentValue "2") "2" "Parametro informado deve sobrescrever config"

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

  $complexSldPath = Join-Path $tempRoot "complex.sld"
  $complexSld = @'
<?xml version="1.0" encoding="UTF-8"?>
<StyledLayerDescriptor xmlns="http://www.opengis.net/sld" xmlns:ogc="http://www.opengis.net/ogc" version="1.0.0">
  <NamedLayer>
    <Name>camada_original</Name>
    <UserStyle>
      <Name>estilo_original</Name>
      <FeatureTypeStyle>
        <Rule>
          <PolygonSymbolizer>
            <Fill>
              <CssParameter name="fill">#F2CA27</CssParameter>
              <CssParameter name="fill-opacity"><![CDATA[0.65]]></CssParameter>
            </Fill>
            <Stroke>
              <CssParameter name="stroke">#0066CC</CssParameter>
            </Stroke>
          </PolygonSymbolizer>
        </Rule>
      </FeatureTypeStyle>
    </UserStyle>
  </NamedLayer>
</StyledLayerDescriptor>
'@
  $utf8NoBom = New-Object Text.UTF8Encoding $false
  [IO.File]::WriteAllText($complexSldPath, $complexSld, $utf8NoBom)
  $sldUploadPath = New-SldWithStyleName -SldPath $complexSldPath -StyleName "novo_estilo" -LayerName "nova_camada"
  try {
    $originalSldBytes = [Convert]::ToBase64String([IO.File]::ReadAllBytes($complexSldPath))
    $uploadSldBytes = [Convert]::ToBase64String([IO.File]::ReadAllBytes($sldUploadPath))
    Assert-Equal $uploadSldBytes $originalSldBytes "SLD de upload deve preservar bytes, cores e CDATA originais"
  }
  finally {
    Remove-Item -LiteralPath $sldUploadPath -Force -ErrorAction SilentlyContinue
  }
  Assert-Equal (Get-SldContentType -SldPath $complexSldPath) "application/vnd.ogc.sld+xml" "SLD 1.0 deve usar content type SLD"

  $seSldPath = Join-Path $tempRoot "se.sld"
  $seSld = @'
<?xml version="1.0" encoding="UTF-8"?>
<StyledLayerDescriptor xmlns="http://www.opengis.net/sld" version="1.1.0" xmlns:se="http://www.opengis.net/se">
  <NamedLayer>
    <se:Name>pnt_pcd_enov_brasil_20260514</se:Name>
    <UserStyle>
      <se:Name>pnt_pcd_enov_brasil_20260514</se:Name>
      <se:FeatureTypeStyle>
        <se:Rule>
          <se:PointSymbolizer>
            <se:Graphic>
              <se:Mark>
                <se:WellKnownName>circle</se:WellKnownName>
                <se:Fill>
                  <se:SvgParameter name="fill">#1654ad</se:SvgParameter>
                </se:Fill>
              </se:Mark>
            </se:Graphic>
          </se:PointSymbolizer>
        </se:Rule>
      </se:FeatureTypeStyle>
    </UserStyle>
  </NamedLayer>
</StyledLayerDescriptor>
'@
  [IO.File]::WriteAllText($seSldPath, $seSld, $utf8NoBom)
  Assert-Equal (Get-SldContentType -SldPath $seSldPath) "application/vnd.ogc.se+xml" "SLD 1.1/SE deve usar content type SE"

  $dictionaryUrl = "https://etlapiqas.iocasta.com.br/get_geonetwork_data_dict?key=uuid-teste"
  $metadataWithEmptyContactUrlAndPlaceholder = @"
<root>
  <contact>
    <gmd:URL/>
  </contact>
  <distribution>
    <gmd:URL>Estrutura de 2 link associado</gmd:URL>
  </distribution>
</root>
"@
  $linkResult = Add-DataDictionaryLink -XmlContent $metadataWithEmptyContactUrlAndPlaceholder -DictionaryUrl $dictionaryUrl
  Assert-True $linkResult.Inserted "Deve inserir link do dicionario quando houver placeholder"
  Assert-True ($linkResult.Content -like "*<contact>*<gmd:URL/>*</contact>*") "Nao deve usar URL vazia de contato antes do placeholder"
  Assert-True ($linkResult.Content -like "*<distribution>*<gmd:URL>https://etlapiqas.iocasta.com.br/get_geonetwork_data_dict?key=uuid-teste</gmd:URL>*</distribution>*") "Deve inserir link no placeholder de distribuicao"

  $sourceUrl = "https://www.ibge.gov.br/geociencias/organizacao-do-territorio/estrutura-territorial/27385-localidades.html"
  $metadataWithEmptyQualitySourceUrl = @"
<gmd:MD_Metadata xmlns:gmd="http://www.isotc211.org/2005/gmd" xmlns:gco="http://www.isotc211.org/2005/gco">
  <gmd:dataQualityInfo>
    <gmd:DQ_DataQuality>
      <gmd:lineage>
        <gmd:LI_Lineage>
          <gmd:source>
            <gmd:LI_Source>
              <gmd:sourceCitation>
                <gmd:CI_Citation>
                  <gmd:onlineResource>
                    <gmd:CI_OnlineResource>
                      <gmd:linkage>
                        <gmd:URL/>
                      </gmd:linkage>
                    </gmd:CI_OnlineResource>
                  </gmd:onlineResource>
                </gmd:CI_Citation>
              </gmd:sourceCitation>
            </gmd:LI_Source>
          </gmd:source>
        </gmd:LI_Lineage>
      </gmd:lineage>
    </gmd:DQ_DataQuality>
  </gmd:dataQualityInfo>
</gmd:MD_Metadata>
"@
  $sourceLinkResult = Add-QualitySourceLink -XmlContent $metadataWithEmptyQualitySourceUrl -SourceUrl $sourceUrl
  Assert-True $sourceLinkResult.Inserted "Deve inserir link da fonte na qualidade quando houver URL vazia em sourceCitation"
  Assert-True ($sourceLinkResult.Content -like "*<gmd:sourceCitation>*<gmd:CI_Citation>*<gmd:onlineResource>*<gmd:CI_OnlineResource>*<gmd:linkage>*<gmd:URL>$sourceUrl</gmd:URL>*") "XML atualizado deve conter link da fonte em qualidade"

  $metadataWithQualitySourceNoOnlineResource = @"
<gmd:MD_Metadata xmlns:gmd="http://www.isotc211.org/2005/gmd" xmlns:gco="http://www.isotc211.org/2005/gco">
  <gmd:dataQualityInfo>
    <gmd:DQ_DataQuality>
      <gmd:lineage>
        <gmd:LI_Lineage>
          <gmd:source>
            <gmd:LI_Source>
            </gmd:LI_Source>
          </gmd:source>
        </gmd:LI_Lineage>
      </gmd:lineage>
    </gmd:DQ_DataQuality>
  </gmd:dataQualityInfo>
</gmd:MD_Metadata>
"@
  $createdSourceLinkResult = Add-QualitySourceLink -XmlContent $metadataWithQualitySourceNoOnlineResource -SourceUrl $sourceUrl
  Assert-True $createdSourceLinkResult.Inserted "Deve criar onlineResource da fonte quando a qualidade ja possui lineage/source"
  Assert-True ($createdSourceLinkResult.Content -like "*<gmd:sourceCitation><gmd:CI_Citation><gmd:onlineResource><gmd:CI_OnlineResource><gmd:linkage><gmd:URL>$sourceUrl</gmd:URL>*") "XML atualizado deve criar estrutura de link da fonte"

  $context = New-PublishContext -DataPath $dataPath -SldPath $sldPath -XmlPath $xmlPath
  Assert-Equal $context.Store "pol_pcd_app_car_ba_20260301" "Contexto deve derivar store do arquivo"
  Assert-Equal $context.Layer "pol_pcd_app_car_ba_20260301" "Contexto deve derivar layer do arquivo"
  Assert-Equal $context.Style "style" "Contexto deve derivar estilo do SLD"
  Assert-Equal $context.LayerTitle "Titulo Teste" "Contexto deve usar titulo do XML"
  Assert-Equal $context.GeoServerLayerTitle $expectedAppCarTitle "Contexto deve usar titulo amigavel no GeoServer"

  Assert-Equal (Resolve-GeoServerLayerTitle -Layer "pnt_pcd_enov_20260514" -LayerTitle "Titulo XML") $expectedAutosInfracaoTitle "Contexto deve usar titulo amigavel para autos de infracao"
  Assert-Equal (Resolve-GeoServerLayerTitle -Layer "pnt_pcd_enov_brasil_20260514" -LayerTitle "Titulo XML") $expectedAutosInfracaoBrasilTitle "Contexto deve usar titulo amigavel para autos de infracao Brasil"

  Assert-Equal (Join-UrlPath -BaseUrl "https://server/base/" -Segments @("/a/", "b")) "https://server/base/a/b" "Deve juntar segmentos de URL sem duplicar barras"
  Assert-Equal (Get-GeoServerDataUploadUrl -GeoServer "https://gis/geoserver" -Workspace "gold" -DataEndpoint "datastores" -Store "store1" -DataType "gpkg") "https://gis/geoserver/rest/workspaces/gold/datastores/store1/file.gpkg?configure=all" "Deve montar URL de upload GeoServer"
  Assert-Equal (Get-GeoServerLayerJsonUrl -GeoServer "https://gis/geoserver" -Workspace "gold" -Layer "layer1") "https://gis/geoserver/rest/layers/gold:layer1.json" "Deve montar URL JSON da camada"
  Assert-Equal (Get-GeoNetworkMeUrl -Catalog "https://catalog") "https://catalog/srv/api/me" "Deve montar URL /me do GeoNetwork"
  $recordsImportUrls = Get-GeoNetworkRecordsImportUrls -Catalog "https://catalog" -CatalogGroup "2" -CatalogCategory "3"
  Assert-Equal $recordsImportUrls[0] "https://catalog/srv/api/records?metadataType=METADATA&uuidProcessing=OVERWRITE&group=2&category=3&rejectIfInvalid=false&publishToAll=true&transformWith=_none_&schema=iso19139&allowEditGroupMembers=true" "Deve montar URL moderna de importacao"
  Assert-Equal $recordsImportUrls[1] "https://catalog/srv/api/records/?metadataType=METADATA&uuidProcessing=OVERWRITE&group=2&category=3&rejectIfInvalid=false&publishToAll=true&transformWith=_none_&schema=iso19139&allowEditGroupMembers=true" "Deve manter variante moderna com barra final"

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

  $dictionaryWithExistingType = @"
<root>
  <data_dictionary>
    <field>
      <name>area</name>
      <type>String</type>
    </field>
  </data_dictionary>
</root>
"@
  $existingTypeResult = Set-DataDictionaryFieldTypes -XmlContent $dictionaryWithExistingType -AttributeTypes @{ area = "Real" }
  Assert-Equal $existingTypeResult.Count 1 "Deve atualizar tipo existente no dicionario"
  Assert-True ($existingTypeResult.Content -like "*<type>Real</type>*") "XML atualizado deve substituir tipo antigo"

  $dictionaryWithAliases = @"
<root>
  <data_dictionary>
    <field>
      <name>cod_imovel</name>
    </field>
    <field>
      <name>municipio</name>
    </field>
    <field>
      <name>sem_tipo</name>
    </field>
  </data_dictionary>
</root>
"@
  $aliasResult = Set-DataDictionaryFieldTypes -XmlContent $dictionaryWithAliases -AttributeTypes @{
    "sdb_cod_imovel" = "String"
    "cadastro_municipio" = "String"
  }
  Assert-Equal $aliasResult.Count 2 "Deve atualizar campos por prefixo sdb_ e sufixo unico"
  Assert-True ($aliasResult.Content -like "*<name>cod_imovel</name>*<type>String</type>*") "XML atualizado deve conter tipo para campo com sdb_"
  Assert-True ($aliasResult.Content -like "*<name>municipio</name>*<type>String</type>*") "XML atualizado deve conter tipo para campo por sufixo"

  $noDictionaryXml = "<root><field><name>codigo</name></field></root>"
  $noDictionaryResult = Set-DataDictionaryFieldTypes -XmlContent $noDictionaryXml -AttributeTypes @{ codigo = "Integer64" }
  Assert-Equal $noDictionaryResult.Count 0 "Nao deve alterar XML sem data_dictionary"
  Assert-Equal $noDictionaryResult.Content $noDictionaryXml "XML sem data_dictionary deve permanecer igual"

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
