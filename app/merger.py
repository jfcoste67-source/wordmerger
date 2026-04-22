import io
from pathlib import Path

from docxtpl import DocxTemplate
from datetime import date, datetime

TEMPLATE_DIR = Path(__file__).parent.parent / "templates"
ARTICLE2_DATE_FIELDS = {"DATE_DEBUT_REMPLACEMENT", "DATE_FIN_REMPLACEMENT"}
FR_MONTH_ABBR = {
    1: "janvier",
    2: "février",
    3: "mars",
    4: "avril",
    5: "mai",
    6: "juin",
    7: "juillet",
    8: "août",
    9: "septembre",
    10: "octobre",
    11: "novembre",
    12: "décembre",
}


def _format_date_fr_jj_mmm_aaaa(value: object) -> object:
    if isinstance(value, datetime):
        dt = value.date()
    elif isinstance(value, date):
        dt = value
    elif isinstance(value, str):
        text = value.strip()
        if not text:
            return value
        dt = None
        for fmt in ("%Y-%m-%d", "%d/%m/%Y", "%Y/%m/%d"):
            try:
                dt = datetime.strptime(text, fmt).date()
                break
            except ValueError:
                continue
        if dt is None:
            return value
    else:
        return value

    return f"{dt.day:02d} {FR_MONTH_ABBR[dt.month]} {dt.year:04d}"


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
    for key in ARTICLE2_DATE_FIELDS:
        if key in normalized:
            normalized[key] = _format_date_fr_jj_mmm_aaaa(normalized[key])
    # Convert list fields to comma-separated strings for plain {{}} placeholders
    for key, val in normalized.items():
        if isinstance(val, list):
            normalized[key] = ", ".join(str(item) for item in val)
    tpl.render(normalized, autoescape=False)

    buf = io.BytesIO()
    tpl.save(buf)
    return buf.getvalue()
