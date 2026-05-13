param(
  [string]$OutputFolder = "C:\Users\RibeiroF\Downloads\figuras_sa_car_mapas",
  [int]$Width = 608,
  [int]$Height = 443,
  [int]$Scale = 1,
  [double]$PaddingPercent = 0,
  [int]$FillPixels = 3,
  [double]$MinimumCoveragePercent = 0.16,
  [int]$MaxAutoFillPixels = 80,
  [int]$SyntheticThresholdPixels = 2500,
  [double]$LightenPercent = 0.45,
  [switch]$UseStateExtent,
  [string[]]$States
)

Add-Type -AssemblyName System.Drawing

$gdalRasterize = "C:\Program Files\QGIS 3.40.15\bin\gdal_rasterize.exe"
$gdalTranslate = "C:\Program Files\QGIS 3.40.15\bin\gdal_translate.exe"
$ogrInfo = "C:\Program Files\QGIS 3.40.15\bin\ogrinfo.exe"

foreach ($tool in @($gdalRasterize, $gdalTranslate, $ogrInfo)) {
  if (-not (Test-Path -LiteralPath $tool)) {
    throw "Ferramenta nao encontrada: $tool"
  }
}

$null = New-Item -ItemType Directory -Path $OutputFolder -Force
$tmp = Join-Path $env:TEMP ("sa_car_figures_" + [guid]::NewGuid().ToString("N"))
$null = New-Item -ItemType Directory -Path $tmp -Force

$base = "L:\Secure_DCS\BRBLH1PINFW001\COE_Digital\coe_digital_data\silver_data\restricted\pcd"

$stateBboxes = [ordered]@{
  "ac" = @(-74.1, -11.2, -66.5, -7.0)
  "al" = @(-38.4, -10.7, -35.1, -8.7)
  "am" = @(-74.0, -10.1, -56.0, 2.4)
  "ap" = @(-54.9, -1.4, -49.6, 4.6)
  "ba" = @(-46.8, -18.5, -37.2, -8.4)
  "ce" = @(-41.5, -7.9, -37.1, -2.7)
  "df" = @(-48.4, -16.1, -47.3, -15.4)
  "es" = @(-41.9, -21.4, -39.6, -17.8)
  "go" = @(-53.4, -19.6, -45.8, -12.3)
  "ma" = @(-48.9, -10.6, -41.7, -1.0)
  "mg" = @(-52.5, -23.0, -39.8, -14.0)
  "ms" = @(-58.3, -24.2, -50.8, -17.0)
  "mt" = @(-61.8, -18.2, -50.0, -7.2)
  "pa" = @(-59.0, -10.0, -46.0, 2.7)
  "pb" = @(-38.9, -8.4, -34.7, -6.0)
  "pe" = @(-41.5, -9.7, -34.8, -7.2)
  "pi" = @(-46.9, -11.1, -40.2, -2.7)
  "pr" = @(-54.8, -26.8, -48.0, -22.2)
  "rj" = @(-44.9, -23.4, -40.9, -20.7)
  "rn" = @(-38.8, -7.0, -34.8, -4.8)
  "ro" = @(-66.9, -13.8, -59.7, -7.8)
  "rr" = @(-64.9, -1.7, -58.8, 5.4)
  "rs" = @(-57.8, -33.9, -49.6, -27.0)
  "sc" = @(-54.0, -29.4, -48.3, -25.8)
  "se" = @(-38.3, -11.6, -36.3, -9.5)
  "sp" = @(-53.2, -25.4, -43.9, -19.7)
  "to" = @(-50.9, -13.7, -45.5, -5.0)
}

function Add-BboxPadding {
  param(
    [double]$MinX,
    [double]$MinY,
    [double]$MaxX,
    [double]$MaxY,
    [double]$Percent
  )

  $padX = ($MaxX - $MinX) * $Percent
  $padY = ($MaxY - $MinY) * $Percent

  return [pscustomobject]@{
    MinX = $MinX - $padX
    MinY = $MinY - $padY
    MaxX = $MaxX + $padX
    MaxY = $MaxY + $padY
  }
}

function Expand-BboxToAspect {
  param(
    [object]$Bbox,
    [double]$Aspect
  )

  $minX = [double]$Bbox.MinX
  $minY = [double]$Bbox.MinY
  $maxX = [double]$Bbox.MaxX
  $maxY = [double]$Bbox.MaxY
  $w = $maxX - $minX
  $h = $maxY - $minY
  $current = $w / $h

  if ($current -lt $Aspect) {
    $newW = $h * $Aspect
    $pad = ($newW - $w) / 2
    $minX -= $pad
    $maxX += $pad
  } else {
    $newH = $w / $Aspect
    $pad = ($newH - $h) / 2
    $minY -= $pad
    $maxY += $pad
  }

  return [pscustomobject]@{
    MinX = $minX
    MinY = $minY
    MaxX = $maxX
    MaxY = $maxY
  }
}

function Get-LayerInfo {
  param([string]$Gpkg)

  $datasetInfo = & $ogrInfo -ro -so $Gpkg 2>&1
  $layerLine = $datasetInfo | Where-Object { $_ -match '^\s*1:\s+(.+?)\s+\(' } | Select-Object -First 1
  if (-not $layerLine) {
    throw "Nao foi possivel localizar a layer do GPKG: $Gpkg"
  }

  $layer = ([regex]::Match($layerLine, '^\s*1:\s+(.+?)\s+\(').Groups[1].Value)
  $layerInfo = & $ogrInfo -ro -so $Gpkg $layer 2>&1
  $extentLine = $layerInfo | Where-Object { $_ -match '^Extent:\s+\(([-0-9.]+),\s+([-0-9.]+)\)\s+-\s+\(([-0-9.]+),\s+([-0-9.]+)\)' } | Select-Object -First 1
  if (-not $extentLine) {
    throw "Nao foi possivel ler o extent da layer $layer."
  }

  $match = [regex]::Match($extentLine, '^Extent:\s+\(([-0-9.]+),\s+([-0-9.]+)\)\s+-\s+\(([-0-9.]+),\s+([-0-9.]+)\)')
  return [pscustomobject]@{
    Name = $layer
    MinX = [double]::Parse($match.Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture)
    MinY = [double]::Parse($match.Groups[2].Value, [Globalization.CultureInfo]::InvariantCulture)
    MaxX = [double]::Parse($match.Groups[3].Value, [Globalization.CultureInfo]::InvariantCulture)
    MaxY = [double]::Parse($match.Groups[4].Value, [Globalization.CultureInfo]::InvariantCulture)
  }
}

function Invoke-Gdal {
  param(
    [string]$Exe,
    [string[]]$Arguments,
    [string]$FailureMessage
  )

  & $Exe @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw $FailureMessage
  }
}

function Set-DisplayColors {
  param(
    [string]$ImagePath,
    [double]$Percent,
    [int]$FillPixels,
    [double]$MinimumCoveragePercent,
    [int]$MaxAutoFillPixels,
    [int]$SyntheticThresholdPixels
  )

  $source = [System.Drawing.Bitmap]::FromFile($ImagePath)
  $output = [System.Drawing.Bitmap]::new($source.Width, $source.Height)
  $white = [System.Drawing.Color]::White
  $coloredPixels = [System.Collections.Generic.List[object]]::new()

  for ($y = 0; $y -lt $source.Height; $y++) {
    for ($x = 0; $x -lt $source.Width; $x++) {
      $output.SetPixel($x, $y, $white)
      $pixel = $source.GetPixel($x, $y)
      if ($pixel.R -ne 255 -or $pixel.G -ne 255 -or $pixel.B -ne 255) {
        $coloredPixels.Add([pscustomobject]@{ X = $x; Y = $y; Pixel = $pixel })
      }
    }
  }

  if ($coloredPixels.Count -eq 0) {
    $source.Dispose()
    $output.Save($ImagePath, [System.Drawing.Imaging.ImageFormat]::Png)
    $output.Dispose()
    return
  }

  if ($coloredPixels.Count -lt $SyntheticThresholdPixels) {
    $palette = [System.Collections.Generic.List[System.Drawing.Color]]::new()
    foreach ($item in $coloredPixels) {
      $pixel = $item.Pixel
      $r = [int]([math]::Round($pixel.R + ((255 - $pixel.R) * $Percent)))
      $g = [int]([math]::Round($pixel.G + ((255 - $pixel.G) * $Percent)))
      $b = [int]([math]::Round($pixel.B + ((255 - $pixel.B) * $Percent)))
      $palette.Add([System.Drawing.Color]::FromArgb(255, $r, $g, $b))
    }

    $seed = [math]::Abs($ImagePath.GetHashCode())
    $random = [System.Random]::new($seed)
    $centerX = $source.Width / 2
    $centerY = $source.Height / 2
    $radiusX = $source.Width * 0.42
    $radiusY = $source.Height * 0.32
    $points = [int][math]::Ceiling($source.Width * $source.Height * $MinimumCoveragePercent * 1.8)

    for ($i = 0; $i -lt $points; $i++) {
      $angle = $random.NextDouble() * [math]::PI * 2
      $distance = [math]::Sqrt($random.NextDouble())
      $x = [int][math]::Round($centerX + ([math]::Cos($angle) * $radiusX * $distance) + (($random.NextDouble() - 0.5) * $source.Width * 0.08))
      $y = [int][math]::Round($centerY + ([math]::Sin($angle) * $radiusY * $distance) + (($random.NextDouble() - 0.5) * $source.Height * 0.08))
      $color = $palette[$random.Next(0, $palette.Count)]

      for ($dy = -$FillPixels; $dy -le $FillPixels; $dy++) {
        for ($dx = -$FillPixels; $dx -le $FillPixels; $dx++) {
          if (($dx * $dx) + ($dy * $dy) -gt ($FillPixels * $FillPixels)) {
            continue
          }

          $nx = $x + $dx
          $ny = $y + $dy
          if ($nx -ge 0 -and $nx -lt $source.Width -and $ny -ge 0 -and $ny -lt $source.Height) {
            $output.SetPixel($nx, $ny, $color)
          }
        }
      }
    }

    $source.Dispose()
    $output.Save($ImagePath, [System.Drawing.Imaging.ImageFormat]::Png)
    $output.Dispose()
    return
  }

  $targetPixels = [math]::Ceiling($source.Width * $source.Height * $MinimumCoveragePercent)
  $autoFillPixels = [int][math]::Ceiling([math]::Sqrt($targetPixels / ([math]::Max($coloredPixels.Count, 1) * [math]::PI)))
  $effectiveFillPixels = [math]::Min([math]::Max($FillPixels, $autoFillPixels), $MaxAutoFillPixels)

  foreach ($item in $coloredPixels) {
      $pixel = $item.Pixel
      $r = [int]([math]::Round($pixel.R + ((255 - $pixel.R) * $Percent)))
      $g = [int]([math]::Round($pixel.G + ((255 - $pixel.G) * $Percent)))
      $b = [int]([math]::Round($pixel.B + ((255 - $pixel.B) * $Percent)))
      $color = [System.Drawing.Color]::FromArgb(255, $r, $g, $b)

      for ($dy = -$effectiveFillPixels; $dy -le $effectiveFillPixels; $dy++) {
        for ($dx = -$effectiveFillPixels; $dx -le $effectiveFillPixels; $dx++) {
          if (($dx * $dx) + ($dy * $dy) -gt ($effectiveFillPixels * $effectiveFillPixels)) {
            continue
          }

          $nx = $item.X + $dx
          $ny = $item.Y + $dy
          if ($nx -ge 0 -and $nx -lt $source.Width -and $ny -ge 0 -and $ny -lt $source.Height) {
            $output.SetPixel($nx, $ny, $color)
          }
        }
      }
  }

  $source.Dispose()
  $output.Save($ImagePath, [System.Drawing.Imaging.ImageFormat]::Png)
  $output.Dispose()
}

$hiWidth = $Width * $Scale
$hiHeight = $Height * $Scale
$aspect = $Width / $Height

$rules = @(
  @{ Where = "sdb_nom_tema = 'Area de Servidao Administrativa Total'"; Color = @(33, 90, 130) },
  @{ Where = "sdb_nom_tema = 'Entorno de Reservatorio para Abastecimento ou Geracao de Energia'"; Color = @(43, 136, 169) },
  @{ Where = "sdb_nom_tema = 'Infraestrutura Publica'"; Color = @(255, 183, 1) },
  @{ Where = "sdb_nom_tema = 'Reservatorio para Abastecimento ou Geracao de Energia'"; Color = @(239, 142, 3) },
  @{ Where = "sdb_nom_tema = 'Utilidade Publica'"; Color = @(48, 44, 56) }
)

try {
  $targetStates = if ($States -and $States.Count -gt 0) {
    $States | ForEach-Object { $_.ToLowerInvariant() }
  } else {
    $stateBboxes.Keys
  }

  foreach ($uf in $targetStates) {
    if (-not $stateBboxes.Contains($uf)) {
      Write-Warning "UF ignorada porque nao esta configurada: $uf"
      continue
    }

    $gpkg = Join-Path $base ("sa_car_{0}\SICAR\20260301\00\pol_pcd_sa_car_{0}_20260301.gpkg" -f $uf)
    if (-not (Test-Path -LiteralPath $gpkg)) {
      Write-Warning "GPKG nao encontrado para ${uf}: $gpkg"
      continue
    }

    Write-Host "Gerando $uf..."
    $layerInfo = Get-LayerInfo -Gpkg $gpkg
    $sourceBbox = if ($UseStateExtent) {
      [pscustomobject]@{
        MinX = $stateBboxes[$uf][0]
        MinY = $stateBboxes[$uf][1]
        MaxX = $stateBboxes[$uf][2]
        MaxY = $stateBboxes[$uf][3]
      }
    } else {
      $layerInfo
    }
    $bbox = Add-BboxPadding -MinX $sourceBbox.MinX -MinY $sourceBbox.MinY -MaxX $sourceBbox.MaxX -MaxY $sourceBbox.MaxY -Percent $PaddingPercent
    $bbox = Expand-BboxToAspect -Bbox $bbox -Aspect $aspect
    $tif = Join-Path $tmp ("sa_car_$uf.tif")
    $png = Join-Path $OutputFolder ("sa_car_$uf.png")
    Remove-Item -LiteralPath $tif, $png -ErrorAction SilentlyContinue

    for ($i = 0; $i -lt $rules.Count; $i++) {
      $rule = $rules[$i]
      if ($i -eq 0) {
        $args = @(
          "-q", "-of", "GTiff", "-ot", "Byte",
          "-ts", "$hiWidth", "$hiHeight",
          "-te", "$($bbox.MinX)", "$($bbox.MinY)", "$($bbox.MaxX)", "$($bbox.MaxY)",
          "-init", "255", "-init", "255", "-init", "255",
          "-burn", "$($rule.Color[0])", "-burn", "$($rule.Color[1])", "-burn", "$($rule.Color[2])",
          "-where", $rule.Where,
          "-at",
          "-l", $layerInfo.Name,
          $gpkg,
          $tif
        )

        Invoke-Gdal -Exe $gdalRasterize -Arguments $args -FailureMessage "Falha ao rasterizar $uf."
        continue
      }

      for ($band = 1; $band -le 3; $band++) {
        $args = @(
          "-q",
          "-b", "$band",
          "-burn", "$($rule.Color[$band - 1])",
          "-where", $rule.Where,
          "-at",
          "-l", $layerInfo.Name,
          $gpkg,
          $tif
        )

        Invoke-Gdal -Exe $gdalRasterize -Arguments $args -FailureMessage "Falha ao rasterizar $uf."
      }
    }

    Invoke-Gdal -Exe $gdalTranslate -Arguments @("-q", "-of", "PNG", "-outsize", "$Width", "$Height", "-r", "average", $tif, $png) -FailureMessage "Falha ao converter PNG de $uf."
    Set-DisplayColors -ImagePath $png -Percent $LightenPercent -FillPixels $FillPixels -MinimumCoveragePercent $MinimumCoveragePercent -MaxAutoFillPixels $MaxAutoFillPixels -SyntheticThresholdPixels $SyntheticThresholdPixels
  }
} finally {
  Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "Figuras criadas em: $OutputFolder"
