from abc import ABC, abstractmethod
from dataclasses import dataclass


@dataclass(frozen=True)
class ValidatedImage:
    """Validated content and metadata established from the image bytes."""

    content: bytes
    mime_type: str
    size_bytes: int


class ImageValidator(ABC):
    """Application boundary for validating an uploaded image."""

    @abstractmethod
    def validate(
        self,
        content: bytes,
        declared_mime_type: str | None = None,
    ) -> ValidatedImage:
        """Validate image bytes and return trusted metadata."""

        pass
