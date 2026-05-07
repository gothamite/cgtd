# Google Cloud setup

You need your **own** Google Cloud project to issue OAuth tokens for this assistant. Takes 5 minutes. The project is yours; the assistant author never sees your data.

## Why your own project?

- Google forbids embedding `client_secret` values in public source repos. Each user must create their own.
- A "Testing"-mode OAuth project is capped at 100 test users — fine for you + family/friends, but not for a public-distribution shared client.
- Your project's quotas, audit log, and revocation control all stay yours.

## Step-by-step

1. **Create project.** Go to https://console.cloud.google.com/. Top-left dropdown → "New Project". Name it anything (e.g. `cgtd`).

2. **Enable APIs.** In the project, navigate to "APIs & Services → Library" and enable:
   - Gmail API
   - Google Calendar API
   - Google Drive API
   - Google Tasks API (optional, used by some skills)

3. **OAuth consent screen.**
   - "APIs & Services → OAuth consent screen".
   - User type: **External**.
   - App name: anything (e.g. `cgtd`).
   - User support email: yours.
   - Developer contact: yours.
   - On the next page, "Add or remove scopes" — add: `.../gmail.modify`, `.../calendar`, `.../drive.file`, `.../userinfo.email`, `.../userinfo.profile`. (The `workspace-mcp` server requests broader scopes by default; consult its docs if you want to limit further.)
   - **Test users:** add every Gmail address you want to authorize. Up to 100.

4. **OAuth client.**
   - "APIs & Services → Credentials → Create Credentials → OAuth client ID".
   - Application type: **Web application**.
   - Authorized redirect URI: `http://localhost:8000/oauth2callback`.
   > **⚠ Critical:** The redirect URI must be exactly `http://localhost:8000/oauth2callback`. A missing or mis-typed URI is the most common cause of OAuth failures. Double-check it before clicking Create.
   - Click create. Copy the `client_id` and `client_secret` into your `.env`:
     ```
     GOOGLE_OAUTH_CLIENT_ID=...
     GOOGLE_OAUTH_CLIENT_SECRET=...
     ```

5. **Run `/init-cgtd`** inside the container. It triggers the OAuth flow per account.

## Avoiding the 7-day refresh-token expiry

While your consent screen is in **Testing** status, refresh tokens expire after 7 days — meaning every account needs `/cgtd-reauth <email>` weekly.

To fix: "OAuth consent screen → Publishing status → Publish App". This moves you to **Production**.

**Important: «Publish to Production» does not make your app public.** It does not list the app in any Google directory, does not require Google's app verification, and does not affect who can use it. The only effect for personal use is removing the 7-day token limit.

During OAuth you will see an «unverified app» warning — this is normal. Click «Advanced → Go to *your-app-name* (unsafe)» to proceed. The warning exists for end users of public apps; for your own personal app it is safe to bypass.

You do **not** need to complete Google's app verification process. Verification is only required to suppress the warning for *other people* using a public app.

If your scopes include sensitive/restricted ones (Gmail read, Drive read), Google shows an "unverified app" warning during the OAuth flow. You can click "Advanced → Go to <app> (unsafe)" and proceed — it's *your* app, you trust it. **You do not need to complete Google's app verification process** for personal use; verification is only required if you want the warning to disappear for end users (which matters for public apps, not for you).

After publishing, refresh tokens last indefinitely (until revoked, scope-changed, or 6 months of inactivity).

## Adding a friend's account

Two options:

- **(Easy, your project)** Add their email to "Test users" in your OAuth consent screen. They authorize via your `client_id` in their own container. Up to 100 users.
- **(Cleaner, their project)** They follow this doc themselves and create their own Cloud project. Stronger isolation, no shared quotas.

## OAuth callback on a remote VPS

The OAuth redirect lands on `localhost:8000` *inside the container*. On a local machine, Docker forwards that to `127.0.0.1:8000` on your laptop — your browser hits it directly.

On a remote droplet, your browser is on your laptop, but the listener is on the droplet. Use SSH local-forward during init/reauth:

```bash
ssh -L 8000:localhost:8000 root@droplet.example.com
# in another terminal on your laptop:
ssh root@droplet.example.com 'docker compose exec gtd claude'
# then run /init-cgtd or /cgtd-reauth
```

The browser tab you open from the OAuth URL on your laptop will redirect to `localhost:8000`, which is tunneled to the droplet's container.
