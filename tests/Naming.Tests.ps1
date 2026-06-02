$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "TestSupport.ps1")
$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $repoRoot "src\Naming.ps1")

$cCedilla = [char]0x00E7
$aTilde = [char]0x00E3
$expectedTitle = ("Pontos oficiais das sedes municipais e capitais com popula{0}{1}o urbana" -f $cCedilla, $aTilde)
$rules = @(Get-LayerNamingRules)

Assert-True ($rules.Count -ge 10) "Catalogo deve conter as regras conhecidas"
Assert-Equal (Get-FriendlyLayerTitle -LayerName "pnt_soc_upl_20260602") $expectedTitle "Catalogo deve resolver camada UPL"
Assert-Equal (Get-FriendlyLayerTitle -LayerName "camada_sem_regra") $null "Catalogo deve retornar nulo para camada desconhecida"

Write-Host "NAMING TESTS OK (3)"
