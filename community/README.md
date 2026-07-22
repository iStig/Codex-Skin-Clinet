# Dream Skin Community Gallery

The community gallery uses GitHub Issues and GitHub-hosted attachments in `iStig/Codex-Skin-Clinet`. It does not require a Dream Skin server, storage account, API key, or anonymous upload endpoint.

## Submission flow

1. In the macOS App, open **Online Gallery → Community → Submit Wallpaper**.
2. Sign in to GitHub and attach one JPG, PNG, or WebP to the issue form.
3. Confirm authorship and choose CC0, CC BY 4.0, or CC BY-SA 4.0.
4. A maintainer verifies image dimensions, file size, source rights, and suitability.
5. An approved item is added to `community/catalog.json`; every client can then load and download it.

The client accepts only attachment URLs under `github.com/user-attachments/assets/`, repository raw files, and issue source pages in this repository. Catalog entries are capped at 50 MB and must be landscape images of at least 1920x900.

## Catalog entry

```json
{
  "id": 1000001,
  "title": "Example Wallpaper",
  "originalURL": "https://github.com/user-attachments/assets/UUID",
  "thumbnailURL": "https://github.com/user-attachments/assets/UUID",
  "detailsURL": "https://github.com/iStig/Codex-Skin-Clinet/issues/123",
  "width": 2560,
  "height": 1440,
  "byteCount": 2450000,
  "artist": "GitHub username",
  "license": "CC BY 4.0",
  "fileExtension": "jpg"
}
```

GitHub is a pragmatic zero-cost community backend, not an unlimited image CDN. If traffic or moderation volume grows beyond repository limits, migrate the same catalog schema to an object-storage free tier with authenticated uploads.
