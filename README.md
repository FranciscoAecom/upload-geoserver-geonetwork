# Upload GeoServer / GeoNetwork

Scripts PowerShell para publicar camadas APP CAR no GeoServer e importar os metadados ISO 19139 no GeoNetwork.

O fluxo principal esta em `upload_iocasta_qas.ps1`. Ele localiza um arquivo de dados (`.gpkg`, `.rst` ou `.tif`), um SLD e um XML de metadados em uma pasta local, publica a camada no GeoServer, cria ou atualiza o estilo, associa o estilo a camada e importa o XML no catalogo GeoNetwork.

## Pre-requisitos

- Windows com PowerShell.
- `curl.exe` disponivel no PATH.
- Credenciais com permissao de escrita no GeoServer e no GeoNetwork.
- Pasta de entrada contendo exatamente:
  - 1 arquivo `.gpkg`, `.rst` ou `.tif`
  - 1 arquivo `.sld`
  - 1 arquivo `.xml`

Para os scripts auxiliares de figuras em `tools/`, tambem e necessario ter QGIS/GDAL instalado no caminho esperado pelos scripts.

## Comando para subir as bases

Para subir uma base APP CAR, abra o terminal PowerShell, entre na pasta do repositorio e execute:

```powershell
cd "C:\Temp\Repositórios\upload-geoserver-geonetwork"

.\upload_iocasta_qas.ps1 `
  -Folder "C:\Users\RibeiroF\Downloads\app_car_ba\SICAR\20260301\00" `
  -Workspace "gold" `
  -Store "pol_pcd_app_car_ba_20260301" `
  -Layer "pol_pcd_app_car_ba_20260301" `
  -SameCredentialForCatalog
```

Durante a execucao, o script solicita as credenciais via `Get-Credential`. As credenciais nao devem ser salvas no repositorio.

Para subir varias bases seguindo o mesmo padrao de UF e data:

```powershell
$data = "20260301"
$ufs = @("ac", "al", "am", "ap", "ba", "ce", "df", "es", "go", "ma", "mg", "ms", "mt", "pa", "pb", "pe", "pi", "pr", "rj", "rn", "ro", "rr", "rs", "sc", "se", "sp", "to")

foreach ($uf in $ufs) {
  $layer = "pol_pcd_app_car_${uf}_$data"

  .\upload_iocasta_qas.ps1 `
    -Folder "C:\Users\RibeiroF\Downloads\app_car_$uf\SICAR\$data\00" `
    -Workspace "gold" `
    -Store $layer `
    -Layer $layer `
    -SameCredentialForCatalog
}
```

Para bases IMB LULC / MapBiomas, o nome da camada segue uma regra propria porque o
script usa esse nome para gerar o titulo amigavel no GeoServer:

```text
rst_imb_lulc_AAAA...
```

Onde:

- `AAAA` e o ano da base.
- O sufixo depois do ano pode carregar a colecao e a versao/data usada no pacote de origem.
- Quando houver pelo menos 3 digitos depois do ano, o script interpreta os 3 primeiros como colecao.

Exemplo:

```text
rst_imb_lulc_20110101
```

Esse nome representa a base de 2011 da colecao 010 e gera o titulo:

```text
Uso e cobertura da terra de 2011 - Colecao 10
```

Se `Store` e `Layer` nao forem informados, o script usa automaticamente o nome do
arquivo de dados (`.gpkg`, `.rst` ou `.tif`) sem a extensao. Por isso, para esse
fluxo automatico funcionar, o arquivo de dados deve seguir a convencao de nome.

Exemplo:

```powershell
.\upload_iocasta_qas.ps1 `
  -Folder "L:\Secure_DCS\BRBLH1PINFW001\COE_Digital\coe_digital_data\silver_data\restricted\imb\uso_do_solo_2011\MapBiomas\20250815\00\teste" `
  -Workspace "gold" `
  -SameCredentialForCatalog
```

Nesse caso, se o arquivo de dados se chamar `rst_imb_lulc_20110101.tif`, o script
vai usar automaticamente:

```text
Store: rst_imb_lulc_20110101
Layer: rst_imb_lulc_20110101
```

## Parametros principais

| Parametro | Padrao | Descricao |
| --- | --- | --- |
| `Folder` | pasta local APP CAR BA | Pasta que contem o `.gpkg`, `.rst` ou `.tif`, `.sld` e `.xml`. |
| `GeoServer` | `https://gisqas.iocasta.com.br/geoserver` | URL base do GeoServer. |
| `Catalog` | `https://catalogqas.iocasta.com.br` | URL base do GeoNetwork. |
| `Workspace` | `gold` | Workspace de destino no GeoServer. |
| `Store` | nome do arquivo de dados | Nome do datastore/coveragestore no GeoServer. Se omitido, usa o nome do arquivo de dados sem extensao. |
| `Layer` | nome do arquivo de dados | Nome da camada publicada. Se omitido, usa o nome do arquivo de dados sem extensao. |
| `LayerTitle` | extraido do XML | Titulo usado no catalogo quando informado ou detectado. |
| `Style` | nome do arquivo SLD | Nome do estilo no GeoServer. |
| `CatalogGroup` | `2` | Grupo usado na importacao do GeoNetwork. |
| `CatalogCategory` | `2` | Categoria usada na importacao do GeoNetwork. |
| `DataDictionaryBaseUrl` | endpoint QAS | Base para inserir link do dicionario de dados no XML. |

## Opcoes de controle

- `-SameCredentialForCatalog`: reutiliza a credencial do GeoServer no GeoNetwork.
- `-SkipGeoServer`: ignora as etapas do GeoServer.
- `-SkipGeoPackage`: nao faz upload do arquivo de dados, mas continua ajustando titulo/estilo.
- `-SkipCatalog`: ignora a importacao no GeoNetwork.

## Fluxo executado

1. Valida a pasta de entrada e localiza os arquivos `.gpkg`, `.rst` ou `.tif`, `.sld` e `.xml`.
2. Publica o arquivo raster ou GeoPackage no GeoServer.
3. Ajusta o titulo da camada.
4. Cria ou atualiza o estilo SLD.
5. Associa o estilo como estilo padrao da camada.
6. Insere, quando possivel, o link do dicionario de dados no XML temporario.
7. Importa os metadados no GeoNetwork, tentando primeiro a API moderna e depois endpoints legados.

## Scripts auxiliares

### `tools/create_app_car_figures.ps1`

Gera imagens PNG no padrao de legenda do GeoServer para todos os estados.

```powershell
.\tools\create_app_car_figures.ps1 -OutputFolder "C:\Temp\figuras_app_car_geoserver"
```

### `tools/create_app_car_state_maps.ps1`

Gera miniaturas/mapas PNG por UF a partir dos GeoPackages APP CAR. O script usa ferramentas GDAL do QGIS e caminhos locais/rede configurados no proprio arquivo.

```powershell
.\tools\create_app_car_state_maps.ps1 `
  -OutputFolder "C:\Temp\figuras_app_car_mapas" `
  -States ba,sp,mg
```

## Observacoes

- O script imprime os comandos `curl.exe`, mascarando headers sensiveis como `Authorization` e `X-XSRF-TOKEN`.
- Arquivos temporarios sao criados durante a execucao e removidos ao final.
- Antes de executar para outro ambiente, revise `GeoServer`, `Catalog`, `Workspace`, `Store`, `Layer`, `CatalogGroup` e `CatalogCategory`.
