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

function New-GeoNetworkGroupEditingSharingJson {
  param([string]$CatalogGroup)

  return @{
    clear = $false
    privileges = @(
      @{
        group = [int]$CatalogGroup
        operations = @{
          view = $true
          editing = $true
          download = $true
          notify = $true
          dynamic = $true
        }
      }
    )
  } | ConvertTo-Json -Depth 5 -Compress
}

function New-GeoNetworkSession {
  param(
    [string]$Catalog,
    [pscredential]$GeoCredential,
    [bool]$SameCredentialForCatalog,
    [bool]$DryRun = $false
  )

  Write-Host "Abrindo sessao e capturando token XSRF do GeoNetwork..."
  $catalogCredential = $null
  $catalogAuth = "DRYRUN"
  if ($DryRun) {
    Write-Host "DRY-RUN: credenciais do Catalogo/GeoNetwork nao solicitadas."
  }
  else {
    if ($SameCredentialForCatalog -and $null -ne $GeoCredential) {
      $catalogCredential = $GeoCredential
    }
    else {
      $catalogCredential = Get-Credential -Message "Credenciais do Catalogo QAS / GeoNetwork"
    }
    $catalogAuth = ConvertTo-BasicAuth -Credential $catalogCredential
  }

  $cookieJar = New-TemporaryFile
  try {
    Invoke-Curl -Arguments @(
      "--fail-with-body",
      "--show-error",
      "--location",
      "--retry", "5",
      "--retry-delay", "15",
      "--connect-timeout", "60",
      "--max-time", "0",
      "--cookie-jar", $cookieJar.FullName,
      "--cookie", $cookieJar.FullName,
      "--header", "Authorization: Basic $catalogAuth",
      "--header", "Accept: application/json",
      (Get-GeoNetworkMeUrl -Catalog $Catalog)
    ) -DryRun $DryRun

    if ($DryRun) {
      $xsrfToken = "DRYRUN-XSRF-TOKEN"
    }
    else {
      $xsrfToken = Get-CookieValue -CookieJar $cookieJar.FullName -CookieName "XSRF-TOKEN"
    }
    if ([string]::IsNullOrWhiteSpace($xsrfToken)) {
      throw "Nao foi possivel obter XSRF-TOKEN do GeoNetwork em $(Get-GeoNetworkMeUrl -Catalog $Catalog)."
    }

    return [pscustomobject]@{
      Auth = $catalogAuth
      XsrfToken = $xsrfToken
      CookieJar = $cookieJar.FullName
    }
  }
  catch {
    Remove-Item -LiteralPath $cookieJar.FullName -Force -ErrorAction SilentlyContinue
    throw
  }
}

function Remove-GeoNetworkSession {
  param([pscustomobject]$Session)

  if ($null -ne $Session -and -not [string]::IsNullOrWhiteSpace($Session.CookieJar)) {
    Remove-Item -LiteralPath $Session.CookieJar -Force -ErrorAction SilentlyContinue
  }
}

function Set-GeoNetworkGroupEditingPrivilege {
  param(
    [string]$Catalog,
    [string]$MetadataUuid,
    [string]$CatalogGroup,
    [string]$CatalogAuth,
    [string]$XsrfToken,
    [string]$CookieJar,
    [bool]$DryRun = $false
  )

  if ([string]::IsNullOrWhiteSpace($MetadataUuid)) {
    Write-Warning "Nao foi possivel identificar o UUID do XML; permissao de edicao do grupo nao foi reforcada."
    return
  }

  $sharingUrl = Get-GeoNetworkRecordSharingUrl -Catalog $Catalog -MetadataUuid $MetadataUuid
  $sharingJson = New-GeoNetworkGroupEditingSharingJson -CatalogGroup $CatalogGroup

  Write-Host ""
  Write-Host "Garantindo permissao de edicao do grupo $CatalogGroup no GeoNetwork..."
  Invoke-CurlJson -JsonBody $sharingJson -Arguments @(
    "--fail-with-body",
    "--show-error",
    "--location",
    "--retry", "0",
    "--connect-timeout", "60",
    "--max-time", "0",
    "--request", "PUT",
    "--cookie-jar", $CookieJar,
    "--cookie", $CookieJar,
    "--header", "Authorization: Basic $CatalogAuth",
    "--header", "X-XSRF-TOKEN: $XsrfToken",
    "--header", "Accept: application/json",
    $sharingUrl
  ) -DryRun $DryRun
}

function Import-GeoNetworkMetadata {
  param(
    [string]$Catalog,
    [string]$XmlPath,
    [string]$DataDictionaryBaseUrl,
    [hashtable]$AttributeTypes,
    [string]$QualitySourceUrl,
    [string]$CatalogGroup,
    [string]$CatalogCategory,
    [pscredential]$GeoCredential,
    [bool]$SameCredentialForCatalog,
    [bool]$DryRun = $false
  )

  Write-PublishStep -Step "5/5" -Message "Importando XML no catalogo GeoNetwork..."
  $metadataUploadPath = New-MetadataXmlWithDataDictionaryLink -XmlPath $XmlPath -DataDictionaryBaseUrl $DataDictionaryBaseUrl -AttributeTypes $AttributeTypes -QualitySourceUrl $QualitySourceUrl
  $session = $null

  try {
    $session = New-GeoNetworkSession -Catalog $Catalog -GeoCredential $GeoCredential -SameCredentialForCatalog $SameCredentialForCatalog -DryRun $DryRun

    $metadataUuid = Get-MetadataUuid -XmlPath $metadataUploadPath
    $recordsImportUrls = Get-GeoNetworkRecordsImportUrls -Catalog $Catalog -CatalogGroup $CatalogGroup -CatalogCategory $CatalogCategory

    try {
      $modernSuccess = $false
      $modernErrors = @()
      foreach ($recordsImportUrl in $recordsImportUrls) {
        if ($modernSuccess) {
          continue
        }

        Write-Host ""
        Write-Host "Tentando importacao moderna em $recordsImportUrl"
        try {
          $modernOutput = Invoke-CurlCapture -Arguments @(
            "--fail-with-body",
            "--show-error",
            "--location",
            "--retry", "0",
            "--connect-timeout", "60",
            "--max-time", "0",
            "--request", "POST",
            "--cookie-jar", $session.CookieJar,
            "--cookie", $session.CookieJar,
            "--header", "Authorization: Basic $($session.Auth)",
            "--header", "X-XSRF-TOKEN: $($session.XsrfToken)",
            "--header", "Accept: application/json",
            "--form", "file=@$metadataUploadPath;type=application/xml",
            $recordsImportUrl
          ) -DryRun $DryRun -DryRunOutput '{"success":true}'
          Assert-GeoNetworkModernImportSucceeded -Output $modernOutput
          $modernSuccess = $true
        }
        catch {
          $modernErrors += "$recordsImportUrl -> $($_.Exception.Message)"
          Write-Warning "Falhou em $recordsImportUrl"
        }
      }

      if (-not $modernSuccess) {
        throw "Tentativas modernas falharam: $($modernErrors -join ' | ')"
      }
    }
    catch {
      Write-Warning "Importacao pela API moderna falhou; tentando endpoints legados. Detalhe: $($_.Exception.Message)"
      $legacyEndpoints = Get-GeoNetworkLegacyImportUrls -Catalog $Catalog

      $legacySuccess = $false
      $legacyErrors = @()
      foreach ($legacyEndpoint in $legacyEndpoints) {
        if ($legacySuccess) {
          continue
        }

        Write-Host ""
        Write-Host "Tentando importacao legada em $legacyEndpoint"
        try {
          Invoke-Curl -Arguments @(
            "--fail-with-body",
            "--show-error",
            "--retry", "0",
            "--connect-timeout", "60",
            "--max-time", "0",
            "--request", "POST",
            "--cookie-jar", $session.CookieJar,
            "--cookie", $session.CookieJar,
            "--header", "Authorization: Basic $($session.Auth)",
            "--header", "X-XSRF-TOKEN: $($session.XsrfToken)",
            "--form", "data=<$metadataUploadPath",
            "--form", "group=$CatalogGroup",
            "--form", "category=$CatalogCategory",
            "--form", "styleSheet=_none_",
            "--form", "uuidAction=overwrite",
            "--form", "isTemplate=n",
            "--form", "validate=off",
            $legacyEndpoint
          ) -DryRun $DryRun
          $legacySuccess = $true
        }
        catch {
          $legacyErrors += "$legacyEndpoint -> $($_.Exception.Message)"
          Write-Warning "Falhou em $legacyEndpoint"
        }
      }

      if (-not $legacySuccess) {
        throw "Nao foi possivel importar no GeoNetwork. Tentativas: $($legacyErrors -join ' | ')"
      }
    }

    Set-GeoNetworkGroupEditingPrivilege `
      -Catalog $Catalog `
      -MetadataUuid $metadataUuid `
      -CatalogGroup $CatalogGroup `
      -CatalogAuth $session.Auth `
      -XsrfToken $session.XsrfToken `
      -CookieJar $session.CookieJar `
      -DryRun $DryRun
  }
  finally {
    Remove-GeoNetworkSession -Session $session
    if ($metadataUploadPath -ne $XmlPath) {
      Remove-Item -LiteralPath $metadataUploadPath -Force -ErrorAction SilentlyContinue
    }
  }
}

