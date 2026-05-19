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

## Comando para subir as bases

Para subir uma base APP CAR, abra o terminal PowerShell, entre na pasta do repositorio e execute:

```powershell
cd "C:\Temp\Repositórios\upload-geoserver-geonetwork"

.\upload_iocasta_qas.ps1 `
  -Folder "C:\Users\RibeiroF\Downloads\app_car_ba\SICAR\20260301\00" `
  -Environment qas `
  -Workspace "gold" `
  -SameCredentialForCatalog
```

O nome da camada e do store e definido automaticamente a partir do nome do arquivo
de dados, sem a extensao. Por exemplo, se a pasta contem
`pol_pcd_app_car_ba_20260301.gpkg`, o script usa:

```text
Store: pol_pcd_app_car_ba_20260301
Layer: pol_pcd_app_car_ba_20260301
```

Durante a execucao, o script solicita as credenciais via `Get-Credential`. As credenciais nao devem ser salvas no repositorio.

Para subir varias bases seguindo o mesmo padrao de UF e data:

```powershell
$data = "20260301"
$ufs = @("ac", "al", "am", "ap", "ba", "ce", "df", "es", "go", "ma", "mg", "ms", "mt", "pa", "pb", "pe", "pi", "pr", "rj", "rn", "ro", "rr", "rs", "sc", "se", "sp", "to")

foreach ($uf in $ufs) {
  .\upload_iocasta_qas.ps1 `
    -Folder "C:\Users\RibeiroF\Downloads\app_car_$uf\SICAR\$data\00" `
    -Workspace "gold" `
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
Informe `Store` ou `Layer` apenas quando precisar publicar com um nome diferente
do arquivo de dados.

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
| `Store` | nome do arquivo de dados | Nome opcional do datastore/coveragestore no GeoServer. Use apenas quando precisar sobrescrever o nome derivado do arquivo. |
| `Layer` | nome do arquivo de dados | Nome opcional da camada publicada. Use apenas quando precisar sobrescrever o nome derivado do arquivo. |
| `LayerTitle` | extraido do XML | Titulo usado no catalogo quando informado ou detectado. |
| `Style` | nome do arquivo SLD | Nome do estilo no GeoServer. |
| `CatalogGroup` | `2` | Grupo usado na importacao do GeoNetwork. |
| `CatalogCategory` | `2` | Categoria usada na importacao do GeoNetwork. |
| `DataDictionaryBaseUrl` | endpoint QAS | Base para inserir link do dicionario de dados no XML. |
| `Environment` | `qas` | Nome do ambiente carregado de `config/<ambiente>.psd1`. |
| `ConfigPath` | vazio | Caminho opcional para um arquivo `.psd1` especifico. |

## Configuracao por ambiente

As URLs e valores de ambiente ficam em arquivos `.psd1` na pasta `config/`.
Por padrao, o script carrega `config/qas.psd1`.

```powershell
.\upload_iocasta_qas.ps1 `
  -Folder "C:\Users\RibeiroF\Downloads\app_car_ba\SICAR\20260301\00" `
  -Environment qas `
  -SameCredentialForCatalog
```

Tambem e possivel informar um arquivo diretamente:

```powershell
.\upload_iocasta_qas.ps1 `
  -Folder "C:\Users\RibeiroF\Downloads\app_car_ba\SICAR\20260301\00" `
  -ConfigPath ".\config\qas.psd1" `
  -SameCredentialForCatalog
```

Parametros passados na linha de comando sobrescrevem o arquivo de configuracao.
Por exemplo, `-Workspace silver` usa o restante do ambiente escolhido, mas publica
no workspace informado.

## Opcoes de controle

- `-SameCredentialForCatalog`: reutiliza a credencial do GeoServer no GeoNetwork.
- `-SkipGeoServer`: ignora as etapas do GeoServer.
- `-SkipGeoPackage`: nao faz upload do arquivo de dados, mas continua ajustando titulo/estilo.
- `-SkipCatalog`: ignora a importacao no GeoNetwork.
- `-DryRun`: mostra os comandos `curl.exe` que seriam executados, sem pedir credenciais e sem publicar nada.

Exemplo para conferir a publicacao antes de executar de verdade:

```powershell
.\upload_iocasta_qas.ps1 `
  -Folder "C:\Users\RibeiroF\Downloads\app_car_ba\SICAR\20260301\00" `
  -Workspace "gold" `
  -SameCredentialForCatalog `
  -DryRun
```

## Fluxo executado

1. Valida a pasta de entrada e localiza os arquivos `.gpkg`, `.rst` ou `.tif`, `.sld` e `.xml`.
2. Publica o arquivo raster ou GeoPackage no GeoServer.
3. Ajusta o titulo da camada.
4. Cria ou atualiza o estilo SLD.
5. Associa o estilo como estilo padrao da camada.
6. Insere, quando possivel, o link do dicionario de dados no XML temporario.
7. Importa os metadados no GeoNetwork, tentando primeiro a API moderna e depois endpoints legados.

## Estrutura do projeto

- `upload_iocasta_qas.ps1`: script de entrada e orquestracao do fluxo.
- `src/Core.ps1`: validacoes locais, credenciais, escaping e execucao de `curl.exe`.
- `src/Config.ps1`: carregamento dos arquivos `config/*.psd1` e aplicacao de overrides.
- `src/Naming.ps1`: regras de nomes e titulos amigaveis de camadas.
- `src/GeoServer.ps1`: leitura de tipos de atributos publicados no GeoServer.
- `src/GeoNetwork.ps1`: validacao das respostas de importacao do GeoNetwork.
- `src/Metadata.ps1`: leitura e ajuste do XML de metadados.
- `src/PublishContext.ps1`: consolidacao dos nomes, arquivos, tipo de dado, endpoint e titulos usados no fluxo.
- `src/Sld.ps1`: ajuste temporario do SLD antes do upload.
- `src/Urls.ps1`: montagem centralizada dos endpoints GeoServer e GeoNetwork.
- `config/qas.psd1`: configuracao padrao do ambiente QAS.
- `config/prod.psd1.example`: exemplo de configuracao para producao.
- `tests/Run-UnitTests.ps1`: testes locais das funcoes puras do fluxo.
- `.validate_parse_upload.ps1`: validacao sintatica dos scripts PowerShell.

## Validacao local

Para validar a sintaxe dos scripts:

```powershell
.\.validate_parse_upload.ps1
```

Para executar os testes locais:

```powershell
.\tests\Run-UnitTests.ps1
```

## Observacoes

- O script imprime os comandos `curl.exe`, mascarando headers sensiveis como `Authorization` e `X-XSRF-TOKEN`.
- Arquivos temporarios sao criados durante a execucao e removidos ao final.
- Antes de executar para outro ambiente, revise `GeoServer`, `Catalog`, `Workspace`, `CatalogGroup` e `CatalogCategory`. Use `Store` e `Layer` somente quando o nome publicado precisar ser diferente do arquivo de dados.
