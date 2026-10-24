import os
import logging
import shutil
import subprocess
import tempfile
from pathlib import Path

from dotenv import load_dotenv
from fastapi import Depends, FastAPI, HTTPException, Security
from fastapi.responses import Response
from fastapi.security import APIKeyHeader

from app.merger import get_available_templates, merge, normalize_fields_with_aliases
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
logger = logging.getLogger(__name__)


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
    docx_bytes = _render_docx(request)
    filename = f"contrat_{request.template}.docx"
    return Response(
        content=docx_bytes,
        media_type=(
            "application/vnd.openxmlformats-officedocument"
            ".wordprocessingml.document"
        ),
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


@app.post("/api/contracts/merge/pdf", dependencies=[Depends(_verify_key)])
def merge_contract_pdf(request: MergeRequest) -> Response:
    docx_bytes = _render_docx(request)
    try:
        pdf_bytes = _convert_docx_to_pdf(docx_bytes)
    except subprocess.TimeoutExpired as exc:
        logger.exception("WordMerger PDF conversion timed out")
        raise HTTPException(status_code=504, detail="PDF conversion timed out") from exc
    except (OSError, RuntimeError, subprocess.SubprocessError) as exc:
        logger.exception("WordMerger PDF conversion failed")
        raise HTTPException(status_code=503, detail="PDF conversion is unavailable") from exc

    filename = f"contrat_{request.template}.pdf"
    return Response(
        content=pdf_bytes,
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


def _render_docx(request: MergeRequest) -> bytes:
    normalized_fields = normalize_fields_with_aliases(request.fields)

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
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc))
    except (OSError, RuntimeError, ValueError) as exc:
        logger.exception("WordMerger document merge failed")
        raise HTTPException(status_code=500, detail="Merge failed") from exc

    return docx_bytes


def _convert_docx_to_pdf(docx_bytes: bytes) -> bytes:
    converter = shutil.which("libreoffice") or shutil.which("soffice")
    if converter is None:
        raise RuntimeError("LibreOffice is not installed")

    with tempfile.TemporaryDirectory(prefix="wordmerger-") as temp_dir:
        source = Path(temp_dir) / "contract.docx"
        user_profile = Path(temp_dir) / "libreoffice-profile"
        source.write_bytes(docx_bytes)
        result = subprocess.run(
            [
                converter,
                "--headless",
                f"-env:UserInstallation={user_profile.as_uri()}",
                "--convert-to",
                "pdf",
                "--outdir",
                temp_dir,
                str(source),
            ],
            check=False,
            capture_output=True,
            timeout=60,
        )
        output = Path(temp_dir) / "contract.pdf"
        if result.returncode != 0 or not output.is_file():
            raise RuntimeError("LibreOffice could not convert the merged document")
        if output.stat().st_size > 20 * 1024 * 1024:
            raise RuntimeError("The generated PDF exceeds the maximum supported size")
        pdf_bytes = output.read_bytes()
        if not pdf_bytes.startswith(b"%PDF-"):
            raise RuntimeError("LibreOffice returned an invalid PDF")
        return pdf_bytes
