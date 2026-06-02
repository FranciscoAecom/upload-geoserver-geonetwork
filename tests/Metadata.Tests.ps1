$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "TestSupport.ps1")
$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $repoRoot "src\Core.ps1")
. (Join-Path $repoRoot "src\Metadata.ps1")

$invalidDictionaryXml = "<root><data_dictionary><field><name>codigo</name></field><broken></data_dictionary></root>"
$output = @(Set-DataDictionaryFieldTypes -XmlContent $invalidDictionaryXml -AttributeTypes @{ codigo = "Integer64" } 3>&1)
$warnings = @($output | Where-Object { $_ -is [Management.Automation.WarningRecord] })
$result = @($output | Where-Object { $_ -is [hashtable] })[0]

Assert-Equal $result.Count 1 "Fallback regex deve atualizar campo conhecido"
Assert-True ($result.Content -like "*<type>Integer64</type>*") "Fallback regex deve inserir tipo"
Assert-True ($warnings.Count -gt 0) "Fallback regex deve emitir warning"

Write-Host "METADATA TESTS OK (3)"
