$ErrorActionPreference = "Stop"

function Test-MeaningfulGeoNetworkErrorValue {
  param([object]$Value)

  if ($null -eq $Value) {
    return $false
  }

  if ($Value -is [bool]) {
    return $Value
  }

  if ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal]) {
    return $Value -ne 0
  }

  if ($Value -is [string]) {
    return -not [string]::IsNullOrWhiteSpace($Value)
  }

  if ($Value -is [array]) {
    return $Value.Count -gt 0
  }

  if ($Value -is [pscustomobject]) {
    return @($Value.PSObject.Properties).Count -gt 0
  }

  return $true
}

function Assert-GeoNetworkModernImportSucceeded {
  param([string]$Output)

  if ([string]::IsNullOrWhiteSpace($Output)) {
    throw "GeoNetwork retornou resposta vazia para a importacao."
  }

  if ($Output -match "(?is)<html|gnSearchSettings|catalog.search") {
    throw "GeoNetwork retornou HTML em vez de relatorio JSON de importacao."
  }

  try {
    $json = $Output | ConvertFrom-Json
  }
  catch {
    throw "GeoNetwork retornou uma resposta que nao e JSON valido: $Output"
  }

  $queue = New-Object System.Collections.Queue
  $queue.Enqueue($json)
  while ($queue.Count -gt 0) {
    $current = $queue.Dequeue()
    if ($null -eq $current) {
      continue
    }

    if ($current -is [array]) {
      foreach ($item in $current) {
        $queue.Enqueue($item)
      }
      continue
    }

    if ($current -isnot [pscustomobject]) {
      continue
    }

    foreach ($property in $current.PSObject.Properties) {
      $name = $property.Name
      $value = $property.Value

      if ($name -match "(?i)^(success|successful)$" -and $value -is [bool] -and -not $value) {
        throw "GeoNetwork indicou falha no relatorio de importacao: $Output"
      }

      if ($name -match "(?i)(error|errors|exception|rejected|failed|failure|invalid)" -and (Test-MeaningfulGeoNetworkErrorValue -Value $value)) {
        throw "GeoNetwork indicou erro no relatorio de importacao: $Output"
      }

      if ($value -is [array] -or $value -is [pscustomobject]) {
        $queue.Enqueue($value)
      }
    }
  }
}

