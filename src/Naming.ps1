$ErrorActionPreference = "Stop"

function Get-StateNameFromLayer {
  param([string]$LayerName)

  $aAcute = [char]0x00E1
  $iAcute = [char]0x00ED
  $aTilde = [char]0x00E3
  $oCircumflex = [char]0x00F4

  $stateNames = @{
    "ac" = "Acre"
    "al" = "Alagoas"
    "am" = "Amazonas"
    "ap" = ("Amap" + $aAcute)
    "ba" = "Bahia"
    "ce" = ("Cear" + $aAcute)
    "df" = "Distrito Federal"
    "es" = ("Esp" + $iAcute + "rito Santo")
    "go" = ("Goi" + $aAcute + "s")
    "ma" = ("Maranh" + $aTilde + "o")
    "mg" = "Minas Gerais"
    "ms" = "Mato Grosso do Sul"
    "mt" = "Mato Grosso"
    "pa" = ("Par" + $aAcute)
    "pb" = ("Para" + $iAcute + "ba")
    "pe" = "Pernambuco"
    "pi" = ("Piau" + $iAcute)
    "pr" = ("Paran" + $aAcute)
    "rj" = "Rio de Janeiro"
    "rn" = "Rio Grande do Norte"
    "ro" = ("Rond" + $oCircumflex + "nia")
    "rr" = "Roraima"
    "rs" = "Rio Grande do Sul"
    "sc" = "Santa Catarina"
    "se" = "Sergipe"
    "sp" = ("S" + $aTilde + "o Paulo")
    "to" = "Tocantins"
  }

  if ($LayerName -match "_([a-z]{2})_\d{8}$") {
    $stateCode = $Matches[1].ToLowerInvariant()
    if ($stateNames.ContainsKey($stateCode)) {
      return $stateNames[$stateCode]
    }
  }

  return $null
}

function Get-AppCarLayerTitle {
  param([string]$LayerName)

  $stateName = Get-StateNameFromLayer -LayerName $LayerName
  if ([string]::IsNullOrWhiteSpace($stateName)) {
    return $null
  }

  $aAcuteUpper = [char]0x00C1
  $cCedilla = [char]0x00E7
  $aTilde = [char]0x00E3
  $oAcute = [char]0x00F3

  return ("{0}rea de Preserva{1}{2}o Permanente - Im{3}veis {4}" -f $aAcuteUpper, $cCedilla, $aTilde, $oAcute, $stateName)
}

function Get-SaCarLayerTitle {
  param([string]$LayerName)

  $stateName = Get-StateNameFromLayer -LayerName $LayerName
  if ([string]::IsNullOrWhiteSpace($stateName)) {
    return $null
  }

  $aTilde = [char]0x00E3
  $oAcute = [char]0x00F3

  return ("Servid{0}o Administrativa - Im{1}veis {2}" -f $aTilde, $oAcute, $stateName)
}

function Get-UrCarLayerTitle {
  param([string]$LayerName)

  $stateName = Get-StateNameFromLayer -LayerName $LayerName
  if ([string]::IsNullOrWhiteSpace($stateName)) {
    return $null
  }

  $oAcute = [char]0x00F3

  return ("Uso Restrito - Im{0}veis {1}" -f $oAcute, $stateName)
}

function Get-ImbLulcLayerTitle {
  param([string]$LayerName)

  if ($LayerName -notmatch "^rst_imb_lulc_(\d{4})(\d*)$") {
    return $null
  }

  $year = $Matches[1]
  $suffix = $Matches[2]
  $cCedilla = [char]0x00E7
  $aTilde = [char]0x00E3

  if ($suffix -match "^\d{3}") {
    $collection = [int]$Matches[0]
    return ("Uso e cobertura da terra de {0} - Cole{1}{2}o {3}" -f $year, $cCedilla, $aTilde, $collection)
  }

  return ("Uso e cobertura da terra de {0}" -f $year)
}

function Get-AutosInfracaoLayerTitle {
  param([string]$LayerName)

  $aCedilla = [char]0x00E7
  $aTilde = [char]0x00E3

  if ($LayerName -match "^pnt_pcd_enov_\d{8}$") {
    return ("Autos de Infra{0}{1}o" -f $aCedilla, $aTilde)
  }

  if ($LayerName -match "^pnt_pcd_enov_brasil_\d{8}$") {
    return ("Autos de Infra{0}{1}o - Brasil" -f $aCedilla, $aTilde)
  }

  if ($LayerName -match "^pnt_pcd_enov_bbox_brasil_\d{8}$") {
    return ("Autos de Infra{0}{1}o - BBox Brasil" -f $aCedilla, $aTilde)
  }

  return $null
}

function Get-SetorCensitarioLayerTitle {
  param([string]$LayerName)

  if ($LayerName -notmatch "^pol_loc_cse_\d{8}$") {
    return $null
  }

  $aAcute = [char]0x00E1
  return ("Setor Censit{0}rio" -f $aAcute)
}

function Get-CensoTerritorialBasicoParametrosLayerTitle {
  param([string]$LayerName)

  if ($LayerName -notmatch "^pol_soc_ctbp_\d{8}$") {
    return $null
  }

  $aAcute = [char]0x00E1
  $aCircumflex = [char]0x00E2

  return ("Censo demogr{0}fico por Setor Censit{1}rio - Par{2}metros b{3}sicos (2022)" -f $aAcute, $aAcute, $aCircumflex, $aAcute)
}

function Get-DegradacaoFlorestaAmazoniaLayerTitle {
  param([string]$LayerName)

  if ($LayerName -notmatch "^pol_dfaab_imb_\d{8}$") {
    return $null
  }

  $aCedilla = [char]0x00E7
  $aTilde = [char]0x00E3
  $aAcuteUpper = [char]0x00C1
  $oCircumflex = [char]0x00F4

  return ("Degrada{0}{1}o em {2}reas de Floresta - Bioma Amaz{3}nia" -f $aCedilla, $aTilde, $aAcuteUpper, $oCircumflex)
}

function Get-ManchaUrbanaPopulacaoLayerTitle {
  param([string]$LayerName)

  if ($LayerName -notmatch "^pol_soc_ufp_\d{8}$") {
    return $null
  }

  $aAcuteUpper = [char]0x00C1
  $cCedilla = [char]0x00E7
  $aTilde = [char]0x00E3

  return ("{0}rea urbana das sedes municipais com popula{1}{2}o residente" -f $aAcuteUpper, $cCedilla, $aTilde)
}

function Get-DistanciaManchaUrbanaPopulacaoLayerTitle {
  param([string]$LayerName)

  if ($LayerName -notmatch "^rst_gsi_dist_ufp_\d{8}$") {
    return $null
  }

  $aCircumflex = [char]0x00E2
  $aAcute = [char]0x00E1
  $cCedilla = [char]0x00E7
  $aTilde = [char]0x00E3

  return ("Dist{0}ncia da {1}rea urbana das sedes municipais com popula{2}{3}o residente" -f $aCircumflex, $aAcute, $cCedilla, $aTilde)
}

function Get-DistanciaRodoviasNaoOficiaisLayerTitle {
  param([string]$LayerName)

  if ($LayerName -notmatch "^rst_gsi_dist_rod_no_\d{8}$") {
    return $null
  }

  $aCircumflex = [char]0x00E2
  $aTilde = [char]0x00E3

  return ("Dist{0}ncia das rodovias n{1}o oficiais" -f $aCircumflex, $aTilde)
}

function Get-DistanciaRodoviasOficiaisLayerTitle {
  param([string]$LayerName)

  if ($LayerName -notmatch "^rst_gsi_dist_rod_of_\d{8}$") {
    return $null
  }

  $aCircumflex = [char]0x00E2

  return ("Dist{0}ncia das rodovias oficiais" -f $aCircumflex)
}

function Get-LocalidadesPopulacaoUrbanaLayerTitle {
  param([string]$LayerName)

  if ($LayerName -notmatch "^pnt_soc_upl_\d{8}$") {
    return $null
  }

  $cCedilla = [char]0x00E7
  $aTilde = [char]0x00E3

  return ("Pontos oficiais das sedes municipais e capitais com popula{0}{1}o urbana" -f $cCedilla, $aTilde)
}

function Get-LayerNamingRules {
  return @(
    [pscustomobject]@{ Match = "_app_car_"; Resolver = "Get-AppCarLayerTitle" }
    [pscustomobject]@{ Match = "_sa_car_"; Resolver = "Get-SaCarLayerTitle" }
    [pscustomobject]@{ Match = "_ur_car_"; Resolver = "Get-UrCarLayerTitle" }
    [pscustomobject]@{
      Match = "^rst_imb_lulc_"
      Resolver = "Get-ImbLulcLayerTitle"
      Warning = "Nao consegui interpretar ano/colecao pelo nome da camada IMB LULC '{0}'. O script vai usar o titulo do XML ou o proprio nome da camada."
    }
    [pscustomobject]@{
      Match = "^pnt_pcd_enov"
      Resolver = "Get-AutosInfracaoLayerTitle"
      Warning = "Nao consegui interpretar o nome da camada de autos de infracao '{0}'. O script vai usar o titulo do XML ou o proprio nome da camada."
    }
    [pscustomobject]@{
      Match = "^pol_loc_cse_"
      Resolver = "Get-SetorCensitarioLayerTitle"
      Warning = "Nao consegui interpretar o nome da camada de setor censitario '{0}'. O script vai usar o titulo do XML ou o proprio nome da camada."
    }
    [pscustomobject]@{
      Match = "^pol_soc_ctbp_"
      Resolver = "Get-CensoTerritorialBasicoParametrosLayerTitle"
      Warning = "Nao consegui interpretar o nome da camada de censo territorial basico parametros '{0}'. O script vai usar o titulo do XML ou o proprio nome da camada."
    }
    [pscustomobject]@{
      Match = "^pol_dfaab_imb_"
      Resolver = "Get-DegradacaoFlorestaAmazoniaLayerTitle"
      Warning = "Nao consegui interpretar o nome da camada de degradacao em areas de floresta - bioma Amazonia '{0}'. O script vai usar o titulo do XML ou o proprio nome da camada."
    }
    [pscustomobject]@{
      Match = "^pol_soc_ufp_"
      Resolver = "Get-ManchaUrbanaPopulacaoLayerTitle"
      Warning = "Nao consegui interpretar o nome da camada de mancha urbana com populacao residente '{0}'. O script vai usar o titulo do XML ou o proprio nome da camada."
    }
    [pscustomobject]@{
      Match = "^rst_gsi_dist_ufp_"
      Resolver = "Get-DistanciaManchaUrbanaPopulacaoLayerTitle"
      Warning = "Nao consegui interpretar o nome da camada de distancia da mancha urbana com populacao residente '{0}'. O script vai usar o titulo do XML ou o proprio nome da camada."
    }
    [pscustomobject]@{
      Match = "^rst_gsi_dist_rod_no_"
      Resolver = "Get-DistanciaRodoviasNaoOficiaisLayerTitle"
      Warning = "Nao consegui interpretar o nome da camada de distancia das rodovias nao oficiais '{0}'. O script vai usar o titulo do XML ou o proprio nome da camada."
    }
    [pscustomobject]@{
      Match = "^rst_gsi_dist_rod_of_"
      Resolver = "Get-DistanciaRodoviasOficiaisLayerTitle"
      Warning = "Nao consegui interpretar o nome da camada de distancia das rodovias oficiais '{0}'. O script vai usar o titulo do XML ou o proprio nome da camada."
    }
    [pscustomobject]@{
      Match = "^pnt_soc_upl_"
      Resolver = "Get-LocalidadesPopulacaoUrbanaLayerTitle"
      Warning = "Nao consegui interpretar o nome da camada de localidades com populacao urbana '{0}'. O script vai usar o titulo do XML ou o proprio nome da camada."
    }
  )
}

function Get-FriendlyLayerTitle {
  param([string]$LayerName)

  foreach ($rule in Get-LayerNamingRules) {
    if ($LayerName -match $rule.Match) {
      return & $rule.Resolver -LayerName $LayerName
    }
  }

  return $null
}

function Assert-KnownLayerNaming {
  param([string]$LayerName)

  foreach ($rule in Get-LayerNamingRules) {
    if ($LayerName -match $rule.Match) {
      $layerTitle = & $rule.Resolver -LayerName $LayerName
      if ([string]::IsNullOrWhiteSpace($layerTitle) -and -not [string]::IsNullOrWhiteSpace($rule.Warning)) {
        Write-Warning ($rule.Warning -f $LayerName)
      }
      return
    }
  }
}
