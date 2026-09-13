# Resizes phone screenshots to Play Store dimensions.
#
# Play accepts a range of sizes, but 1080 x 1920 (exact 9:16) always
# passes, while a modern phone shoots something taller - 1080 x 2340 on
# most Samsungs. Rather than crop away the top or bottom of your UI, this
# scales each image to fit and pads the sides.
#
# Windows only, and no installs needed: System.Drawing ships with .NET.
#
#   .\scripts\resize-screenshots.ps1
#   .\scripts\resize-screenshots.ps1 -Source "C:\shots" -Out "C:\out"
#   .\scripts\resize-screenshots.ps1 -Background Navy
#
# If PowerShell refuses to run it ("running scripts is disabled on this
# system"), that is the execution policy, not this file:
#
#   powershell -ExecutionPolicy Bypass -File .\scripts\resize-screenshots.ps1

param(
  [string]$Source = "$HOME\Pictures\Screenshots",
  [string]$Out = "$HOME\Desktop\play-screenshots",
  # Padding colour. Light matches the app's screen background, Navy its
  # header - pick whichever suits the shots you are converting.
  [ValidateSet('Light', 'Navy', 'White')]
  [string]$Background = 'Light'
)

Add-Type -AssemblyName System.Drawing

$W = 1080
$H = 1920

$bg = switch ($Background) {
  'Navy'  { [System.Drawing.Color]::FromArgb(11, 31, 59) }
  'White' { [System.Drawing.Color]::White }
  default { [System.Drawing.Color]::FromArgb(244, 246, 248) }
}

if (-not (Test-Path $Source)) {
  Write-Error "Source folder not found: $Source"
  exit 1
}

New-Item -ItemType Directory -Force -Path $Out | Out-Null

$files = @(Get-ChildItem -Path $Source -Include *.png, *.jpg, *.jpeg -File -Recurse:$false -ErrorAction SilentlyContinue)
if ($files.Count -eq 0) {
  $files = @(Get-ChildItem -Path (Join-Path $Source '*') -Include *.png, *.jpg, *.jpeg -File)
}

if ($files.Count -eq 0) {
  Write-Warning "No .png or .jpg files in $Source"
  exit 0
}

foreach ($file in $files) {
  $img = [System.Drawing.Image]::FromFile($file.FullName)
  try {
    $scale = [Math]::Min($W / $img.Width, $H / $img.Height)
    $nw = [int]($img.Width * $scale)
    $nh = [int]($img.Height * $scale)

    # 24bpp, not the default 32bpp: Play wants a PNG with no alpha channel,
    # and an opaque 32bpp image still carries one.
    $canvas = New-Object System.Drawing.Bitmap($W, $H, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    try {
      $g = [System.Drawing.Graphics]::FromImage($canvas)
      try {
        $g.Clear($bg)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.DrawImage($img, [int](($W - $nw) / 2), [int](($H - $nh) / 2), $nw, $nh)
      } finally { $g.Dispose() }

      $dest = Join-Path $Out ($file.BaseName + '-play.png')
      $canvas.Save($dest, [System.Drawing.Imaging.ImageFormat]::Png)
      Write-Host ("{0}  {1}x{2}  ->  {3}x{4}" -f $file.Name, $img.Width, $img.Height, $W, $H)
    } finally { $canvas.Dispose() }
  } finally { $img.Dispose() }
}

Write-Host ""
Write-Host "$($files.Count) file(s) written to $Out"
