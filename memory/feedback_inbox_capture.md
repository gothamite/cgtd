---
name: Inbox capture behavior
description: Inbox is a capture bucket — save verbatim, no immediate questions, handle attachments by size and MIME type
type: feedback
---

**Inbox = capture bucket.** When routing anything to Notion Inbox, do NOT ask the user clarifying questions first. Save it, then let process-inbox classify later.

**Save verbatim.** Store the original text exactly as received. Do not paraphrase, summarize, or reformat.

## Attachment handling

### ≤20 MB

1. Download via Telegram Bot API.
2. Upload to Google Drive folder `config.google.drive_inbox_folder_id` (primary account).
3. Set file permission to public read.
4. Add a content block to the Notion Inbox page body based on MIME type:

| MIME type | Notion block | URL pattern |
|-----------|-------------|-------------|
| `image/*` | `image` block | Use lh3 CDN: `curl -sI "https://drive.google.com/thumbnail?id={id}&sz=w2000"` → follow redirect → URL of the form `https://lh3.googleusercontent.com/...`. Do NOT use `uc?export=view` — it does not render in Notion. |
| `video/*` | `video` block | `https://drive.google.com/file/d/{id}/preview` |
| `audio/*` | `audio` block | `https://drive.google.com/file/d/{id}/preview` |
| `application/pdf` | `pdf` block | `https://drive.google.com/file/d/{id}/preview` |
| other | `file` block | use `webViewLink` from Drive API response |

### >20 MB

Create the Inbox entry with the filename and file size noted in the body. Send a Telegram message asking the user to upload the file manually to Drive and share the link.

**Why:** Notion image blocks require a direct CDN URL. Drive's `uc?export=view` redirects to a login page when embedded. The lh3 CDN URL obtained via redirect works reliably.
