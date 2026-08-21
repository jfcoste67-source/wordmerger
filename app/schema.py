import json
from functools import lru_cache
from pathlib import Path
from typing import Any

SCHEMA_DIR = Path(__file__).parent.parent / "schemas"


@lru_cache(maxsize=64)
def load_schema(template_name: str) -> dict[str, Any]:
    schema_path = SCHEMA_DIR / f"{template_name}.json"
    if not schema_path.exists():
        raise FileNotFoundError(f"Schema '{template_name}' not found")

    with schema_path.open("r", encoding="utf-8") as f:
        schema = json.load(f)

    fields = schema.get("fields")
    if not isinstance(fields, dict):
        raise ValueError(f"Invalid schema '{template_name}': fields must be an object")

    return schema


def get_required_fields(template_name: str) -> set[str]:
    schema = load_schema(template_name)
    fields: dict[str, Any] = schema["fields"]
    return {
        name.upper()
        for name, meta in fields.items()
        if isinstance(meta, dict) and bool(meta.get("required", False))
    }


def get_allowed_fields(template_name: str) -> set[str]:
    schema = load_schema(template_name)
    fields: dict[str, Any] = schema["fields"]
    return {name.upper() for name in fields.keys()}
