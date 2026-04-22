import os

from dotenv import load_dotenv
from fastapi import Depends, FastAPI, HTTPException, Security
from fastapi.responses import Response
from fastapi.security import APIKeyHeader

from app.merger import get_available_templates, merge
from app.models import MergeRequest
from app.schema import get_allowed_fields, get_required_fields

load_dotenv()

_API_KEY = os.getenv("WORDMERGER_API_KEY", "")
if not _API_KEY:
    raise RuntimeError("WORDMERGER_API_KEY environment variable is not set")

api_key_header = APIKeyHeader(name="X-API-Key", auto_error=False)

app = FastAPI(
    title="WordMerger API",
    version="1.0.0",
    # Disable public docs in production
    docs_url=None,
    redoc_url=None,
)


FIELD_ALIASES = {
    "MEDECIN_REMPMACE_CABINET_ADRESSE": "MEDECIN_REMPLACE_CABINET_ADRESSE",
    "MEDECIN_REMPMACE_CABINET_CODE_POSTAL": "MEDECIN_REMPLACE_CABINET_CODE_POSTAL",
    "MEDECIN_REMPMACE_CABINET_VILLE": "MEDECIN_REMPLACE_CABINET_VILLE",
}


def _verify_key(key: str = Security(api_key_header)) -> None:
    if not key or key != _API_KEY:
        raise HTTPException(status_code=401, detail="Invalid or missing API key")


def _normalize_fields_with_aliases(fields: dict) -> dict[str, object]:
    normalized = {k.upper(): v for k, v in fields.items()}
    for alias, canonical in FIELD_ALIASES.items():
        if alias in normalized and canonical not in normalized:
            normalized[canonical] = normalized[alias]
        normalized.pop(alias, None)
    return normalized


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}


@app.get("/api/contracts/templates", dependencies=[Depends(_verify_key)])
def list_templates() -> dict:
    return {"templates": get_available_templates()}


@app.post("/api/contracts/merge", dependencies=[Depends(_verify_key)])
def merge_contract(request: MergeRequest) -> Response:
    normalized_fields = _normalize_fields_with_aliases(request.fields)

    try:
        allowed = get_allowed_fields(request.template)
        required = get_required_fields(request.template)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc))
    except ValueError as exc:
        raise HTTPException(status_code=500, detail=str(exc))

    unknown = sorted([k for k in normalized_fields.keys() if k not in allowed])
    if unknown:
        raise HTTPException(
            status_code=422,
            detail={
                "error": "Unknown fields in payload",
                "fields": unknown,
            },
        )

    missing = sorted([k for k in required if k not in normalized_fields])
    if missing:
        raise HTTPException(
            status_code=422,
            detail={
                "error": "Missing required fields",
                "fields": missing,
            },
        )

    try:
        docx_bytes = merge(request.template, normalized_fields)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc))
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Merge failed: {exc}")

    filename = f"contrat_{request.template}.docx"
    return Response(
        content=docx_bytes,
        media_type=(
            "application/vnd.openxmlformats-officedocument"
            ".wordprocessingml.document"
        ),
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )
