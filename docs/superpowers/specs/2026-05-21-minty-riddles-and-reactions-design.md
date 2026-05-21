# Minty Riddles + Reaction State

**Date:** 2026-05-21
**Branch:** TBD (feature branch off `main`)
**Scope:** Author Minty's 9-prompt text-only dialogue deck, wire it into `data/difficulty/minty.tres`, and add a new **Reaction State** to the riddle box so each picked answer is followed by the opponent's reaction line inside existing gameplay timing (no clock cost added).

## Summary

Minty (Tier 2) ships with text-only riddles paired with a per-answer reaction line that displays in the riddle box after the player picks. The reaction does not introduce a new pause — it occupies time the gameplay was already spending on the punch+damage+breather (WRONG), the pre-redisplay wait that used to host the "Try again!" banner (NEUTRAL), or the attack show/repeat (RIGHT, dismissed by the first attack input).

Tofu's existing image-only deck is unaffected. Its `DialogueAnswer` resources have empty `reaction_text`, which routes through a graceful fallback that preserves the current snap-hide-on-answer behavior.

## Mechanic: Reaction State

### Concept

A second display state for the riddle box. Picked answer triggers it; the next prompt re-display (or the first attack input on the RIGHT path) clears it. While in Reaction State the box stays mounted with:

- **Body area:** typewriter-renders the picked `DialogueAnswer.reaction_text` (replacing whatever the prompt body was).
- **Answer cards:** only the picked card remains visible in its current shuffled slot; the other two are hidden.
- **Input:** menu_left / menu_up / menu_right / menu_confirm are no-ops while in Reaction State.

### Per-outcome flow

| Outcome | What plays during Reaction State | What clears it |
|---|---|---|
| WRONG | Opponent swing + damage flash + breather gap (≈4s, unchanged) | `_show_next_prompt()` at end of breather → `RiddleBox.display(...)` returns to NORMAL |
| NEUTRAL | Same `MatchPacing.TRY_AGAIN_BANNER` wait, but as a bare `await get_tree().create_timer(...)` — no banner | Same-prompt re-display via `_riddle.display(_current_prompt)` returns to NORMAL |
| RIGHT | Attack show + repeat phase, until the first registered W/A/S/D press in repeat phase | First registered input (right direction or wrong) hides the riddle for the rest of the attack phase. Show-phase keypresses (no-op'd by `_repeat_active`) and attack timeouts do not hide the riddle — timeouts let the reaction persist through breather until `_show_next_prompt()` rebuilds in NORMAL. |

The match clock continues running through Reaction State exactly as it does through Riddle Gaps today — knockdown remains the only pause source.

### Empty-reaction fallback (tofu)

`RiddleBox.show_reaction(picked_index)` checks the picked answer's `has_reaction()` itself:

- Non-empty `reaction_text` → enter REACTION as described above.
- Empty `reaction_text` → `self.hide()`, REACTION never entered.

Gameplay always calls `show_reaction(...)` after `answer_submitted`. The branching policy lives in RiddleBox; gameplay stays branch-free. Tofu's nine existing `.tres` files don't change.

### Code touch points

**`scripts/game/dialogue_answer.gd` — add field:**

```gdscript
@export var reaction_text: String = ""

func has_reaction() -> bool:
    return reaction_text != ""
```

`text`, `image`, `outcome` unchanged. Existing tofu `.tres` files load with `reaction_text = ""` by Godot's default-field-on-old-resource behavior.

**`scripts/ui/riddle_box.gd` — state machine:**

- New enum `State { NORMAL, REACTION }` and `_state` field.
- `display(prompt)` sets `_state = NORMAL`, restores all 3 cards' visibility, runs the existing body render + typewriter + card-shuffle path.
- New method `show_reaction(picked_index: int) -> void`:
  - If `_cards[picked_index]` was displayed with an answer whose `has_reaction()` is false → call `self.hide()` and return.
  - Otherwise: hide non-picked cards (`_cards[i].visible = false` for `i != picked_index`), hide `_body_image`, render the reaction text via the existing `_start_typewriter(...)`, set `_state = REACTION`.
- `_unhandled_input` early-returns when `_state == REACTION` so menu actions are no-ops.
- On confirm in NORMAL, RiddleBox already has the picked card's index in `_highlight_index` (riddle_box.gd:14). The confirm branch calls `show_reaction(_highlight_index)` **synchronously before** emitting `answer_submitted(outcome)`, so gameplay observes the state transition as already complete by the time its handler runs. No new signal payload.

**`scripts/gameplay.gd` — remove snap-hide, drop banner, hook attack input:**

- Delete `_riddle.visible = false` at line 523. RiddleBox owns its own visibility now. The `_visibility = RiddleVisibility.BREATHER_GAP` flip at line 522 stays — it's the re-entrant K-press gate.
- Rewrite the comment block at lines 508–522 to reflect the new contract: the gate now relies on RiddleBox's REACTION state ignoring input as the primary defense, with the gameplay-side visibility gate as belt-and-suspenders.
- NEUTRAL path (line 558+): delete the `await _banner.show_message("Try again!", MatchPacing.TRY_AGAIN_BANNER)` call. Replace with `await get_tree().create_timer(MatchPacing.TRY_AGAIN_BANNER).timeout` so pacing is preserved. Keep the `_gap_generation` race check (round-end / match-loss can still invalidate the flow).
- RIGHT path: in `_trigger_attack_phase()`, connect a new one-shot signal `first_input_received` on `AttackPhase` (emitted on the first W/A/S/D that registers — whether it routes through `step_landed` or `attack_failed`). The handler calls `_riddle.hide()`.

**`scripts/game/attack_phase.gd` — new signal:**

- `signal first_input_received()` — emitted exactly once per attack phase, inside `player_input(direction)` **after** the `if not _repeat_active: return` guard at line 76 and **before** the `_sequence.validate_at(...)` branch at line 78. Tracked with an internal `_first_input_emitted: bool` that resets to `false` at the top of `begin(input_count)`.
- Show-phase keypresses (which are no-ops behind the `_repeat_active` guard) do not fire the signal — the reaction is interrupted only by an input that actually counts.
- Attack timeout (`_on_input_timeout` → `_fail`) does not fire the signal — if the player stares the timer out, the reaction persists through `_return_to_defense` → breather gap until `_show_next_prompt` rebuilds the box in NORMAL.

**`scripts/ui/announcement_banner.gd` and `MatchPacing.TRY_AGAIN_BANNER`** — kept. Other paths may still use the banner; verify with `grep -rn "show_message\|TRY_AGAIN_BANNER" scripts/` before deletion. The constant `TRY_AGAIN_BANNER` is reused as the reaction-display duration on NEUTRAL.

## Content: Minty's Deck

### Layout

```
data/dialogue/minty/
├── deck.tres
├── tier_0/
│   ├── flex_feint.tres
│   ├── dog_distraction.tres
│   └── hungry_footwork.tres
├── tier_1/
│   ├── bug_in_the_ring.tres
│   ├── pink_gloves.tres
│   └── sparring_date.tres
└── tier_2/
    ├── bruise_compliment.tres
    ├── dog_trap.tres
    └── strength_test.tres
```

Mirror of tofu's layout. Filenames are author-facing only — they don't appear in game. JSON `round` maps to tier (1→0, 2→1, 3→2) so the existing `_deck.set_active_tier(_knockdowns.count())` wiring at `gameplay.gd:97` works without change.

### Authoring shape

Each prompt `.tres` is a `DialoguePrompt` with:
- `body_text` = JSON `clue`
- `body_image` = null
- `answers` = three `DialogueAnswer` sub-resources, each with `text` = JSON `text`, `image` = null, `outcome` per the table below, `reaction_text` = JSON `reaction`.

JSON `character` and `title` fields are dropped (character is implicit in the deck path; title is editorial only).

### Outcome map

| Q | Tier | RIGHT (2) | NEUTRAL (1) | WRONG (0) |
|---|---|---|---|---|
| 1 | 0 | Both. You look like… | They say you train… | Mostly final boss… |
| 2 | 0 | A happy little mutt… | A dog is a dog. | A bloodhound. |
| 3 | 0 | That wasn't a growl… | You must be hungry… | Maybe your stomach should… |
| 4 | 1 | I'll relocate the tiny criminal… | I'll move it so… | I'll end its reign… |
| 5 | 1 | The hearts make it scarier. | They're cute, but you still seem tough. | They're cute, so people probably… |
| 6 | 1 | Then I'll block what I can… | Your hair does look nice. | I'd lose on purpose… |
| 7 | 2 | Princesses can have battle damage. | It doesn't look that bad. | Don't worry, I still think you look pretty. |
| 8 | 2 | A cheerful rescue mutt… | Any dog you like. | A loyal bloodhound… |
| 9 | 2 | I get up, ask for pointers… | I'd be impressed you hit that hard. | I'd tell you to go easy… |

The position of answers within the `Array[Resource]` at authoring time has no in-game effect — RiddleBox shuffles per `display()`.

### Wiring

`data/difficulty/minty.tres` line 11: `dialogue_deck_path = ""` → `dialogue_deck_path = "res://data/dialogue/minty/deck.tres"`.

No `animation_profile_path` change. Per CONTEXT.md line 97, Minty falls back to Tofu's animation profile until per-opponent tuning is done.

## CONTEXT.md Updates

**Line 16** (Riddle / Dialogue Prompt definition):
> Visible during a Riddle Encounter; hidden during a Riddle Gap.

becomes:
> Visible during a Riddle Encounter. During a Riddle Gap the box is hidden by default, or in the **Reaction State** if the previous answer carried reaction text.

**New paragraph after the Riddle / Dialogue Prompt definition:** define Reaction State —
> **Reaction State** — Post-answer beat that runs inside the existing Riddle Gap. The body area renders the picked answer's `reaction_text` via typewriter; only the picked answer card remains visible in its shuffled slot; menu input is ignored. Tofu's deck (image-only) skips Reaction State because its answers have empty `reaction_text`. On the WRONG path, Reaction State persists through the breather gap until the next prompt loads. On the NEUTRAL path, it persists for `MatchPacing.TRY_AGAIN_BANNER` seconds (the "Try again!" banner is removed) until the same prompt re-displays. On the RIGHT path, it persists into the Attack Phase show/repeat until the first attack input, which hides the riddle for the rest of the phase.

The CONTEXT.md change lands in the same PR as the code change.

## Testing

**Unit (GUT, add to existing files):**
- `tests/unit/test_dialogue_prompt.gd` — `test_answer_has_reaction_when_set`, `test_answer_has_reaction_empty_default`.

**Unit (new file `tests/unit/test_riddle_box.gd`):**
- `display(prompt)` puts box in NORMAL with 3 cards visible.
- After NORMAL confirm of an answer with non-empty `reaction_text`: state is REACTION, two cards are invisible, picked card is visible, body text == reaction text, menu inputs are no-ops.
- After NORMAL confirm of an answer with empty `reaction_text`: box is hidden (`visible == false`), state did not enter REACTION.
- `display(prompt)` from REACTION returns to NORMAL with all 3 cards re-shown.

If `_unhandled_input` testing against a live scene tree turns out to be expensive in GUT, fall back to pure-logic assertions on `_state`, `_cards[i].visible`, and `_body_text.text` after manually invoking the relevant methods. Visual behavior is then validated in-engine (see Manual below).

**Smoke (one-liner in `test_dialogue_deck.gd`):**
- Load `res://data/dialogue/minty/deck.tres`; assert 3 prompts per tier, each prompt has 3 answers, each answer has non-empty `text` and `reaction_text`.

**Manual (in-engine, against minty match):**
- WRONG, NEUTRAL, RIGHT answers each produce the expected reaction display in the box.
- The picked card stays in its shuffled slot through the reaction.
- On RIGHT, the first W/A/S/D press hides the riddle; no late re-show during the rest of attack phase.
- Tofu match: behavior identical to current ship (snap-hide on answer).
- "Try again!" banner does not appear in any minty match.

## Open Questions / Followups

- **Sebastian (Tier 3) deck** — out of scope for this spec. Same data shape and code path; needs its own JSON pass.
- **Reaction text length budget** — JSON reactions are short (~50–100 chars) and the typewriter at 30 chars/sec lands them well inside every outcome's natural duration. If a future author writes a reaction longer than ~1.5s of typing on the NEUTRAL path, it can clip mid-sentence when the prompt re-displays. Out of scope for this spec; revisit if it becomes a real authoring problem.
- **Reaction polish on RIGHT** — picked card sliding to center, reaction tinted by outcome, etc. — explicitly deferred. User wants the beat playable first for tuning.
