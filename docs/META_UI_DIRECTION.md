# The meta-game — UI direction and the round's build order

**2026-08-11.** Written from the first end-to-end look anyone has taken at the management half of
this game. Thirteen screens, one shared mid-career career, captured at 1152×648 and read back.

> *"we need to clean up the ui in every screen and improve the loop, outside of the arena the game
> is very much incomplete, use monster rancher and teamfight manager 2 as your inspirations, fan
> out and improve everything"* — the user, this round

The harness is `monster-tamer/scripts/_probe_screens.gd` + `scenes/_probe_screens.tscn`. It drives
one Bronze-league, week-130, five-monster career through every player-facing screen outside the
arena and writes `user://screens/NN_<name>.png`, plus `_end.png` for any screen whose content runs
past the fold. **Re-run it before and after every change in this round.** It runs with a window,
never `--headless` — the dummy renderer saves black rectangles and "passes".

```
P:/Godot_v4.7.1-stable_win64.exe --path . res://scenes/_probe_screens.tscn
```

---

## 0. The brief was right about the disease and wrong about one symptom

**Right:** the meta-game has had a fraction of the investment the arena has, and it shows the
moment you look at thirteen screens in a row instead of one at a time.

**Wrong, and worth correcting before anyone acts on it:** *"the management game has been carried
by whatever was quickest"* is not what the captures show. The management screens are **thoughtful
and under-designed**, which is a different disease with a different cure. `training_ui.gd` runs
the real tick on a clone to print an exact preview and shows the whole multiplier chain.
`tournament_ui.gd` prints every cup's per-round archetype, the champion's name and a genuine
counter-read. `stable_ui.gd` shows aptitude, focus cost, and which class each drill opens.
`week_plan.gd` snapshots the multiplier chain *before* the tick so the feeding ledger can explain
itself. That is not quick work. **The content is largely right and the ARRANGEMENT is largely
wrong** — which is good news, because rearranging is cheaper than authoring.

Two corrections to the measurements in the brief, both from the captures:

- **`shop_ui`'s two "silent disabled buttons" are not a rule-3 violation.** The probe flags a
  disabled button with no tooltip; those two carry their reason in the button *label* — `"Locked —
  reach Iron league (you are Bronze)"`. That is better than a tooltip, not worse. The probe's
  check is the thing that needs fixing, and it has been noted in the file.
- **The line-count ratio understates the arena and overstates the neglect.** `arena_3d.gd` is
  5,859 lines because it is a renderer; `shop_ui.gd` is 200 lines because a shop is three rows.
  The honest measure is what the screen lets you decide, and §2 uses that instead.

---

## 1. What I actually saw — screen by screen

Each entry: what the player is here to **decide**, whether they **can**, and what is in the way.
Quotes are lifted verbatim from the captures.

### 01 title — `01_title.png`
**Decide:** continue or start. **Can they:** yes. The single best-looking screen in the game — a
full-bleed painted arena, `MONSTER TAMER`, `"You run the stable. The stable fights."`
**In the way:** four identical grey buttons stacked in the lower-left corner at body size, over
the best art in the project. `Continue` says nothing about the career behind it — no week, no
league, no roster. The one screen with a real establishing shot spends none of it on the career.
**Also:** it is the only screen whose root does not scroll (`UI_LAYOUT_RULES` rule 1). At a fixed
four-button menu that is defensible; note it rather than fix it.

### 02 town — `02_town.png`
**Decide:** where to go this week. **Can they:** yes, and the pace strip is genuinely good —
`"Week 130, holding Bronze. Ilse Varra is at Gold. They were here 1 season before you."` over a
two-row ladder track (you / Varra). That is the season made present, on the screen you pass
through most, and it works.
**In the way:** **the bottom 52% of the hub is empty black.** Seven cards, four columns, ~250px of
a 648px screen, then void. The hub of a management game shows nothing about the stable it manages
— no roster glance, no "three of your five have no plan", no "the Bronze Cup is this month", no
gold trend. It is a door menu with a good banner on top.
**And one lie:** `Hall of Fame · 🔒 not yet built`. `lab_ui.gd`'s own header says *"IT IS ALSO THE
HALL OF FAME, DELIBERATELY, AND NOT A TROPHY CASE."* The town says a shipped feature does not
exist. That is signature failure #2 inverted and it costs one line to fix.

### 03 stable — `03_stable.png`, `03_stable_end.png`
**Decide:** which monster to invest in, and what it is becoming. **Can they:** eventually — the
content is there and it is strong. Portrait, body, class-as-commitment with three Assign buttons
and an honest warning, temperament as four named axes (`Ice in its veins`, `Attentive`), and below
the fold a per-stat push-drill summary (`STR +36 STR, -7 DEX, -5 WIS (aptitude ×1.10, focus ×0.98)
→ opens Captain`), the moveset by line, and the innates.
**In the way, and this is the ranking error of the round:** the **six stat bars — the primary
readout of a monster-taming game — straddle the fold**, and above them sits a four-line lore
paragraph (`Story`). At 1152×648 you see the portrait, the story, the temperament, and half a
class panel. You do not see a single stat. Monster Rancher's stable screen is a *condition
readout*; this is a *biography*.
**Roster strip:** five cards, every one reading `● Growing`. Five monsters aged 1 to 7 years, and
the at-a-glance column says the same word five times. No age, no stamina, no happiness, no
"unplanned". The life arc — the drama the whole reference is built on — is invisible in the one
place it should live.
**Cross-screen contradiction (rule 1, and it is real):** the stable's stat bars read `115 / 540`.
The training screen, same monster, same week, reads `115 / 400` and the header says
`Bronze ceiling 400`. Both numbers are defensible (`stat_ceiling`'s class-spike headroom vs the
nominal cap) and that is exactly the problem — the player sees two different caps for one stat.

### 04 training — `04_training.png`, `04_training_end.png`
**Decide:** which of thirty drills this week. **Can they:** no, and the reason is arrangement, not
information. Every card is honest and exact — `Weight Training → +6 net`, a live bar, `on paper:
+6 STR`, and the chain `STR: natural aptitude ×1.10 · STR already leads this build — focus cost
×0.98`. That is the best training preview this project has ever shipped.
**In the way:** **6,071px of single-column scroll, 43 buttons, ~130px per card.** Choosing between
STR and CHA means scrolling four screen-heights and holding two numbers in your head. The decision
the design calls the heart of the stable half is a decision the layout makes impossible to
*compare*. The old React `RanchView` condensed this into six columns by stat for exactly this
reason, and that did not survive the port.
**Also:** nine food buttons and a Forage row sit *above* all thirty drills, so the first screenful
of the training screen is the feeding decision. Two decisions stacked in one scroll, wrong one
first.

### 05 feeding — `05_feeding.png`
**Decide:** nothing. It is a ledger, and it is a good one — `Cobalon · Acrobatics · ate unfed ·
+17 DEX -5 CON · why: Fully Grown ×1.15 · DEX focus cost ×0.99 · -25 stamina · -1 happiness`. The
`why` chain matches the number above it, which is the rule-1 bar and it clears it.
**In the way:** it is called *Feeding* and it feeds nobody — food is chosen on the Training screen,
a week earlier. The name is a fossil of `town.ts`'s sequential feeding phase. Also: every monster
in the capture reads `ate unfed`, because nothing on any screen makes choosing food feel like a
step you owe. And 20% of the screen is void below a five-row list.

### 06 market — `06_market.png`
**Decide:** buy which recruit, at the cost of which stall. **Can they:** partly. The offer cards
are well-informed — `Mosshorn — Veteran · now 260/stat · ceiling 328 (×0.82) · 4y left of 8y ·
trains: STR ×1.20, CHA ×1.10, INT ×0.80 → trains toward Captain`. Grade tiers, remaining career,
aptitude, destination class. Good.
**In the way:** **the portraits are ~28px.** Sixty-five species of real generated art and the
recruiting screen renders them as thumbnails beside a wall of 11px text. The right column ("Your
stable") lists what you would release with a refund and *nothing about what you would lose* — no
stats, no age, no role — so the actual decision (is this recruit better than the body I would drop
for it?) has its two halves rendered in two incomparable formats. And 40% void.

### 07 shop — `07_shop.png`
**Decide:** barn slot vs licence. **Can they:** yes, in three rows, and the copy is excellent:
`Room for one more monster. ⚠ Team leagues need bodies — Bronze fields 3, Platinum fields 5, and a
cup you cannot field a team for is a cup you cannot enter.`
**In the way:** the entire gold sink of the game is three rows and then 55% empty screen. There is
no sense of a shop, no sense of what gold is *for* across the campaign, no forward view (what does
2,200g buy me later?). The economy's only outlet reads as a settings page.

### 08 lab — `08_lab.png`, `08_lab_end.png`
**Decide:** which monster leaves competition to become bloodline. This is, per its own header,
*"the decision at the centre of the meta-game."*
**In the way:** **two dense paragraphs of essay before any control** — `"THE BILL IS FOR THE
OPTION, NOT THE STORAGE. Preserve a monster that could still be racing and the freezer charges 12g
every week, forever..."` — set in ~11px muted grey, occupying the top quarter. Then text rows.
**No portraits at all.** Every row reads `potential ×1.00 · Wild stock — Gen 1`, identical across
five monsters, so the screen shows no reason to prefer one. A decision billed as the centre of the
meta-game is rendered as an FAQ with buttons.

### 09 breeding — `09_breeding.png`
**Decide:** which two parents. **Can they:** **no.** One eligible stud in the book; every barn row
reads `potential ×1.00 · Wild stock — Gen 1`, i.e. identical. **No portraits. No preview of the
foal.** The screen about lineage and inheritance shows neither lineage nor inheritance — you
cannot see what the child would get, so "which two" is a coin flip dressed as a decision.
This is the weakest screen in the game measured by decision-served-per-pixel.

### 10 tournament — `10_tournament.png`, `10_tournament_end.png`
**Decide:** which cup, and whether to spend the week. Best-informed screen in the meta-game.
`Bronze Cup · your league · 3v3 · 3 teams in the draw · stat ceiling 400 · entry 48g · winner's
purse 640g`, then per round `Round 1 attrition 47% of the Bronze ceiling [##·-]`, then
`Title held by Dunnal Bray, Bellfounder. Opens wide. Everything hits everyone, so a tight formation
gives them the whole team for free.`
**In the way:** it is **all prose, stacked**. Three cups, each a tall text block; comparing them
means reading 40 lines. `[##·-]` is an ASCII bar pretending to be a chart. The real cost — *"The
trip costs 1 week of game time — your stable ages, eats and rests on the road, but nobody trains"*
— is a sentence in a paragraph, not a price on the button.
**And the season is missing.** `cup_run.gd` ships a full calendar: 13 months per game year, five
named marquee events (`The Silver Assay`, `The Gilt Chain`, `The White Circuit`, `The Masters'
Round`, `The Elite Convocation`), a deterministic month per league per year, `MARQUEE_PURSE_MULT
1.75`. **No screen renders any of it.** Authored and unreached, signature failure #2, and it is the
single largest piece of finished content the meta-game is sitting on.

### 11 tactics — `11_tactics.png`, `11_tactics_end.png`
**Decide:** the orders you will not be able to change. Two columns, standing orders with real
descriptions, a formation board with saved presets, the scouted rival with a counter-read
(`Guard is FLAT reduction per hit, so chip damage is worth nothing against them`), per-monster
overrides, and `YOUR READ — the report will grade exactly these`. **This is the best screen in the
project outside the arena and it is the model the others should be measured against.**
**In the way:** the left column is cramped — the formation board is 550px wide with a five-item
legend in ~8px type, below the accessibility floor. The per-monster orders strip is its own nested
scroll showing 2 of 3 monsters (rule 5). And **in neither capture is a commit control visible** —
the screen says `Orders are live until you commit` with nothing on screen to commit with. Verify
that at 1152×648 before assuming it is fine; if it is below the fold that is a rule-2 failure on
the most important button in the game.

### 12 report — `12_report.png`
**Decide:** nothing — it is the observe half, and its job is to tell you whether the read was
right.
**In the way:** the largest type on the screen reads **`THE READ COULD NOT BE GRADED`**, above
`◆ VICTORY`. ⚠️ **Caveat, honestly: that is partly my fixture.** `report_ui.gd` runs a headless
demo battle when no real fight is pending, and a demo has no frame stream to grade against, so
this exact headline will not appear after a real cup round. What is *not* a fixture artifact is
the **hierarchy**: the grading apparatus is the headline and the result is a subhead, and the
per-monster rows carry only `dealt 180 · took 347` plus a collapsed `Orders & decision log`. The
screen that is supposed to close the loop leads with its own machinery.

### 13 ending — `13_ending.png`
**Decide:** nothing. **And it is the second-best screen in the game.** `TAMERS APEX — TAKEN`, a
`CHAMPION / score 1596` panel with the pace comparison (`The Varra stable takes it in week 420.
You were 48 weeks quicker.`), an 11-rung climb bar with the arrival week under each rung, a
five-tile career numbers row, and **`The Ones Who Did It` — the roster as portrait cards with age,
class and three key stats.**
**In the way:** nothing, except that **it exists once, at the end.** That roster card grid is the
only place in the entire game where the stable is shown as portraits + stats + age together, and
it is on the screen the player sees after they have stopped playing.

### Cross-screen: the tutorial banner
`TutorialOverlay` is a `CanvasLayer` autoload at `layer = 100`, pinned bottom-right on **every**
screen — including the title screen and the ending screen. It does not eat clicks (that is
correctly handled) but it **overlaps the primary action rail** on shop, breeding, feeding, lab and
report, and it shows `"Decide what it eats"` while the player is on the title screen. It should
mute on screens its step does not concern, and it should not overlap a bottom rail.

---

## 2. Where the loop goes slack

Walking it as a player, not as a screen list.

**Slack point 1 — the week has no felt cost, so it is not a decision.** The Training screen prints
`+6 net` and `−15 stamina`, both true, both exact. But nothing on any screen tells the player what
they *gave up*: the week they did not rest, the week they did not enter the cup, the four weeks of
the monster's remaining career that this drill consumed. `Rosewing` is 7.0 of 8.0 years old and
neither the stable card nor the training header says so. **Monster Rancher's whole drama is that
your best monster is dying**, and the life arc is present in the data (`age_weeks`,
`lifespan_years`, `stage_info`) and absent from every surface except the ending screen's
`7.0 yrs`. Make the clock cost visible and the training week becomes a decision without changing
one number.

**Slack point 2 — food is a chore appended to training.** Nine buttons, above the drills, on the
wrong screen, and the capture shows all five monsters `ate unfed` with no consequence louder than
`−1 happiness`. Favourite/hated foods exist per monster (`favourite_food`, `hated_food`) and no
screen shows them. Either surface the preference and make feeding a small real choice, or fold it
into the drill card as one line and stop pretending it is a phase.

**Slack point 3 — nothing accumulates between cups.** You enter a cup, you fight three rounds, you
get a result, and the world is exactly as it was. No standings, no rivalry, no record, no
calendar. The Varra pace strip on the town screen is the *only* thing in the meta-game that
persists across weeks and it is three lines. TFM2's season is a container the player lives inside;
this is a series of disconnected fixtures, exactly as the brief says.

**Slack point 4 — the two halves of the loop do not use the same words in the same places.** The
Read commits `🎯 Hunt the casters`; the report grades it; the stable never mentions it; the
training screen never says which stat serves it. A player who learns from a report has nowhere to
spend the lesson except by remembering it across four screens.

**Slack point 5 — the breeding half is unreachable in practice.** Breeding requires two preserved
parents; preserving costs 12g/week forever and takes a monster out of competition; the Lab renders
that trade as an essay and the Breeding Ranch renders the outcome as nothing at all. The
generational game — the thing CLAUDE.md calls *"how you build the answer you will need"* — has the
weakest two screens in the project guarding it.

---

## 3. The target

### 3.1 The two references, applied

**Monster Rancher is the WEEK.** Take: the stable as a *condition readout* not a biography; a
monster as a character with visible mood and visible age; the week as a choice with a felt cost;
the life arc as a story the UI tells continuously, not once at the end.

**Teamfight Manager 2 is the SEASON.** Take: information density without clutter (grids and rows
that compare, not stacked prose blocks); scouting as a real beat *before* commitment — which this
game already does better than TFM2 on the tactics screen; the season as a container you live
inside.

### 3.2 What each screen is FOR, in one sentence

| screen | one sentence | must show |
|---|---|---|
| title | The career you are returning to. | week, league, roster count, the pace line — on `Continue` |
| town | Where the stable stands this week, and the one thing worth doing about it. | pace strip (keep), roster condition strip, what's on this month, gold |
| stable | Which body is worth this week's investment. | six stat bars vs cap **above the fold**, age/stage, stamina, happiness, plan status |
| training | Which of six stats, compared side by side. | six columns, one per stat, exact preview per option, the week's cost |
| feeding *(rename: The Week)* | What last week cost and taught. | the ledger it already has (it is right) |
| market | Whether this recruit beats a body you already own. | large portraits, and the same stat readout on both sides of the comparison |
| shop | What gold is for, across the whole climb. | the ladder of purchases, not just the two affordable now |
| lab | Which monster stops racing to become bloodline. | portraits, potential and heirloom **differentiated**, the bill as a number not a paragraph |
| breeding | Which two parents, and what the foal would be. | portraits, parent stats side by side, a **foal preview** |
| tournament | Which cup, at what price, against whom. | a season calendar with the marquee events, cups as comparable rows, the week-cost on the button |
| tactics | The orders you cannot change once it starts. | keep it; fix the legend size, the nested scroll, and prove the commit button is above the fold |
| report | Whether the read was right. | the result first, the grade second, per-monster with the words the tactics screen used |
| ending | What the climb was worth. | keep it; it is the reference |

### 3.3 The biggest structural gap — and my answer, argued both ways

**The question:** TFM2 lives in its standings table. This game has no standings table, no season
container, no hall of fame. Is a table the right spine?

**The case FOR a standings table:** it is the single strongest thing TFM2 does. It gives every
match a consequence beyond its own result, it makes rivals persistent, it lets a player answer
"how am I doing" without being told, and it turns a series of fixtures into a season. Every
complaint in §2 slack-point 3 is a complaint a table would answer.

**The case AGAINST, and it is the one I take:** a standings table needs a *field that keeps
playing when you are not*. TFM2 is a round-robin league — everyone plays everyone, the table is
the season's true state, and your rivals' results accumulate whether you watch or not. This game
is a **promotion ladder**: you enter a cup, win 2 of 3 rounds, promote, and the field is *drawn
fresh per cup* (`Career.make_cup_field()`, seeded off the league). There is no standing field. A
standings table here would either be fabricated — rows of results nobody played, which is precisely
rule (1), a screen lying about the thing it describes — or it would be a single-row table of your
own cup history, which is a log, not a table.

**So: not a standings table. A LADDER BOARD — and most of it is already built.**

The *job* the table does (persistent, named, comparative, lived-in) is real and unmet. This game's
own structure serves it better than a fabricated league would:

- **11 rungs, each with an authored champion** who has a name and a read line
  (`Dunnal Bray, Bellfounder`, `Sable Roke, the Tinsmith`, `Merrin Kell, the Kettle Queen`).
- **A live pace-setter** — the Varra stable, on an authored schedule, whose rung moves with the
  week. That is a rival that keeps playing while you are not, which is exactly what a table
  provides and this game already has.
- **A calendar** — 13 months, five named marquee events, deterministic per year — sitting unused
  in `cup_run.gd`.

The Ladder Board is one screen: eleven rungs down the page, each showing the champion's portrait
and name, taken/held/ahead-of-you, the Varra marker moving down it, and the marquee events pinned
to the months they fall in. **`town_ui.gd:_ladder_track()` and `ending_ui.gd`'s climb bar are
already two-thirds of it** — the ending screen's version is the best-looking thing in the
meta-game. Promote it from an epilogue to a permanent destination and the season has a container
without one fabricated row.

**Hall of Fame:** do not build it. `lab_ui.gd` already *is* it and says so in its own header.
Relabel the Lab's preserved section, unlock the town door, and point it there. One line of work
to convert a lie into a feature.

---

## 4. The three builder briefs

Ranked ruthlessly, and the ranking is honest about this: **a beautiful screen for a decision that
does not matter is worth less than a plain screen for one that does.** Every P1 below is a screen
where the player currently *cannot make the decision the screen exists for*. Every P3 is polish
and should be dropped without argument if the round runs long.

Acceptance criteria are written so `_probe_screens.gd` can settle them — a before/after capture
pair, read back, is the evidence. **Capture before you change anything.**

### Builder A — THE WEEK (`stable_ui.gd`, `training_ui.gd`, `feeding_ui.gd`)
*Monster Rancher. The stable is a place, the monster is a character, the week has a cost.*

**A1 (P1) — Stats above the fold on the stable.** Move the six stat bars directly under the
portrait; demote `Story` to a collapsed disclosure or a single line. *Accept:* in
`03_stable.png` at 1152×648, all six stat bars are visible without scrolling.

**A2 (P1) — Training becomes six columns, not one 6,000px scroll.** One column per stat, each
holding that stat's basic/intensive/extreme options as compact cards, so two stats can be compared
in one glance. Keep every number exactly as it is — the preview is correct, only the arrangement
changes. *Accept:* `04_training.png` content height drops below ~2,000px (from 6,071) and at least
four of the six stats are visible in the first viewport.

**A3 (P1) — One ceiling, one number.** The stable reads `115 / 540`, training reads `115 / 400`
for the same stat in the same week. Pick the number the player is told is "the cap" and show the
other only as an explicitly-labelled extension. *Accept:* the same stat reads the same denominator
in `03_stable.png` and `04_training.png`.

**A4 (P2) — The life arc, on every roster card.** The strip currently says `● Growing` five times
for monsters aged 1 to 7. Show stage, age/lifespan, stamina and plan status per card.
*Accept:* the five roster cards in `03_stable.png` show at least three distinct condition states.

**A5 (P2) — The week's cost on the drill.** Each option states what it spends in the currency
that is actually scarce: stamina, *and* the weeks of career remaining. *Accept:* a drill card
in `04_training.png` shows a career-time cost, not only a stamina cost.

**A6 (P3) — Split food off the top of training,** or fold it into one line per drill card, and
surface each monster's favourite/hated food (the data exists and no screen shows it).

**A7 (P3) — Rename the Feeding screen.** It feeds nobody; it is the week's ledger. The ledger
itself is correct — do not touch its content.

### Builder B — THE TOWN AND ECONOMY (`town_ui.gd`, `market_ui.gd`, `shop_ui.gd`, `lab_ui.gd`, `breeding_ui.gd`)
*The half with the two weakest screens in the project, and the most empty pixels.*

**B1 (P1) — Breeding shows what the foal would be.** Portraits for both parents, their stats side
by side, and a preview of the child's inherited potential/aptitude/heirloom. Today every row reads
`potential ×1.00 · Wild stock — Gen 1` and the decision has no discriminating information.
*Accept:* `09_breeding.png` shows two parent portraits and at least one predicted child attribute.

**B2 (P1) — Portraits everywhere a monster is named.** Lab, breeding, and the market's offer cards
(currently ~28px). Sixty-five species of real art exist; three screens render none of it and one
renders it as thumbnails. *Accept:* `08_lab.png`, `09_breeding.png` and `06_market.png` each show
creature textures at or above the size used in `13_ending.png`'s roster cards.

**B3 (P1) — The Lab's essay becomes a decision panel.** Two paragraphs of 11px justification
before any control. Keep the *rules* (they are load-bearing and hard-won) but state the trade as a
comparison — *this monster: 12g/week forever, N racing years surrendered, this bloodline gained* —
and move the reasoning behind a disclosure. *Accept:* the first control in `08_lab.png` appears in
the top third of the screen.

**B4 (P2) — Fill the town's empty half with the stable's state.** A condition strip (five roster
cards, mood/age/plan), what is on the calendar this month, and the one prompt worth acting on.
Keep the pace strip exactly as it is — it works. *Accept:* `02_town.png` has no contiguous empty
region taller than ~150px.

**B5 (P2) — The market compares like with like.** The recruit and the body you would release must
be rendered in the same format with the same stats, so the trade is legible.
*Accept:* both columns of `06_market.png` show the same stat fields.

**B6 (P2) — Unlock the Hall of Fame door and point it at the Lab.** `town_ui.gd:LOCATIONS` says
`"real": false`; `lab_ui.gd`'s header says it already is the Hall of Fame. One of the two is
lying. *Accept:* `02_town.png` shows no locked door for a feature that exists.

**B7 (P3) — The shop shows the whole ladder of purchases,** not only the rows you can afford now,
so gold has a visible destination across the campaign.

### Builder C — THE COMPETITION (`tournament_ui.gd`, `tactics_ui.gd`, `report_ui.gd`, `ending_ui.gd`)
*TFM2. The season is the container, and most of it is already written and unrendered.*

**C1 (P1) — Surface the season calendar that already exists.** `cup_run.gd` ships 13 months per
year, five named marquee events with a 1.75× purse, and a deterministic month per league. Nothing
renders it. Put a year strip on the tournament screen: the months, where you are, which cups fall
where, the marquee flagged. *Accept:* `10_tournament.png` shows a month/year axis and at least one
named marquee event.

**C2 (P1) — Cups become comparable rows, not stacked prose.** Three tall text blocks cannot be
compared. Same information, tabular: league · size · ceiling · entry · purse · rounds · champion ·
your standing. Put the week-cost on the button (`Enter — 48g · 1 week of your stable's life`), not
in a paragraph. And replace `[##·-]` with a real bar — an ASCII chart is a chart that lies about
its precision. *Accept:* all three cups are visible in the first viewport of `10_tournament.png`.

**C3 (P1) — The report leads with the result.** `THE READ COULD NOT BE GRADED` is currently the
largest type on the screen, above `◆ VICTORY`. Result first, grade second, machinery third. *(⚠️
The specific headline is partly a probe artifact — the demo battle has no frame stream. Fix the
hierarchy, not the sentence.)* *Accept:* in `12_report.png` the win/loss verdict is the largest
text on the screen.

**C4 (P1) — Prove the commit button is above the fold on the tactics screen.** It is not visible
in either capture at 1152×648, and it is the most important button in the game. If it is below the
fold that is a rule-2 failure; pin it outside the scroll region. *Accept:* a commit control is
visible in `11_tactics.png` without scrolling.

**C5 (P2) — Build the Ladder Board** (§3.3) as a real destination, promoted from
`ending_ui.gd`'s climb bar and `town_ui.gd:_ladder_track()`. Eleven rungs, each champion named and
portrayed, the Varra marker live. This is the season container, and it is the highest-value *new*
screen in the round — but it is P2 because C1–C4 are decisions the player currently cannot make,
and this one is a decision they can already make badly.

**C6 (P2) — Fix the tactics screen's legend and nested scroll.** The formation legend is ~8px,
below the accessibility floor; the per-monster orders strip is a nested scroll showing 2 of 3
(rule 5).

**C7 (P3) — Carry the tactics vocabulary into the report's per-monster rows** verbatim, per
`UX_LEGIBILITY.md` §1 rule 1. Today they carry `dealt/took` only.

### Not owned by a builder — for the integrator
- **`TutorialOverlay` overlaps the bottom action rail** on shop, breeding, feeding, lab and report,
  and shows a food hint on the *title screen*. It should mute where its step does not apply and
  never overlap a pinned rail.
- **`_probe_screens.gd`'s `silent_disabled` check is too strict** — it counts a disabled button
  with no *tooltip*, but `shop_ui.gd` puts the reason in the *label*, which is better. Widen the
  check to accept either.
- **Nothing asserts monster-id uniqueness.** `WeekPlan.advance()` keys its per-monster snapshot by
  `mi.id`; two monsters sharing an id silently report each other's numbers. Every shipped path
  assigns `Roster.next_slot_id()` correctly and `roster.gd:109` carries the ⚠️ — but a one-line
  tripwire in `advance()` would convert a future silent corruption into a loud failure. Low
  priority, cheap, and it cost this round twenty minutes to diagnose from a capture.

---

## 5. What I would drop first

If the round runs long, drop in this order: C7, B7, A6, A7, C6, B6. Keep every P1. **A2 (training
in six columns) and B1 (breeding shows the foal) are the two changes that convert a screen from
"cannot decide" to "can decide", and they are worth more than the other eleven items combined.**
