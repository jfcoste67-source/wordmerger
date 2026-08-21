# test_merge.ps1 - Non-disruptive API test via SSH tunnel, then open result in Word

$LOCAL_PORTS = @(8002, 18002)
$LOCAL_PORT  = $null
$API_KEY     = $env:WORDMERGER_API_KEY
$OUT_FILE    = "$env:TEMP\contrat_remplacement_test_$((Get-Date).ToString('yyyyMMdd_HHmmss')).docx"

if ([string]::IsNullOrWhiteSpace($API_KEY)) {
    throw "WORDMERGER_API_KEY is not set."
}

foreach ($p in $LOCAL_PORTS) {
    $listener = Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue
    if ($listener) {
        $LOCAL_PORT = $p
        break
    }
}

if (-not $LOCAL_PORT) {
    throw "No local tunnel detected. Open one first (non-disruptive): C:\Program Files\Git\usr\bin\ssh.exe -N -L 8002:127.0.0.1:8002 root@69.62.105.107"
}

$API_URL = "http://127.0.0.1:$LOCAL_PORT/api/contracts/merge"

$payload = @{
    template = "contrat_remplacement"
    fields   = @{
        medecin_remplacant_prenom          = "Jeanne"
        medecin_remplacant_nom             = "Martin"
        medecin_remplacant_rrps            = "12345678901"
        medecin_remplacant_sexe            = "F"
        medecin_remplacant_these           = "Oui"
        medecin_remplacant_adresse         = "8 avenue Victor Hugo"
        medecin_remplacant_code_postal     = "75016"
        medecin_remplacant_ville           = "Paris"
        medecin_remplace_cabinet_nom       = "Cabinet Médical des Lilas"
        medecin_remplace_cabinet_adresse   = "12 rue des Fleurs"
        medecin_remplace_cabinet_code_postal = "75015"
        medecin_remplace_cabinet_ville     = "Paris"
        medecin_remplace_nom               = "Durand"
        medecin_remplace_prenom            = "Paul"
        medecin_remplace_rrps              = "10987654321"
        annonce_id                    = "A-2026-1001"
        candidature_id                = "C-2026-778"
        cabinet_medecin_id            = "CM-55"
        statut_contrat_remplacement   = "Signé"
        jours_remplacement            = @("Lundi", "Mardi", "Jeudi")
        date_debut_remplacement       = "2026-04-20"
        date_fin_remplacement         = "2026-06-30"
        taux_retrocession             = "70"
        date_signature_cabinet        = "14/04/2026"
        ip_signature                  = "127.0.0.1"
    }
} | ConvertTo-Json -Depth 3

Write-Host "Sending request to $API_URL (through local SSH tunnel) ..."

try {
    $response = Invoke-WebRequest `
        -Uri $API_URL `
        -Method POST `
        -UseBasicParsing `
        -Headers @{ "X-API-Key" = $API_KEY; "Content-Type" = "application/json" } `
        -Body $payload `
        -OutFile $OUT_FILE `
        -PassThru `
        -ErrorAction Stop

    Write-Host "Response: $($response.StatusCode) - $([math]::Round($response.RawContentLength/1024,1)) KB"
    Write-Host "Saved to: $OUT_FILE"
    Write-Host "Opening document in Word..."
    Start-Process $OUT_FILE
}
catch {
    Write-Host "ERROR: $_"
    if ($_.Exception.Response) {
        $reader = [System.IO.StreamReader]::new($_.Exception.Response.GetResponseStream())
        Write-Host $reader.ReadToEnd()
    }
}
