# Deploying to Cloudflare Pages

The app is a **static Vite SPA** — no server code, and no hardcoded hostname (Vite builds with a
root `/` base and relative asset URLs). Cloudflare Pages serves the built `dist/` folder.
`public/_redirects` provides SPA fallback and `wrangler.jsonc` sets the project name + output dir.

## Live setup

- **Pages project:** `game` (account: Mpackman0). Default URL: `https://game-eoz.pages.dev`.
- **Git integration:** connected to `42p-personal/GAME`, production branch `main`.
  Build command `npm run build`, output dir `dist`. **Every push to `main` auto-builds & deploys.**
- **Custom domain:** `tamergame.42p.uk` (managed in the Pages project → Custom domains tab).

So the normal workflow is just: commit and push to `main`. No manual deploy step.

## Manual deploy (optional, via CLI)

Requires a Cloudflare API token with **Account → Cloudflare Pages → Edit** (and **Zone → DNS → Edit**
if adding/changing a custom domain). Then:

```bash
export CLOUDFLARE_API_TOKEN="<token>"      # bash
$env:CLOUDFLARE_API_TOKEN = "<token>"      # PowerShell

npm run deploy      # = npm run build && wrangler pages deploy  (uploads dist to project "game")
```

## Changing the custom domain

In the dashboard: **Workers & Pages → game → Custom domains** — remove the old domain and
**Set up a custom domain** for the new one. Cloudflare adds the `CNAME → game-eoz.pages.dev`
record on the zone automatically; SSL provisions in a few minutes. No code change is needed —
the app is domain-agnostic.
