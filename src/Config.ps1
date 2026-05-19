$ErrorActionPreference = "Stop"

function Resolve-ConfigPath {
  param(
    [string]$ScriptRoot,
    [string]$Environment,
    [string]$ConfigPath
  )

  if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
    return (Resolve-Path -LiteralPath $ConfigPath).Path
  }

  return Join-Path $ScriptRoot ("config\{0}.psd1" -f $Environment)
}

function Import-PublishConfig {
  param(
    [string]$ScriptRoot,
    [string]$Environment = "qas",
    [string]$ConfigPath
  )

  $resolvedConfigPath = Resolve-ConfigPath -ScriptRoot $ScriptRoot -Environment $Environment -ConfigPath $ConfigPath
  if (-not (Test-Path -LiteralPath $resolvedConfigPath)) {
    throw "Arquivo de configuracao nao encontrado: $resolvedConfigPath"
  }

  $config = Import-PowerShellDataFile -LiteralPath $resolvedConfigPath
  $config.Path = $resolvedConfigPath
  $config.Environment = $Environment
  return $config
}

function Get-ConfigValue {
  param(
    [hashtable]$Config,
    [hashtable]$BoundParameters,
    [string]$Name,
    [object]$CurrentValue
  )

  if ($BoundParameters.ContainsKey($Name)) {
    return $CurrentValue
  }

  if ($Config.ContainsKey($Name)) {
    return $Config[$Name]
  }

  return $CurrentValue
}
