# test_local.ps1 - Test local direct (sans tunnel SSH, sans API)
# Appelle merger.py directement avec le template sur disque local

$OUT_FILE = "$env:TEMP\contrat_remplacement_local_$((Get-Date).ToString('yyyyMMdd_HHmmss')).docx"
$repoRoot = Split-Path -Parent $PSScriptRoot
$mergerPath = Join-Path $repoRoot 'app\merger.py'

$script = @"
import sys, importlib.util
spec = importlib.util.spec_from_file_location('merger', r'$mergerPath')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
merge = mod.merge

fields = {
    'medecin_remplacant_prenom':          'Jeanne',
    'medecin_remplacant_nom':             'Martin',
    'medecin_remplacant_rrps':            '12345678901',
    'medecin_remplacant_sexe':            'F',
    'medecin_remplacant_these':           'Oui',
    'medecin_remplacant_adresse':         '8 avenue Victor Hugo',
    'medecin_remplacant_code_postal':     '75016',
    'medecin_remplacant_ville':           'Paris',
    'medecin_remplace_cabinet_nom':       'Cabinet Medical des Lilas',
    'medecin_remplace_cabinet_adresse':   '12 rue des Fleurs',
    'medecin_remplace_cabinet_code_postal': '75015',
    'medecin_remplace_cabinet_ville':     'Paris',
    'medecin_remplace_nom':               'Durand',
    'medecin_remplace_prenom':            'Paul',
    'medecin_remplace_rrps':              '10987654321',
    'annonce_id':                         'A-2026-1001',
    'candidature_id':                     'C-2026-778',
    'cabinet_medecin_id':                 'CM-55',
    'statut_contrat_remplacement':        'Signe',
    'jours_remplacement':                 ['Lundi', 'Mardi', 'Jeudi'],
    'date_debut_remplacement':            '2026-04-20',
    'date_fin_remplacement':              '2026-06-30',
    'taux_retrocession':                  '70',
    'date_signature_cabinet':             '14/04/2026',
    'ip_signature':                       '127.0.0.1',
}

data = merge('contrat_remplacement', fields)
with open(r'$OUT_FILE', 'wb') as f:
    f.write(data)
print(f'OK - {len(data)} bytes')
"@

Write-Host "Generating document locally..."
$result = python -c $script 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host $result
    Write-Host "Saved to: $OUT_FILE"
    Write-Host "Opening in Word..."
    Start-Process $OUT_FILE
} else {
    Write-Host "ERROR:"
    Write-Host $result
}
