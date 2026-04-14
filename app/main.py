import os

from dotenv import load_dotenv
from fastapi import Depends, FastAPI, HTTPException, Security
from fastapi.responses import Response
from fastapi.security import APIKeyHeader

from app.merger import get_available_templates, merge
from app.models import MergeRequest

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


def _verify_key(key: str = Security(api_key_header)) -> None:
    if not key or key != _API_KEY:
        raise HTTPException(status_code=401, detail="Invalid or missing API key")


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}


@app.get("/api/contracts/templates", dependencies=[Depends(_verify_key)])
def list_templates() -> dict:
    return {"templates": get_available_templates()}


@app.post("/api/contracts/merge", dependencies=[Depends(_verify_key)])
def merge_contract(request: MergeRequest) -> Response:
    try:
        docx_bytes = merge(request.template, request.fields)
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
