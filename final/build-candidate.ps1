param(
    [string]$SourceApk = (Join-Path $PSScriptRoot 'projector-settings.apk'),
    [string]$Payload = (Join-Path $PSScriptRoot 'z9x-hb-ru-v3-payload.zip'),
    [string]$OutputApk = (Join-Path $PSScriptRoot 'projector-settings-ru-v3.UNSIGNED.apk')
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
if (-not ('Z9xZipAlign' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'ZipAlign.cs') }
function Get-EntryHash($entry) {
    $stream = $entry.Open()
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose(); $stream.Dispose() }
}
function Get-Entries($archive) {
    $dict = New-Object 'System.Collections.Generic.Dictionary[string,System.IO.Compression.ZipArchiveEntry]' ([StringComparer]::Ordinal)
    foreach ($entry in $archive.Entries) {
        if ($dict.ContainsKey($entry.FullName)) { throw ('Duplicate ZIP entry: ' + $entry.FullName) }
        $dict.Add($entry.FullName, $entry)
    }
    return ,$dict
}
$SourceApk = [IO.Path]::GetFullPath($SourceApk)
$Payload = [IO.Path]::GetFullPath($Payload)
$OutputApk = [IO.Path]::GetFullPath($OutputApk)
if (-not [IO.File]::Exists($SourceApk)) { throw ('Original full APK not found: ' + $SourceApk) }
if (-not [IO.File]::Exists($Payload)) { throw ('Payload not found: ' + $Payload) }
if ([IO.File]::Exists($OutputApk)) { throw 'Output already exists; choose a new output filename' }
$raw = $OutputApk + '.building-' + [Guid]::NewGuid().ToString('N')
$src = $null; $patch = $null; $dst = $null; $file = $null; $check = $null; $created = $false
try {
    $src = [IO.Compression.ZipFile]::OpenRead($SourceApk)
    $patch = [IO.Compression.ZipFile]::OpenRead($Payload)
    $originals = Get-Entries $src
    $parts = Get-Entries $patch
    $reader = New-Object IO.StreamReader($parts['_patch/manifest.json'].Open())
    try { $spec = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
    $dexNames = @($originals.Keys | Where-Object { $_ -match '^classes(?:[2-9]|[1-9][0-9]+)?\.dex$' } | Sort-Object)
    $expectedDex = @($spec.source_dex_sha256.PSObject.Properties.Name | Sort-Object)
    if (($dexNames -join '|') -cne ($expectedDex -join '|')) { throw 'DEX set differs from reviewed APK' }
    foreach ($item in $spec.source_sha256.PSObject.Properties) {
        if (-not $originals.ContainsKey($item.Name)) { throw ('Missing original entry: ' + $item.Name) }
        if ((Get-EntryHash $originals[$item.Name]) -cne $item.Value) { throw ('Original differs from reviewed version: ' + $item.Name) }
    }
    $replace = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($item in $spec.replacement_sha256.PSObject.Properties) {
        if (-not $parts.ContainsKey($item.Name) -or -not $originals.ContainsKey($item.Name)) { throw ('Missing replacement: ' + $item.Name) }
        if ((Get-EntryHash $parts[$item.Name]) -cne $item.Value) { throw ('Payload hash differs: ' + $item.Name) }
        [void]$replace.Add($item.Name)
    }
    $file = [IO.File]::Open($raw, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite)
    $dst = New-Object IO.Compression.ZipArchive($file, [IO.Compression.ZipArchiveMode]::Create, $true)
    foreach ($entry in $src.Entries) {
        if ($entry.FullName -match '(?i)^META-INF/(MANIFEST\.MF|[^/]+\.(SF|RSA|DSA|EC))$') { continue }
        $level = [IO.Compression.CompressionLevel]::Optimal
        if ($entry.FullName -eq 'resources.arsc' -or $entry.CompressedLength -eq $entry.Length) { $level = [IO.Compression.CompressionLevel]::NoCompression }
        $out = $dst.CreateEntry($entry.FullName, $level)
        $out.LastWriteTime = $entry.LastWriteTime
        $from = $entry
        if ($replace.Contains($entry.FullName)) { $from = $parts[$entry.FullName] }
        $inputStream = $from.Open(); $outputStream = $out.Open()
        try { $inputStream.CopyTo($outputStream) } finally { $inputStream.Dispose(); $outputStream.Dispose() }
    }
    $dst.Dispose(); $dst = $null; $file.Dispose(); $file = $null
    [Z9xZipAlign]::Align($raw, $OutputApk)
    $created = $true
    $check = [IO.Compression.ZipFile]::OpenRead($OutputApk)
    $checked = Get-Entries $check
    foreach ($name in $checked.Keys) {
        $expected = $originals[$name]
        if ($replace.Contains($name)) { $expected = $parts[$name] }
        if ((Get-EntryHash $checked[$name]) -cne (Get-EntryHash $expected)) { throw ('Candidate verification failed: ' + $name) }
    }
    $sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $OutputApk).Hash.ToLowerInvariant()
    $sourceSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $SourceApk).Hash.ToLowerInvariant()
    $result = [ordered]@{ source_apk_sha256=$sourceSha; candidate_sha256=$sha; replacement_entries=$replace.Count; unsigned=$true; aligned_to=4; installed=$false; hardware_tested=$false }
    $result | ConvertTo-Json | Set-Content -Encoding ASCII -LiteralPath ($OutputApk + '.json')
    Write-Host ('CANDIDATE_BUILT: ' + $OutputApk)
    Write-Host ('SHA256: ' + $sha)
    Write-Host 'Unsigned review candidate. Do not use adb install.'
} catch {
    if ($created -and [IO.File]::Exists($OutputApk)) { [IO.File]::Delete($OutputApk) }
    throw
} finally {
    if ($check) { $check.Dispose() }
    if ($dst) { $dst.Dispose() }
    if ($file) { $file.Dispose() }
    if ($src) { $src.Dispose() }
    if ($patch) { $patch.Dispose() }
    if ([IO.File]::Exists($raw)) { [IO.File]::Delete($raw) }
}
