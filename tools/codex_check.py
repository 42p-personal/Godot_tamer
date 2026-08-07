"""Pre-flight for codex image generation. RUN THIS FIRST, before a batch.

Why this exists: on 2026-07-27 generation began returning `403 Forbidden` with
no useful detail, and it was misdiagnosed for two days as a prompt problem, a
flag problem and a quota problem. The real cause was a lapsed ChatGPT
subscription. This check exists so that failure is one command to identify.

    python3 tools/codex_check.py

Exit 0 = generation actually worked just now, safe to batch.
Exit 1 = it failed; the reason is printed. Do not start a batch, do not debug
prompts.

⚠️ WHY THIS DOES A REAL GENERATION rather than reading the token.
The token's `chatgpt_subscription_active_until` claim is a SNAPSHOT from the
last server check (`last_checked`), NOT live truth — the server decides
entitlement at request time. Observed 2026-07-28: the cached claim still said
"expired 2026-07-27" while a real generation SUCCEEDED, because the subscription
had been renewed and the server honoured it even though the cached token was
stale. So the claim gives false negatives (and could give false positives).

The token is therefore only a HINT, printed for context. The authoritative
signal is whether a tiny image actually comes back. That costs ~30-60s and one
trivial generation, which is the right price before committing to an hours-long
batch of 260.
"""
import base64
import datetime
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile

AUTH = os.path.expanduser('~/.codex/auth.json')
GEN = os.path.expanduser('~/.claude/skills/gpt-image-2/scripts/gen.sh')


def hint_from_token():
    """Best-effort context from the cached token. Never authoritative."""
    if not os.path.exists(AUTH):
        return 'not logged in (no ~/.codex/auth.json) — run: codex login'
    try:
        d = json.load(io.open(AUTH, encoding='utf-8'))
        tok = (d.get('tokens') or {}).get('id_token')
        payload = tok.split('.')[1]
        payload += '=' * (-len(payload) % 4)
        auth = json.loads(base64.urlsafe_b64decode(payload)).get('https://api.openai.com/auth', {})
        plan = auth.get('chatgpt_plan_type', '?')
        until = auth.get('chatgpt_subscription_active_until', '?')
        checked = auth.get('chatgpt_subscription_last_checked', '?')
        return f'plan={plan}  cached-window-until={until}  (snapshot from {checked}; not live)'
    except Exception as e:
        return f'token unreadable ({e})'


def main():
    if not shutil.which('codex'):
        print('  BLOCKED: the codex CLI is not on PATH')
        print('  FIX:     install it — https://github.com/openai/codex')
        return 1

    print(f'  hint:  {hint_from_token()}')
    if not os.path.exists(GEN):
        print(f'  BLOCKED: generation wrapper missing at {GEN}')
        print('  FIX:     install the gpt-image-2 skill')
        return 1

    print('  probe: generating one trivial image (the only authoritative test)…')
    out = os.path.join(tempfile.gettempdir(), 'codex_check_probe.png')
    if os.path.exists(out):
        os.remove(out)
    try:
        r = subprocess.run(
            ['bash', GEN, '--prompt',
             'a single small red circle centred on a plain solid white background',
             '--out', out],
            capture_output=True, text=True, timeout=300,
        )
    except subprocess.TimeoutExpired:
        print('  BLOCKED: probe timed out after 300s (network? codex hung?)')
        return 1

    ok = os.path.exists(out) and os.path.getsize(out) > 1000
    if ok:
        kb = os.path.getsize(out) // 1024
        print(f'  READY: probe produced a {kb}KB image — generation works.')
        return 0

    # Failed — surface the cause, not the whole log.
    tail = (r.stderr or r.stdout or '').strip().splitlines()
    reason = next((ln for ln in reversed(tail) if '403' in ln or 'error' in ln.lower()), '')
    print('  BLOCKED: the probe produced no image.')
    if '403' in reason or 'Forbidden' in reason:
        print('  CAUSE:   403 Forbidden — the ChatGPT subscription is almost certainly')
        print('           lapsed or lacks image-gen entitlement. `codex login status`')
        print('           will still say "Logged in" — that is not the signal.')
        print('  FIX:     renew the ChatGPT subscription, then re-run this check.')
        print('           (A renewal takes effect on the NEXT generation — the cached')
        print('           token window can still read stale, which is fine.)')
    elif reason:
        print(f'  DETAIL:  {reason[:200]}')
    return 1


if __name__ == '__main__':
    sys.exit(main())
