"""Optional Cloudinary integration for server-side document uploads."""

from __future__ import annotations

from pathlib import Path
from typing import Any

from ..config.settings import Settings


class CloudinaryMediaService:
    def __init__(self, settings: Settings) -> None:
        missing = [
            name
            for name, value in (
                ("CLOUDINARY_CLOUD_NAME", settings.cloudinary_cloud_name),
                ("CLOUDINARY_API_KEY", settings.cloudinary_api_key),
                ("CLOUDINARY_API_SECRET", settings.cloudinary_api_secret),
            )
            if not value
        ]
        if missing:
            raise ValueError(f"Cloudinary configuration is incomplete: {', '.join(missing)}")

        import cloudinary

        cloudinary.config(
            cloud_name=settings.cloudinary_cloud_name,
            api_key=settings.cloudinary_api_key,
            api_secret=settings.cloudinary_api_secret,
            secure=True,
        )

    @staticmethod
    def upload_file(path: Path, public_id: str) -> dict[str, Any]:
        """Store an uploaded document as a private raw Cloudinary asset."""
        from cloudinary import uploader

        return uploader.upload(
            str(path),
            public_id=public_id,
            resource_type="raw",
            type="authenticated",
            overwrite=False,
        )
