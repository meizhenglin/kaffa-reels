Add-Type -AssemblyName System.Drawing

$src = "C:\Users\admin\arab_drama_app\assets\images\APP_LOGO_NEW_purple.png"
$dst = "C:\Users\admin\arab_drama_app\web\logo.ico"

# ICO 内嵌的多分辨率：覆盖浏览器/标签页/书签需要的尺寸
$sizes = @(16, 24, 32, 48, 64, 128, 256)

$orig = [System.Drawing.Image]::FromFile($src)
$bitmaps = @()
foreach ($s in $sizes) {
    $bmp = New-Object System.Drawing.Bitmap $s, $s
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.DrawImage($orig, 0, 0, $s, $s)
    $g.Dispose()
    $bitmaps += $bmp
}
$orig.Dispose()

# 用 MemoryStream 构造 .ico 容器
$ms = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter $ms

# ICONDIR
$bw.Write([UInt16]0)            # reserved
$bw.Write([UInt16]1)            # type: icon
$bw.Write([UInt16]$sizes.Count) # count

$headerSize = 6
$entrySize = 16
$imageOffset = $headerSize + $entrySize * $sizes.Count

foreach ($bmp in $bitmaps) {
    $imgMs = New-Object System.IO.MemoryStream
    $bmp.Save($imgMs, [System.Drawing.Imaging.ImageFormat]::Png)
    $imgBytes = $imgMs.ToArray()
    $imgMs.Dispose()

    $w = if ($bmp.Width -ge 256) { 0 } else { $bmp.Width }
    $h = if ($bmp.Height -ge 256) { 0 } else { $bmp.Height }

    $bw.Write([Byte]$w)                  # width
    $bw.Write([Byte]$h)                  # height
    $bw.Write([Byte]0)                   # color count
    $bw.Write([Byte]0)                   # reserved
    $bw.Write([UInt16]1)                 # color planes
    $bw.Write([UInt16]32)                # bits per pixel
    $bw.Write([UInt32]$imgBytes.Length)  # image size
    $bw.Write([UInt32]$imageOffset)      # offset
    $imageOffset += $imgBytes.Length
    $bmp.Dispose()
}

foreach ($bmp in $bitmaps) {
    # already disposed above; re-encode from the stored images
}

# Rewrite images section properly
# Reset stream and re-do the entries with image bytes inline
$ms2 = New-Object System.IO.MemoryStream
$bw2 = New-Object System.IO.BinaryWriter $ms2

$bw2.Write([UInt16]0)
$bw2.Write([UInt16]1)
$bw2.Write([UInt16]$sizes.Count)

$entries = @()
$imageOffset = $headerSize + $entrySize * $sizes.Count

# Re-create bitmaps since we disposed them
$orig = [System.Drawing.Image]::FromFile($src)
foreach ($s in $sizes) {
    $bmp = New-Object System.Drawing.Bitmap $s, $s
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.DrawImage($orig, 0, 0, $s, $s)
    $g.Dispose()

    $imgMs = New-Object System.IO.MemoryStream
    $bmp.Save($imgMs, [System.Drawing.Imaging.ImageFormat]::Png)
    $imgBytes = $imgMs.ToArray()
    $imgMs.Dispose()

    $w = if ($bmp.Width -ge 256) { 0 } else { $bmp.Width }
    $h = if ($bmp.Height -ge 256) { 0 } else { $bmp.Height }

    $bw2.Write([Byte]$w)
    $bw2.Write([Byte]$h)
    $bw2.Write([Byte]0)
    $bw2.Write([Byte]0)
    $bw2.Write([UInt16]1)
    $bw2.Write([UInt16]32)
    $bw2.Write([UInt32]$imgBytes.Length)
    $bw2.Write([UInt32]$imageOffset)
    $imageOffset += $imgBytes.Length

    $entries += ,@{ Bytes = $imgBytes; Bitmap = $bmp }
}

foreach ($e in $entries) {
    $bw2.Write($e.Bytes)
    $e.Bitmap.Dispose()
}
$orig.Dispose()

$bw2.Flush()
[System.IO.File]::WriteAllBytes($dst, $ms2.ToArray())
$bw2.Dispose()
$ms2.Dispose()
$ms.Dispose()

Write-Host "Wrote $dst ($([System.IO.File]::ReadAllBytes($dst).Length) bytes)"
