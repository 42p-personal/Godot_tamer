# Dialogue — Tamer Origin

**Status:** Draft, Phase 2 of `/team-narrative` — written in parallel with world-builder
(cast/creditor naming) and art-director; not yet reconciled in Phase 4.

**Canon basis:** the decided premise (Origin A with a touch of C — the player's PARENT left a
failed-Circuit debt; Apprentice Tamer papers are the fastest legitimate way to clear it; this
is the player's own choice, never inherited destiny or prophecy). Register matches
`docs/ART_BIBLE_GUILD_COLOURS.md` (sport, not war — no chosen-one language, no cosmic stakes)
and `docs/WORLD_GUILDS.md` (trade/ledger/guild vocabulary, the Circuit, the Assay Table,
Masters/Tamer Elite/Tamers Apex as titles rather than harder grades).

**Starting state referenced:** `docs/CORE_LOOP_PORT.md` §1 — week 0, empty barn (2 stalls),
500 gold, standing in the Town. The opening scene is written to describe exactly this screen.

**Speaker:** all lines below are narrator/system voice — no named NPC. World-builder's parallel
cast pass may later attach a specific speaker (e.g. a guild clerk, a Saddler sponsor) to the
opening scene; until then these are written to work standalone, unattributed.

**Variable insertion:** `{trainer_name}` is the only placeholder used. All other text is
invariant, written for localization (no idiom, no wordplay dependent on English word order).

**Line length:** every line below is under 120 characters.

---

## 1. Opening scene

Shown at the start of a new game, as the player arrives at the empty barn / 500 gold / Town
screen. Six lines, paced to read fast — this is not a cutscene.

`[SPEAKER: narrator/system — unattributed; world-builder may assign a speaker in Phase 4]`

```
The debt in the ledger isn't yours. It's the one you're left to answer for.
Your parent fought the Circuit once, and it left an account that never closed.
Apprentice papers are the fastest honest road anyone's found to close a ledger like that.
Two stalls. Five hundred coin. Your name, freshly inked at the bottom of the page.
Sign here, {trainer_name}.
Everything after this, you earn.
```

**Design intent:**
- "the ledger" / "an account" is deliberately unnamed — the specific creditor (a guild or a
  rival stable) is left open for world-builder's parallel lore pass.
- The debt belongs to the parent's own failed Circuit run, stated plainly, never as bloodline
  obligation or destiny.
- Line 4 describes the literal screen the player is looking at (barn capacity 2, gold 500)
  rather than a generic "your journey begins" — per `CORE_LOOP_PORT.md` §1.
- `{trainer_name}` is the only variable line; every other line is fixed for localization.

---

## 2. Per-league first-entry lines

Shown once, the first time the player enters each league. Herald/announcer register — a
loading line or a herald's call, not a scene. Escalates from nerves (Wood) to institutional
weight (Masters/Tamer Elite) to the debt closing (Tamers Apex), matching each league's actual
meaning per `docs/WORLD_GUILDS.md` §1 and §5 (grades vs. titles).

`[SPEAKER: herald — unattributed]`

| league | line |
|---|---|
| Wood | Wood League. First bout, first stamp in the ledger — everyone shakes through this one. |
| Copper | Copper League. The nerves fade a little when the ledger stops looking so short. |
| Tin | Tin League. Word's getting around the yard — this stable might actually be for real. |
| Bronze | Bronze League. Alloy work now — two grades' worth of lessons, fought at once. |
| Iron | Iron League. The easy wins are behind you. This is where a stable earns its grip. |
| Silver | Silver League. The Assayers are watching properly now. So is everyone else. |
| Gold | Gold League. Guild sponsors start asking your name before the draw's even posted. |
| Platinum | Platinum League. Top of the material ladder — and the debt looks almost survivable. |
| Masters | Masters. Not a harder grade — a different word entirely. The Table calls this master work. |
| Tamer Elite | Tamer Elite. An invitation, not a ranking: sit with the Assayers, help grade the rest. |
| Tamers Apex | Tamers Apex. The last rung, and the highest anyone grades. One clean run to the Standard. |

**Design intent:**
- Wood through Gold escalate on reputation building (the yard noticing, sponsors asking) rather
  than raw difficulty language — matches the trade-apprenticeship framing in `WORLD_GUILDS.md`
  §3, not a generic power-ladder.
- Masters and Tamer Elite each use their specific in-fiction meaning (Masters = graduation /
  "master work," judged by the Assay Table; Tamer Elite = invited to sit and judge alongside
  the Assayers) rather than reading as "Platinum but harder."
- The Tamers Apex entry line sets up the payoff without spending it — it says a clean run
  stands between the player and the Standard, not that they've already won. The win itself is
  reserved for the payoff line below.

---

## 3. Tamers Apex payoff line

Shown once, at the moment the player clears the final league.

`[SPEAKER: narrator/system — unattributed]`

```
The ledger closes, {trainer_name}. The debt's settled — and now every partnership after yours gets measured against it.
```

**Design intent:**
- Closes the loop opened in the opening scene (a literal ledger debt) rather than introducing
  new stakes at the very end.
- Lands on the actual thematic prize per `docs/WORLD_GUILDS.md` §5 — becoming the reference
  other partnerships are graded against — without minting "the Standard" as a proper noun the
  player was never taught in-line; the concept is conveyed, not the term.
- No chosen-one or cosmic-stakes language; the payoff is occupational and earned, matching
  `WORLD_GUILDS.md` §4's explicit rule that every motive in this world is chosen, never destined.

---

## Open items for Phase 4 reconciliation

- **Creditor identity** — the opening scene's "ledger"/"account" is intentionally unnamed; needs
  a specific guild or rival stable name from world-builder before this is final.
- **Opening scene speaker** — currently unattributed narrator/system voice; may be reassigned to
  a named NPC (e.g. a guild clerk or Saddler sponsor) once world-builder's cast pass lands.
- **Tamers Apex line and "the Standard"** — this document deliberately avoids minting the term
  as player-facing vocabulary; flag to narrative-director if "the Standard" should be surfaced
  earlier in the run so the payoff line can use it directly instead of paraphrasing.
