param(
  [string]$OutputFolder = "C:\Users\RibeiroF\Downloads\figuras_app_car_mapas",
  [int]$Width = 140,
  [int]$Height = 92,
  [int]$Scale = 4,
  [int]$DilatePixels = 1,
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
$tmp = Join-Path $env:TEMP ("app_car_figures_" + [guid]::NewGuid().ToString("N"))
$null = New-Item -ItemType Directory -Path $tmp -Force

$base = "L:\Secure_DCS\BRBLH1PINFW001\COE_Digital\coe_digital_data\silver_data\restricted\pcd"
$localSp = "C:\Users\RibeiroF\Downloads\app_car_sp\SICAR\20260301\00\pol_pcd_app_car_sp_20260301.gpkg"

$bboxes = [ordered]@{
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

function Expand-BboxToAspect {
  param(
    [double[]]$Bbox,
    [double]$Aspect
  )

  $minX = $Bbox[0]
  $minY = $Bbox[1]
  $maxX = $Bbox[2]
  $maxY = $Bbox[3]
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

  return @($minX, $minY, $maxX, $maxY)
}

function Get-FirstLayerName {
  param([string]$Gpkg)

  $info = & $ogrInfo -ro -so $Gpkg 2>&1
  $line = $info | Where-Object { $_ -match '^\s*1:\s+(.+?)\s+\(' } | Select-Object -First 1
  if (-not $line) {
    throw "Nao foi possivel localizar a layer do GPKG: $Gpkg"
  }
  return ([regex]::Match($line, '^\s*1:\s+(.+?)\s+\(').Groups[1].Value)
}

function Set-BlueFill {
  param(
    [string]$ImagePath,
    [int]$DilatePixels
  )

  $source = [System.Drawing.Bitmap]::FromFile($ImagePath)
  $output = [System.Drawing.Bitmap]::new($source.Width, $source.Height)
  $blue = [System.Drawing.Color]::FromArgb(255, 46, 169, 235)
  $white = [System.Drawing.Color]::White

  for ($y = 0; $y -lt $source.Height; $y++) {
    for ($x = 0; $x -lt $source.Width; $x++) {
      $output.SetPixel($x, $y, $white)
    }
  }

  for ($y = 0; $y -lt $source.Height; $y++) {
    for ($x = 0; $x -lt $source.Width; $x++) {
      $pixel = $source.GetPixel($x, $y)
      if ($pixel.R -lt 250 -or $pixel.G -lt 250 -or $pixel.B -lt 250) {
        for ($dy = -$DilatePixels; $dy -le $DilatePixels; $dy++) {
          for ($dx = -$DilatePixels; $dx -le $DilatePixels; $dx++) {
            $nx = $x + $dx
            $ny = $y + $dy
            if ($nx -ge 0 -and $nx -lt $source.Width -and $ny -ge 0 -and $ny -lt $source.Height) {
              $output.SetPixel($nx, $ny, $blue)
            }
          }
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

try {
  $targetStates = if ($States -and $States.Count -gt 0) {
    $States | ForEach-Object { $_.ToLowerInvariant() }
  } else {
    $bboxes.Keys
  }

  foreach ($uf in $targetStates) {
    if (-not $bboxes.Contains($uf)) {
      Write-Warning "UF ignorada porque nao esta configurada: $uf"
      continue
    }

    $gpkg = Join-Path $base ("app_car_{0}\SICAR\20260301\00\pol_pcd_app_car_{0}_20260301.gpkg" -f $uf)
    if ($uf -eq "sp" -and (Test-Path -LiteralPath $localSp)) {
      $gpkg = $localSp
    }

    if (-not (Test-Path -LiteralPath $gpkg)) {
      Write-Warning "GPKG nao encontrado para ${uf}: $gpkg"
      continue
    }

    Write-Host "Gerando $uf..."
    $layer = Get-FirstLayerName -Gpkg $gpkg
    $bbox = Expand-BboxToAspect -Bbox $bboxes[$uf] -Aspect $aspect
    $tif = Join-Path $tmp ("app_car_$uf.tif")
    $png = Join-Path $OutputFolder ("app_car_$uf.png")
    Remove-Item -LiteralPath $tif, $png -ErrorAction SilentlyContinue

    & $gdalRasterize -q -of GTiff -ot Byte -ts $hiWidth $hiHeight `
      -te $bbox[0] $bbox[1] $bbox[2] $bbox[3] `
      -init 255 -burn 46 -burn 169 -burn 235 `
      -l $layer $gpkg $tif

    if ($LASTEXITCODE -ne 0) {
      throw "Falha ao rasterizar $uf."
    }

    & $gdalTranslate -q -of PNG -outsize $Width $Height -r average $tif $png
    if ($LASTEXITCODE -ne 0) {
      throw "Falha ao converter PNG de $uf."
    }

    Set-BlueFill -ImagePath $png -DilatePixels $DilatePixels
  }
} finally {
  Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "Figuras criadas em: $OutputFolder"
