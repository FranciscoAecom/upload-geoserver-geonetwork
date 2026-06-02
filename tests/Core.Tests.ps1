$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "TestSupport.ps1")
$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $repoRoot "src\Core.ps1")

$cCedilla = [char]0x00E7
$aTilde = [char]0x00E3
$validUtf8Title = ("Popula{0}{1}o urbana" -f $cCedilla, $aTilde)
$mojibakeTitle = "Popula" + [char]0x00C3 + [char]0x00A7 + [char]0x00C3 + [char]0x00A3 + "o urbana"

Assert-Equal (Repair-Mojibake -Text $validUtf8Title) $validUtf8Title "Reparo deve preservar UTF-8 valido"
Assert-Equal (Repair-Mojibake -Text $mojibakeTitle) $validUtf8Title "Reparo deve corrigir mojibake conhecido"
Assert-Equal (Invoke-CurlCapture -Arguments @("--version") -DryRun $true -DryRunOutput "saida-teste") "saida-teste" "Curl capturado deve preservar saida simulada"

$jsonOutput = Invoke-CurlJson -Arguments @("--version") -JsonBody '{"ok":true}' -DryRun $true -CaptureOutput $true -DryRunOutput "json-teste"
Assert-Equal $jsonOutput "json-teste" "Helper JSON deve preservar saida simulada"

Write-Host "CORE TESTS OK (4)"
