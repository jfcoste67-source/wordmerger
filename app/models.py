from typing import Any
import re
from pydantic import BaseModel, field_validator


class MergeRequest(BaseModel):
    template: str
    fields: dict[str, Any]

    @field_validator("template")
    @classmethod
    def validate_template_name(cls, v: str) -> str:
        if not re.match(r"^[a-zA-Z0-9_-]+$", v):
            raise ValueError("Template name contains invalid characters")
        return v
