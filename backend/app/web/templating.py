from pathlib import Path

from fastapi import Request
from fastapi.templating import Jinja2Templates


# Starlette enables autoescape: a username like <script> is shown as text.
templates = Jinja2Templates(
    directory=Path(__file__).parent / "templates"
)


def render(
    request: Request,
    name: str,
    context: dict | None = None,
    status_code: int = 200,
):
    response = templates.TemplateResponse(
        request,
        name,
        context or {},
        status_code=status_code,
    )
    # Admin pages show personal data: no browser or proxy copy.
    response.headers["Cache-Control"] = "no-store"
    return response
