param(
  [string]$OutputFolder = "C:\Users\RibeiroF\Downloads\figuras_app_car_geoserver",
  [int]$Width = 900,
  [int]$Height = 170
)

Add-Type -AssemblyName System.Drawing

$null = New-Item -ItemType Directory -Path $OutputFolder -Force

$aAcute = [char]0x00E1
$aTilde = [char]0x00E3
$eAcute = [char]0x00E9
$iAcute = [char]0x00ED
$oAcute = [char]0x00F3
$cCedilla = [char]0x00E7

$states = [ordered]@{
  "ac" = "Acre"
  "al" = "Alagoas"
  "am" = "Amazonas"
  "ap" = "Amap$aAcute"
  "ba" = "Bahia"
  "ce" = "Cear$aAcute"
  "df" = "Distrito Federal"
  "es" = "Esp$iAcute" + "rito Santo"
  "go" = "Goi$aAcute" + "s"
  "ma" = "Maranh$aTilde" + "o"
  "mg" = "Minas Gerais"
  "ms" = "Mato Grosso do Sul"
  "mt" = "Mato Grosso"
  "pa" = "Par$aAcute"
  "pb" = "Para$iAcute" + "ba"
  "pe" = "Pernambuco"
  "pi" = "Piau$iAcute"
  "pr" = "Paran$aAcute"
  "rj" = "Rio de Janeiro"
  "rn" = "Rio Grande do Norte"
  "ro" = "Rond$oAcute" + "nia"
  "rr" = "Roraima"
  "rs" = "Rio Grande do Sul"
  "sc" = "Santa Catarina"
  "se" = "Sergipe"
  "sp" = "S$aTilde" + "o Paulo"
  "to" = "Tocantins"
}

$fill = [System.Drawing.Color]::FromArgb(153, 0xA3, 0xD5, 0xFF)
$stroke = [System.Drawing.Color]::FromArgb(255, 0x2E, 0xA9, 0xEB)
$black = [System.Drawing.Color]::Black
$white = [System.Drawing.Color]::White

foreach ($uf in $states.Keys) {
  $stateName = $states[$uf]
  $file = Join-Path $OutputFolder ("legend_geoserver_app_car_{0}_20260301.png" -f $uf)
  $title = "$([char]0x00C1)rea de Preserva$cCedilla$aTilde" + "o Permanente - Im$oAcute" + "veis $stateName"

  $bmp = [System.Drawing.Bitmap]::new($Width, $Height)
  $graphics = [System.Drawing.Graphics]::FromImage($bmp)
  $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
  $graphics.Clear($white)

  $titleFont = [System.Drawing.Font]::new("Arial", 24, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
  $labelFont = [System.Drawing.Font]::new("Arial", 18, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
  $blackBrush = [System.Drawing.SolidBrush]::new($black)
  $fillBrush = [System.Drawing.SolidBrush]::new($fill)
  $strokePen = [System.Drawing.Pen]::new($stroke, 3)

  $graphics.DrawString($title, $titleFont, $blackBrush, 8, 4)
  $graphics.FillRectangle($fillBrush, 12, 52, 20, 20)
  $graphics.DrawRectangle($strokePen, 12, 52, 20, 20)
  $graphics.DrawString("Single symbol", $labelFont, $blackBrush, 42, 49)

  $bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Png)

  $titleFont.Dispose()
  $labelFont.Dispose()
  $blackBrush.Dispose()
  $fillBrush.Dispose()
  $strokePen.Dispose()
  $graphics.Dispose()
  $bmp.Dispose()
}

Write-Host "Figuras no padrao da legenda do GeoServer criadas em: $OutputFolder"
Write-Host ("Total: {0}" -f $states.Count)
