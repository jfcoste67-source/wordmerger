import io
from pathlib import Path

from docxtpl import DocxTemplate

TEMPLATE_DIR = Path(__file__).parent.parent / "templates"


def get_available_templates() -> list[str]:
    return [f.stem for f in sorted(TEMPLATE_DIR.glob("*.docx"))]


def merge(template_name: str, fields: dict) -> bytes:
    """Merge fields into a .docx template and return the document as bytes.

    Field keys are normalised to UPPERCASE to match {{FIELD}} placeholders.
    """
    template_path = TEMPLATE_DIR / f"{template_name}.docx"
    if not template_path.exists():
        raise FileNotFoundError(f"Template '{template_name}' not found")

    tpl = DocxTemplate(str(template_path))
    # Template placeholders use UPPERCASE — normalise incoming keys
    normalized = {k.upper(): v for k, v in fields.items()}
    tpl.render(normalized, autoescape=False)

    buf = io.BytesIO()
    tpl.save(buf)
    return buf.getvalue()
