$ErrorActionPreference = "Stop"

function Resolve-RequiredFile {
  param(
    [string]$Path,
    [string]$Pattern
  )

  $files = @(Get-ChildItem -LiteralPath $Path -Filter $Pattern -File)
  if ($files.Count -ne 1) {
    throw "Esperava 1 arquivo '$Pattern' em '$Path', mas encontrei $($files.Count)."
  }

  return $files[0].FullName
}

function Resolve-RequiredMetadataFile {
  param([string]$Path)

  $files = @(Get-ChildItem -LiteralPath $Path -Filter "*.xml" -File | Where-Object {
    $_.Name -notmatch '\.aux\.xml$'
  })

  if ($files.Count -ne 1) {
    throw "Esperava 1 arquivo de metadados XML em '$Path', mas encontrei $($files.Count)."
  }

  return $files[0].FullName
}

function Resolve-RequiredDataFile {
  param([string]$Path)

  $files = @(Get-ChildItem -LiteralPath $Path -File | Where-Object {
    $extension = $_.Extension.ToLowerInvariant()
    $extension -in '.gpkg', '.rst', '.tif'
  })

  if ($files.Count -ne 1) {
    throw "Esperava exatamente 1 arquivo de dados (.gpkg, .rst ou .tif) em '$Path', mas encontrei $($files.Count)."
  }

  return $files[0].FullName
}

function ConvertTo-BasicAuth {
  param([pscredential]$Credential)

  $user = $Credential.UserName
  $pass = $Credential.GetNetworkCredential().Password
  $pair = "$user`:$pass"
  return [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($pair))
}

function Repair-Mojibake {
  param([string]$Text)

  if ([string]::IsNullOrWhiteSpace($Text) -or $Text -notmatch "[ÃƒÃ‚]") {
    return $Text
  }

  $windows1252 = [Text.Encoding]::GetEncoding(1252)
  return [Text.Encoding]::UTF8.GetString($windows1252.GetBytes($Text))
}

function ConvertTo-XmlEscapedText {
  param([string]$Text)

  $builder = New-Object Text.StringBuilder
  foreach ($character in $Text.ToCharArray()) {
    $code = [int][char]$character
    switch ($character) {
      "<" { [void]$builder.Append("&lt;") }
      ">" { [void]$builder.Append("&gt;") }
      "&" { [void]$builder.Append("&amp;") }
      '"' { [void]$builder.Append("&quot;") }
      "'" { [void]$builder.Append("&apos;") }
      default {
        if ($code -lt 32 -or $code -gt 126) {
          [void]$builder.Append(("&#x{0:X4};" -f $code))
        }
        else {
          [void]$builder.Append($character)
        }
      }
    }
  }

  return $builder.ToString()
}

function ConvertTo-XmlMarkupEscapedText {
  param([string]$Text)

  if ($null -eq $Text) {
    return $null
  }

  return $Text.
    Replace("&", "&amp;").
    Replace("<", "&lt;").
    Replace(">", "&gt;").
    Replace('"', "&quot;").
    Replace("'", "&apos;")
}

function ConvertTo-JsonEscapedText {
  param([string]$Text)

  $builder = New-Object Text.StringBuilder
  foreach ($character in $Text.ToCharArray()) {
    $code = [int][char]$character
    switch ($character) {
      '"' { [void]$builder.Append('\"') }
      '\' { [void]$builder.Append('\\') }
      "`b" { [void]$builder.Append('\b') }
      "`f" { [void]$builder.Append('\f') }
      "`n" { [void]$builder.Append('\n') }
      "`r" { [void]$builder.Append('\r') }
      "`t" { [void]$builder.Append('\t') }
      default {
        if ($code -lt 32 -or $code -gt 126) {
          [void]$builder.Append(('\u{0:x4}' -f $code))
        }
        else {
          [void]$builder.Append($character)
        }
      }
    }
  }

  return $builder.ToString()
}

function ConvertTo-AsciiText {
  param([string]$Text)

  if ([string]::IsNullOrWhiteSpace($Text)) {
    return $Text
  }

  $normalized = $Text.Normalize([Text.NormalizationForm]::FormD)
  $builder = New-Object Text.StringBuilder
  foreach ($character in $normalized.ToCharArray()) {
    $category = [Globalization.CharUnicodeInfo]::GetUnicodeCategory($character)
    if ($category -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
      [void]$builder.Append($character)
    }
  }

  return $builder.ToString().Normalize([Text.NormalizationForm]::FormC)
}

function Invoke-Curl {
  param([string[]]$Arguments)

  $displayArguments = foreach ($argument in $Arguments) {
    if ($argument -like "Authorization: Basic *") {
      "Authorization: Basic ***"
    }
    else {
      $argument
    }
  }

  Write-Host ""
  Write-Host "curl.exe $($displayArguments -join ' ')"
  & curl.exe @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "curl.exe falhou com exit code $LASTEXITCODE."
  }
}

function Invoke-CurlCapture {
  param([string[]]$Arguments)

  $displayArguments = foreach ($argument in $Arguments) {
    if ($argument -like "Authorization: Basic *") {
      "Authorization: Basic ***"
    }
    elseif ($argument -like "X-XSRF-TOKEN: *") {
      "X-XSRF-TOKEN: ***"
    }
    else {
      $argument
    }
  }

  Write-Host ""
  Write-Host "curl.exe $($displayArguments -join ' ')"
  $output = & curl.exe @Arguments
  if ($LASTEXITCODE -ne 0) {
    $body = ($output -join "`n")
    if (-not [string]::IsNullOrWhiteSpace($body)) {
      throw "curl.exe falhou com exit code $LASTEXITCODE. Resposta: $body"
    }
    throw "curl.exe falhou com exit code $LASTEXITCODE."
  }

  return ($output -join "`n")
}

function Get-CookieValue {
  param(
    [string]$CookieJar,
    [string]$CookieName
  )

  if (-not (Test-Path -LiteralPath $CookieJar)) {
    return $null
  }

  $line = Get-Content -LiteralPath $CookieJar |
    Where-Object { $_ -notmatch "^\s*#" -and $_ -match "\s$([regex]::Escape($CookieName))\s" } |
    Select-Object -Last 1

  if ([string]::IsNullOrWhiteSpace($line)) {
    return $null
  }

  return ($line -split "`t")[-1]
}

