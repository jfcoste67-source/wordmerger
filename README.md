# WordMerger

## RemplaDoc replacement contract template

The merge endpoint accepts case-insensitive field names.
The current field contract is in [the schema](schemas/contrat_remplacement.json).
The `contrat_remplacement` template is synchronized with RemplaDoc's prepared
contract model. It preserves the current Article 2 emphasis and slot order,
bolds the doctor names and the 80% sentence in Article 7, underlines only
`Conciliation :` in Article 9, and keeps the signature table and italic platform
notice. Article 2 dates use French abbreviated month names (for example,
`21 déc. 2026`), while `DATE_JOUR` uses the full French month name.

Existing payloads remain accepted:

- `MEDECIN_REMPLACANT_RRPS` and `MEDECIN_REMPLACE_RRPS` are legacy aliases
  for the corresponding `RPPS` fields. When both are supplied, `RPPS` wins.
- The existing `MEDECIN_REMPMACE_CABINET_*` spelling aliases remain supported.
- Fields removed from the document remain accepted but are no longer required:
  replacement doctor sex, thesis status and address, announcement/application/
  cabinet-doctor identifiers, contract status and practice signature date.
- The remaining required fields are unchanged, except for the canonical `RPPS`
  spelling (legacy `RRPS` input still satisfies the requirement).

New and updated fields:

| Field | Behavior when omitted |
| --- | --- |
| `DATE_JOUR` | Generated in `Europe/Paris` as a French date with the full month name when omitted. |
| `CRENEAUX_ACCEPTES` | Accepted slots, one string per slot. Each renders as its own visible bullet paragraph after the bold Article 2 period. Legacy `CRENEAUX_LISTE` / `JOURS_REMPLACEMENT` values remain fallbacks. |
| `TAUX_CABINET` | Calculated as `100 - TAUX_RETROCESSION` for legacy payloads; the current template no longer displays a separate cabinet-share clause. |
| `AVERTISSEMENT_PROFIL` | Generated from `MEDECIN_REMPLACANT_THESE`: `oui` gives no warning; `non` gives the non-thesis warning. Missing or unrecognized status gives a warning to verify the status before signature. Booleans, `true`/`false`, `yes`/`no` and `1`/`0` are also recognized. |

Explicit values take precedence over generated defaults, including an explicitly
empty profile warning. Direct Python calls to `merge()` use the same aliases and
defaults as the API. Replacement start/end dates retain their French formatting.

`JOURS_REMPLACEMENT` is the worked-day count (for example, `1,5 jours`).
RemplaDoc sends the accepted slot strings explicitly in `CRENEAUX_ACCEPTES`,
with a date and `journée`, `matin` or `après-midi` label. The service does not
infer the count or slot dates from weekday names.

## PDF endpoint

`POST /api/contracts/merge/pdf` accepts the same authenticated JSON request as
`POST /api/contracts/merge`, then converts the merged DOCX to PDF with LibreOffice
and returns `application/pdf`. `X-API-Key` is required for both endpoints.
The server deployment must include `libreoffice-writer`; conversion has a
60-second timeout and generated PDFs are limited to 20 MiB.

## Local checks

Run with Python and the dependencies from [requirements.txt](requirements.txt):

```powershell
python -m unittest test_contracts -v
.\tools\validate_template.ps1 -TemplatePath '.\templates\contrat_remplacement.docx' -SchemaPath '.\schemas\contrat_remplacement.json'
```

The tests render the actual template in memory and validate the generated XML.
The PDF endpoint test stubs the external LibreOffice conversion; production PDF
rendering requires LibreOffice installed on the server.
They do not require a running API, SSH connection, or production credentials.
