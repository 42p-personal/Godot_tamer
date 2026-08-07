#!/usr/bin/env python3
"""Route A of the art pipeline — OpenAI images API (see docs/ART_PIPELINE.md).

    python3 tools/gen_image.py "<prompt>" out.png [--size 1024x1024] [--opaque]

`gpt-image-1` with `background: transparent` returns NATIVE ALPHA, so the
output needs no flood-fill and carries no white halo. That is why this is the
preferred route when it is available.

Known failure: `billing_hard_limit_reached` — a hard account cap that is NOT
avoided by a cheaper size or quality. On that error, fall back to Route B
(the codex CLI); this script says so explicitly rather than failing silently.
"""
import base64
import json
import os
import sys
import urllib.error
import urllib.request

API = 'https://api.openai.com/v1/images/generations'


def main() -> int:
    args = [a for a in sys.argv[1:]]
    if len(args) < 2:
        print(__doc__)
        return 2
    prompt, out = args[0], args[1]
    size = '1024x1024'
    if '--size' in args:
        size = args[args.index('--size') + 1]
    background = 'opaque' if '--opaque' in args else 'transparent'

    key = os.environ.get('OPENAI_API_KEY')
    if not key:
        print('ERROR: OPENAI_API_KEY is not set. See docs/ART_PIPELINE.md.')
        return 1

    body = json.dumps({
        'model': 'gpt-image-1',
        'prompt': prompt,
        'size': size,
        'background': background,
        'n': 1,
    }).encode()
    req = urllib.request.Request(API, data=body, headers={
        'Authorization': f'Bearer {key}',
        'Content-Type': 'application/json',
    })
    try:
        with urllib.request.urlopen(req, timeout=300) as r:
            payload = json.load(r)
    except urllib.error.HTTPError as e:
        detail = e.read().decode()[:500]
        if 'billing_hard_limit_reached' in detail:
            print('BLOCKED: billing_hard_limit_reached — the API account is hard-capped.')
            print('Fall back to Route B (codex CLI). See docs/ART_PIPELINE.md.')
            return 3
        print(f'HTTP {e.code}: {detail}')
        return 1

    with open(out, 'wb') as f:
        f.write(base64.b64decode(payload['data'][0]['b64_json']))
    print(f'OK -> {out}  ({size}, background={background})')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
