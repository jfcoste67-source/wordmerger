# tools/patch_template.ps1
# Renames legacy placeholders to new canonical names and injects missing fields.
param(
    [string]$TemplatePath = "templates\contrat_remplacement.docx"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$backupPath = $TemplatePath -replace '\.docx$', (".backup-patch-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + ".docx")
Copy-Item $TemplatePath $backupPath -Force
Write-Host "Backup: $backupPath"

# --- 1. Read original zip ---
$inBytes  = [System.IO.File]::ReadAllBytes($TemplatePath)
$inMs     = New-Object System.IO.MemoryStream(,$inBytes)
$inZip    = New-Object System.IO.Compression.ZipArchive($inMs, [System.IO.Compression.ZipArchiveMode]::Read, $false)

$outMs  = New-Object System.IO.MemoryStream
$outZip = New-Object System.IO.Compression.ZipArchive($outMs, [System.IO.Compression.ZipArchiveMode]::Create, $true)

# --- 2. Rename mappings (applied to document.xml text) ---
$renames = [ordered]@{
    '{{CABINET_NOM}}'         = '{{MEDECIN_REMPLACE_CABINET_NOM}}'
    '{{CABINET_ADRESSE}}'     = '{{MEDECIN_REMPLACE_CABINET_ADRESSE}}'
    '{{CABINET_CODE_POSTAL}}' = '{{MEDECIN_REMPLACE_CABINET_CODE_POSTAL}}'
    '{{CABINET_VILLE}}'       = '{{MEDECIN_REMPLACE_CABINET_VILLE}}'
    '{{MEDECIN_NOM}}'         = '{{MEDECIN_REMPLACANT_NOM}}'
    '{{MEDECIN_PRENOM}}'      = '{{MEDECIN_REMPLACANT_PRENOM}}'
    '{{MEDECIN_RRPS}}'        = '{{MEDECIN_REMPLACANT_RRPS}}'
    '{{MEDECIN_SEXE}}'        = '{{MEDECIN_REMPLACANT_SEXE}}'
    '{{MEDECIN_THESE}}'       = '{{MEDECIN_REMPLACANT_THESE}}'
}

# --- 3. New fields to inject (labelled paragraphs appended before </w:body>) ---
$newFields = @(
    @{ label = "Adresse remplaçant";          field = "MEDECIN_REMPLACANT_ADRESSE" },
    @{ label = "Code postal remplaçant";      field = "MEDECIN_REMPLACANT_CODE_POSTAL" },
    @{ label = "Ville remplaçant";            field = "MEDECIN_REMPLACANT_VILLE" },
    @{ label = "Nom médecin remplacé";        field = "MEDECIN_REMPLACE_NOM" },
    @{ label = "Prénom médecin remplacé";     field = "MEDECIN_REMPLACE_PRENOM" },
    @{ label = "RRPS médecin remplacé";       field = "MEDECIN_REMPLACE_RRPS" },
    @{ label = "Date début remplacement";     field = "DATE_DEBUT_REMPLACEMENT" },
    @{ label = "Date fin remplacement";       field = "DATE_FIN_REMPLACEMENT" }
)

function Make-Para([string]$label, [string]$field) {
    $escaped = [System.Security.SecurityElement]::Escape("$label : {{$field}}")
    return '<w:p><w:pPr><w:jc w:val="left"/></w:pPr><w:r><w:t xml:space="preserve">' + $escaped + '</w:t></w:r></w:p>' + "`n"
}

$injectionBlock  = "`n"
$injectionBlock += '<w:p><w:r><w:t xml:space="preserve">--- Champs complementaires ---</w:t></w:r></w:p>' + "`n"
foreach ($f in $newFields) {
    $injectionBlock += Make-Para $f.label $f.field
}

# --- 4. Copy all entries, patching document.xml ---
foreach ($entry in $inZip.Entries) {
    $name = $entry.FullName -replace '\\', '/'
    $outEntry = $outZip.CreateEntry($name, [System.IO.Compression.CompressionLevel]::Optimal)

    $inStream  = $entry.Open()
    $outStream = $outEntry.Open()

    if ($name -eq 'word/document.xml') {
        $reader  = New-Object System.IO.StreamReader($inStream, [System.Text.Encoding]::UTF8)
        $content = $reader.ReadToEnd()
        $reader.Dispose()

        # Apply renames
        foreach ($kv in $renames.GetEnumerator()) {
            $content = $content.Replace($kv.Key, $kv.Value)
        }

        # Inject new fields before </w:body>
        $content = $content -replace '</w:body>', ($injectionBlock + '</w:body>')

        $writer = New-Object System.IO.StreamWriter($outStream, [System.Text.Encoding]::UTF8)
        $writer.Write($content)
        $writer.Flush()
        $writer.Dispose()
    }
    else {
        $inStream.CopyTo($outStream)
    }

    $inStream.Dispose()
    $outStream.Dispose()
}

$inZip.Dispose()
$inMs.Dispose()
$outZip.Dispose()

$finalBytes = $outMs.ToArray()
$outMs.Dispose()

[System.IO.File]::WriteAllBytes($TemplatePath, $finalBytes)
Write-Host "Template patched: $([math]::Round($finalBytes.Length/1024,1)) KB"
