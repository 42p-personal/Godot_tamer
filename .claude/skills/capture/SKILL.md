---
name: capture
description: "Capture and actually LOOK AT the game's screens — windowed, across both fixtures, with timestamps checked — and report what you saw rather than what the code says. Use after any UI change, before claiming a visual fix worked, when judging whether something reads as a prototype, and whenever a round's acceptance is settled by eyes rather than by a probe. A round that reports 'improved the layout' without a capture has reported nothing."
argument-hint: "[screen-name | all | --fixture A_comfortable|B_thin]"
user-invocable: true
allowed-tools: Bash, Read, Glob, Grep
model: sonnet
---

# Capture

Visual work is judged by eyes. A probe can tell you a label is 12px; it cannot tell you the
screen looks like a debug tool. **Every visual finding worth having in this project was found by
looking at a PNG**, including four defects in one round that no probe reported.

---

## Run it

```bash
cd G:/p42.uk/monster-tamer-3d/monster-tamer
"P:/Godot_v4.7.1-stable_win64.exe" --path . scenes/_probe_screens.tscn
```

⚠️ **NO `--headless`.** The dummy renderer returns blank frames and the harness will save black
rectangles and report success. The probe's own header says so.

Output lands in:

```
C:/Users/P/AppData/Roaming/Godot/app_userdata/Monster Tamer/screens/<fixture>/NN_<name>.png
```

Two fixtures, and **both matter**:

- **`A_comfortable`** — a five-body Bronze stable at week ~130. Everything is fine, so any panel
  that only appears under pressure renders its EMPTY state here.
- **`B_thin`** — a struggling stable. This is where the market's gap panel, the frontier warnings
  and the short-handed states actually fire.

⚠️ **The fixture split exists because a single-fixture harness manufactured a wrong brief.** It
preserved only ONE parent, so Breeding could only ever be photographed empty, and a round was
briefed on a defect that was the harness's. Round 19's biggest feature was then invisible in its
own headline capture for exactly the same reason.

---

## ⚠️ CHECK THE TIMESTAMP BEFORE YOU READ ANY PNG

```bash
ls -l --time-style=+%H:%M "C:/Users/P/AppData/Roaming/Godot/app_userdata/Monster Tamer/screens/A_comfortable/13_ending.png"; date +%H:%M
```

**This cost three consecutive wrong conclusions.** A fix worked on the first attempt; the capture
being read was two hours old at a path nothing writes to any more; two further edits were made
against it and each re-run "confirmed" the failure. The probe now sweeps its own root, but the
habit is the real protection.

**A capture you did not just produce is not evidence.**

---

## Then actually look

Read the PNGs back with the Read tool. For each screen, answer:

1. **What is the player here to DECIDE, and can they?** Not "is the information present" — can
   they act on it without hunting.
2. **Does it read as one game with the others?** Put three screens side by side. The tell is
   usually rhythm rather than colour: identically-shaped stacked panels with a gold heading each
   read as a colour cast even when the ink measures fine.
3. **What is on screen that serves nothing?** Round 18 found the Stable's six stat bars — the
   primary readout of a monster-taming game — pushed below the fold by a four-line biography.
4. **Does anything clip, orphan or overlap?** Clipped placeholders ("Formation nam"), help text
   cut mid-sentence, nameplates floating above capped bodies, a guide panel covering two buttons.
5. **Is anything on screen a lie?** The hardest and most valuable question — see below.

---

## The class of bug only a capture finds

- a scoreboard that **announced the winner at frame 0** and disagreed with the frame in 100% of frames
- a stable screen promising **stat ceilings the tick never applied**
- the same ceiling contradiction surviving in **three separate venues**, caught by putting two
  captures side by side
- an evidence line reading "100% of your damage went into X (an even spread would be 100%)" —
  **both figures true by construction**
- a severity glyph rendering as **tofu** because the codepoint was not in the packaged font
- a legend row widening 40% after a font bump, pushing a whole column **off the viewport**, while
  the style probe went green in the same run

**Compare a number on one screen against the same number on another.** That is how three of these
were caught, and no probe was going to find them.

---

## Reporting

Say what you **saw**, screen by screen, and name the screens that did *not* improve as plainly as
the ones that did. Round 21's most useful sentence was "tactics is now the worst screen in the
game" — about a screen that had just been polished, where the polish made the contrast worse.

Pair the impression with a number where one exists (`_probe_house` gives off-scale labels,
off-token colours, below-floor labels, clipping and nine contrast floors), but **do not let a
green probe overrule your eyes** — the probe measures what it was told to measure.
