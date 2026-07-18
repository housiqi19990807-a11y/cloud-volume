param(
    [string]$Source = "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png",
    [string]$Output = "windows/runner/resources/app_icon.ico",
    [ValidateRange(0.05, 0.5)]
    [double]$CornerRadiusRatio = 0.225
)

# Generates the Windows icon from the existing brand raster while applying the
# rounded mask that macOS supplies when it displays the same opaque source.
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Drawing

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = [IO.Path]::GetFullPath((Join-Path $repoRoot $Source))
$outputPath = [IO.Path]::GetFullPath((Join-Path $repoRoot $Output))
$iconSizes = @(16, 20, 24, 32, 40, 48, 64, 128, 256)

if (-not [IO.File]::Exists($sourcePath)) {
    throw "Icon source does not exist: $sourcePath"
}

function New-RoundedSquarePath {
    param(
        [double]$Size,
        [double]$Radius
    )

    $path = [Drawing.Drawing2D.GraphicsPath]::new()
    $diameter = $Radius * 2
    $edge = $Size - 1

    $path.AddArc(0, 0, $diameter, $diameter, 180, 90)
    $path.AddArc($edge - $diameter, 0, $diameter, $diameter, 270, 90)
    $path.AddArc(
        $edge - $diameter,
        $edge - $diameter,
        $diameter,
        $diameter,
        0,
        90
    )
    $path.AddArc(0, $edge - $diameter, $diameter, $diameter, 90, 90)
    $path.CloseFigure()
    return $path
}

function New-IconFrame {
    param(
        [Drawing.Image]$Master,
        [int]$Size
    )

    $frame = [Drawing.Bitmap]::new(
        $Size,
        $Size,
        [Drawing.Imaging.PixelFormat]::Format32bppArgb
    )
    $graphics = [Drawing.Graphics]::FromImage($frame)
    try {
        $graphics.Clear([Drawing.Color]::Transparent)
        $graphics.CompositingMode = [Drawing.Drawing2D.CompositingMode]::SourceCopy
        $graphics.CompositingQuality = [Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::HighQuality
        $destination = [Drawing.Rectangle]::new(0, 0, $Size, $Size)
        $graphics.DrawImage($Master, $destination)
    } finally {
        $graphics.Dispose()
    }
    return $frame
}

function ConvertTo-PngBytes {
    param([Drawing.Image]$Image)

    $stream = [IO.MemoryStream]::new()
    try {
        $Image.Save($stream, [Drawing.Imaging.ImageFormat]::Png)
        return ,$stream.ToArray()
    } finally {
        $stream.Dispose()
    }
}

$sourceImage = [Drawing.Image]::FromFile($sourcePath)
$master = $null
try {
    if ($sourceImage.Width -ne $sourceImage.Height) {
        throw "Icon source must be square: $sourcePath"
    }

    $masterSize = $sourceImage.Width
    $master = [Drawing.Bitmap]::new(
        $masterSize,
        $masterSize,
        [Drawing.Imaging.PixelFormat]::Format32bppArgb
    )
    $graphics = [Drawing.Graphics]::FromImage($master)
    $path = New-RoundedSquarePath `
        -Size $masterSize `
        -Radius ($masterSize * $CornerRadiusRatio)
    $brush = [Drawing.TextureBrush]::new(
        $sourceImage,
        [Drawing.Drawing2D.WrapMode]::Clamp
    )
    try {
        $graphics.Clear([Drawing.Color]::Transparent)
        $graphics.CompositingMode = [Drawing.Drawing2D.CompositingMode]::SourceCopy
        $graphics.CompositingQuality = [Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.FillPath($brush, $path)
    } finally {
        $brush.Dispose()
        $path.Dispose()
        $graphics.Dispose()
    }

    $frames = foreach ($size in $iconSizes) {
        $frame = New-IconFrame -Master $master -Size $size
        try {
            [pscustomobject]@{
                Size = $size
                Bytes = ConvertTo-PngBytes -Image $frame
            }
        } finally {
            $frame.Dispose()
        }
    }

    $outputDirectory = Split-Path -Parent $outputPath
    [IO.Directory]::CreateDirectory($outputDirectory) | Out-Null
    $stream = [IO.MemoryStream]::new()
    $writer = [IO.BinaryWriter]::new($stream)
    try {
        $writer.Write([uint16]0)
        $writer.Write([uint16]1)
        $writer.Write([uint16]$frames.Count)

        $offset = 6 + (16 * $frames.Count)
        foreach ($frame in $frames) {
            $dimension = if ($frame.Size -eq 256) { 0 } else { $frame.Size }
            $writer.Write([byte]$dimension)
            $writer.Write([byte]$dimension)
            $writer.Write([byte]0)
            $writer.Write([byte]0)
            $writer.Write([uint16]1)
            $writer.Write([uint16]32)
            $writer.Write([uint32]$frame.Bytes.Length)
            $writer.Write([uint32]$offset)
            $offset += $frame.Bytes.Length
        }
        foreach ($frame in $frames) {
            $writer.Write([byte[]]$frame.Bytes)
        }
        $writer.Flush()
        [IO.File]::WriteAllBytes($outputPath, $stream.ToArray())
    } finally {
        $writer.Dispose()
        $stream.Dispose()
    }
} finally {
    if ($null -ne $master) {
        $master.Dispose()
    }
    $sourceImage.Dispose()
}

Write-Host (
    "Generated {0} with {1} PNG layers and a {2:P1} corner radius." -f `
        $outputPath,
        $iconSizes.Count,
        $CornerRadiusRatio
)
