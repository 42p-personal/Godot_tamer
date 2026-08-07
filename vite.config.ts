import { defineConfig, type Plugin } from 'vite'
import react from '@vitejs/plugin-react'
import { writeFileSync, mkdirSync } from 'node:fs'
import { dirname, resolve } from 'node:path'

/**
 * DEV-ONLY: POST a PNG to `/__shot?name=foo` and it lands in `.shots/foo.png`.
 *
 * ⚠️ THIS EXISTS BECAUSE SCREENSHOTS ARE UNAVAILABLE IN THIS ENVIRONMENT — the
 * browser pane does not composite, so `computer{screenshot}` times out. Every visual
 * bug this project has shipped was one that computed-style and hit-test probes pass
 * cleanly: the v0.79 z-index scrim that buried every button, a board that read as two
 * coloured blocks, `image-rendering:pixelated` shredding painted art at a 5x
 * downscale. CLAUDE.md's standing rule is that those audits are NOT sufficient, and
 * until now the only substitute was a Python renderer that re-derived the picture and
 * could therefore flatter the page it was standing in for.
 *
 * This reads back the REAL canvas the browser drew, which is the only source that
 * cannot disagree with what the user sees. It matters most for WebGL, where there is
 * no DOM to probe at all — a three.js scene has exactly one queryable property, its
 * pixels.
 *
 * ⚠️ `apply: 'serve'` — it never exists in a build. It writes files from an
 * unauthenticated POST, which is fine for a local dev server and would not be fine
 * anywhere else.
 */
function shotPlugin(): Plugin {
  return {
    name: 'dev-shot',
    apply: 'serve',
    configureServer(server) {
      server.middlewares.use('/__shot', (req, res) => {
        if (req.method !== 'POST') { res.statusCode = 405; return res.end('POST only') }
        const name = (new URL(req.url ?? '', 'http://x').searchParams.get('name') ?? 'shot')
          .replace(/[^a-z0-9._-]/gi, '_')
        const chunks: Buffer[] = []
        req.on('data', (c) => chunks.push(c as Buffer))
        req.on('end', () => {
          const file = resolve(process.cwd(), '.shots', `${name}.png`)
          mkdirSync(dirname(file), { recursive: true })
          writeFileSync(file, Buffer.concat(chunks))
          res.setHeader('content-type', 'text/plain')
          res.end(file)
        })
      })
    },
  }
}

export default defineConfig({
  plugins: [react(), shotPlugin()],
  server: { port: 5173 },
})
