param(
    [string]$TemplatePath = "templates/contrat_remplacement.docx",
    [string]$SchemaPath = "schemas/contrat_remplacement.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Read-ZipEntryText {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.Compression.ZipArchive]$Zip,
        [Parameter(Mandatory = $true)]
        [string]$EntryName
    )

    $entry = $Zip.GetEntry($EntryName)
    if (-not $entry) { return $null }

    $stream = $entry.Open()
    try {
        $reader = New-Object System.IO.StreamReader($stream)
        return $reader.ReadToEnd()
    }
    finally {
        $stream.Dispose()
    }
}

if (-not (Test-Path $TemplatePath)) {
    throw "Template not found: $TemplatePath"
}

if (-not (Test-Path $SchemaPath)) {
    throw "Schema not found: $SchemaPath"
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$zipStream = [System.IO.File]::OpenRead($TemplatePath)
try {
    $zip = New-Object System.IO.Compression.ZipArchive($zipStream, [System.IO.Compression.ZipArchiveMode]::Read, $false)

    $entryNames = @($zip.Entries | ForEach-Object { $_.FullName })
    $hasBackslashEntries = $entryNames | Where-Object { $_ -match "\\" }

    $hasRels = $entryNames -contains "_rels/.rels"
    $hasDoc = $entryNames -contains "word/document.xml"

    Write-Host "Template: $TemplatePath"
    Write-Host "Entries : $($entryNames.Count)"
    Write-Host "Has _rels/.rels      : $hasRels"
    Write-Host "Has word/document.xml: $hasDoc"

    if ($hasBackslashEntries) {
        Write-Host "WARNING: Found zip entries using backslashes (invalid for OpenXML)."
        $hasBackslashEntries | Select-Object -First 5 | ForEach-Object { Write-Host " - $_" }
    }

    if (-not $hasRels -or -not $hasDoc) {
        throw "Template package is invalid (missing required OpenXML entries)."
    }

    $xml = Read-ZipEntryText -Zip $zip -EntryName "word/document.xml"
    if (-not $xml) {
        throw "Cannot read word/document.xml"
    }

    $matches = [regex]::Matches($xml, "\{\{\s*([A-Z0-9_]+)\s*\}\}")
    $placeholders = @($matches | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)

    Write-Host "Placeholders found: $($placeholders.Count)"
    if ($placeholders.Count -gt 0) {
        $placeholders | ForEach-Object { Write-Host " - $_" }
    }

    $schema = Get-Content $SchemaPath -Raw | ConvertFrom-Json
    $schemaKeys = @($schema.fields.PSObject.Properties.Name | ForEach-Object { $_.ToUpperInvariant() } | Sort-Object -Unique)
    $requiredKeys = @(
        $schema.fields.PSObject.Properties |
        Where-Object { $_.Value.required -eq $true } |
        ForEach-Object { $_.Name.ToUpperInvariant() } |
        Sort-Object -Unique
    )

    $missingInTemplate = @($requiredKeys | Where-Object { $_ -notin $placeholders })
    $extraInTemplate = @($placeholders | Where-Object { $_ -notin $schemaKeys })

    if ($missingInTemplate.Count -gt 0) {
        Write-Host "ERROR: Missing placeholders required by schema:"
        $missingInTemplate | ForEach-Object { Write-Host " - $_" }
    }

    if ($extraInTemplate.Count -gt 0) {
        Write-Host "WARNING: Extra placeholders not present in schema:"
        $extraInTemplate | ForEach-Object { Write-Host " - $_" }
    }

    if ((-not $hasRels) -or (-not $hasDoc) -or ($missingInTemplate.Count -gt 0)) {
        exit 1
    }

    Write-Host "Validation OK"
    exit 0
}
finally {
    $zipStream.Dispose()
}
