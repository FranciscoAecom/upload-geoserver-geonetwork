$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "TestSupport.ps1")
$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $repoRoot "src\Naming.ps1")

$cCedilla = [char]0x00E7
$aTilde = [char]0x00E3
$aCircumflex = [char]0x00E2
$aAcute = [char]0x00E1
$expectedTitle = ("Pontos oficiais das sedes municipais e capitais com popula{0}{1}o urbana" -f $cCedilla, $aTilde)
$expectedDistTitle = ("Dist{0}ncia da {1}rea urbana das sedes municipais com popula{2}{3}o residente" -f $aCircumflex, $aAcute, $cCedilla, $aTilde)
$expectedDistRodNoTitle = ("Dist{0}ncia das rodovias n{1}o oficiais" -f $aCircumflex, $aTilde)
$rules = @(Get-LayerNamingRules)

Assert-True ($rules.Count -ge 12) "Catalogo deve conter as regras conhecidas"
Assert-Equal (Get-FriendlyLayerTitle -LayerName "pnt_soc_upl_20260602") $expectedTitle "Catalogo deve resolver camada UPL"
Assert-Equal (Get-FriendlyLayerTitle -LayerName "rst_gsi_dist_ufp_20260602") $expectedDistTitle "Catalogo deve resolver camada GSI DIST UFP"
Assert-Equal (Get-FriendlyLayerTitle -LayerName "rst_gsi_dist_rod_no_20260603") $expectedDistRodNoTitle "Catalogo deve resolver camada GSI DIST ROD NO"
Assert-Equal (Get-FriendlyLayerTitle -LayerName "camada_sem_regra") $null "Catalogo deve retornar nulo para camada desconhecida"

Write-Host "NAMING TESTS OK (5)"
