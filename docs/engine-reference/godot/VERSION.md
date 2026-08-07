# Godot Engine — Version Reference

| Field | Value |
|-------|-------|
| **Engine Version** | Godot 4.7.1 |
| **Release Date** | 4.6 Jan 2026 · 4.7.1 stable (`a13da4feb`) |
| **Project Pinned** | 2026-08-03 |
| **Last Docs Verified** | 2026-02-12 |
| **LLM Knowledge Cutoff** | May 2025 |

## Knowledge Gap Warning

The LLM's training data likely covers Godot up to ~4.3. Versions 4.4, 4.5,
and 4.6 introduced significant changes that the model does NOT know about.
Always cross-reference this directory before suggesting Godot API calls.

## Post-Cutoff Version Timeline

| Version | Release | Risk Level | Key Theme |
|---------|---------|------------|-----------|
| 4.4 | ~Mid 2025 | MEDIUM | Jolt physics option, FileAccess return types, shader texture type changes |
| 4.5 | ~Late 2025 | HIGH | Accessibility (AccessKit), variadic args, @abstract, shader baker, SMAA |
| 4.6 | Jan 2026 | HIGH | Jolt default, glow rework, D3D12 default on Windows, IK restored |
| **4.7** | 2026 | **HIGH** | **The version actually installed and building this project. Undocumented here — the gap below is real.** |

## ⚠️ The pin was wrong for six months

This file said **4.6** until 2026-08-03 while `P:/Godot_v4.7.1-stable_win64.exe` — the binary
that runs `run_contract.sh` and every headless test — reported **4.7.1**. Nobody was misled
because no 4.7-specific API has been used yet; the port is pure GDScript arithmetic. That luck
does not survive contact with scenes, navigation or rendering.

**Check the binary, not this file:**

```bash
P:/Godot_v4.7.1-stable_win64.exe --version
```

⚠️ **4.7 IS BEYOND EVERY SOURCE BELOW.** The migration notes stop at 4.6, so anything
4.7-specific has to be verified against live docs rather than recalled. Treat any 4.7 API
suggestion as unverified until checked.

## Verified Sources

- Official docs: https://docs.godotengine.org/en/stable/
- 4.5→4.6 migration: https://docs.godotengine.org/en/stable/tutorials/migrating/upgrading_to_godot_4.6.html
- 4.4→4.5 migration: https://docs.godotengine.org/en/stable/tutorials/migrating/upgrading_to_godot_4.5.html
- Changelog: https://github.com/godotengine/godot/blob/master/CHANGELOG.md
- Release notes: https://godotengine.org/releases/4.6/
