"""Bound multipart bodies before FastAPI parses files or fields."""

import re

from starlette.responses import JSONResponse

PHOTO_ROUTE = re.compile(r"/api/v1/reports/[^/]+/photo/?")
MAX_MULTIPART_BYTES = 512_000  # 500,000 image bytes plus the multipart envelope.


class PhotoUploadLimitMiddleware:
    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if (
            scope["type"] != "http"
            or scope["method"] != "POST"
            or PHOTO_ROUTE.fullmatch(scope["path"]) is None
        ):
            return await self.app(scope, receive, send)

        chunks = []
        size = 0
        while True:
            message = await receive()
            if message["type"] == "http.disconnect":
                return
            chunk = message.get("body", b"")
            size += len(chunk)
            if size > MAX_MULTIPART_BYTES:
                response = JSONResponse(
                    status_code=422,
                    content={
                        "error": {
                            "code": "invalid_photo",
                            "message": "photo request is too large",
                            "details": None,
                        }
                    },
                )
                return await response(scope, receive, send)
            chunks.append(chunk)
            if not message.get("more_body", False):
                break

        body = b"".join(chunks)
        delivered = False

        async def bounded_receive():
            nonlocal delivered
            if delivered:
                return await receive()
            delivered = True
            return {"type": "http.request", "body": body, "more_body": False}

        await self.app(scope, bounded_receive, send)
