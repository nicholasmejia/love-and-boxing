# Love and Boxing — Project Glossary

This file is the canonical vocabulary for the project. When code, plans, or art use a term, the meaning here is authoritative.

## Core Gameplay Terms

- **Match** — A full game session against one opponent. Two rounds of five minutes each (max 10:00 of clock time, plus paused-time during knockdowns). Riddle Gaps do *not* pause the clock — knockdown is the only pause source.
- **Round** — One five-minute segment of a Match. Round 1 ends at 0:00; Round 2 begins after a brief transition.
- **Defense Phase** — The default state when the player isn't attacking. Player blocks incoming punches via a continuous Simon-style sequence. The riddle box flickers in and out during this phase: it is visible during **Riddle Encounters** and hidden during **Riddle Gaps**. The Simon-defense loop runs continuously through both (with one narrow exception: the 1s "dead air" at the front of a Fresh-Start Gap).
- **Attack Phase** — Entered when the player answers a riddle with the *right* outcome. Player executes a sequence of attack inputs to build combo or knock down the opponent. The opponent's guard is down throughout. No riddle is visible during Attack Phase.
- **Simon Sequence** — The accumulating chain of WASD inputs that drives both defense and attack phases. Classic Simon rules: show phase flashes the sequence, repeat phase requires the player to reproduce it from memory. Starts at length 1, extends by 1 each successful cycle, resets to 1 on damage taken or phase transition. No natural cap — chain grows indefinitely until interrupted.
- **Show Phase** — The part of a Simon Sequence where the game flashes the chain to the player. Pace is per-opponent (difficulty config).
- **Repeat Phase** — The part of a Simon Sequence where the player must reproduce the chain. The player has 3 seconds per keystroke on Easy (Tofu), shorter on harder tiers.
- **Riddle / Dialogue Prompt** — A piece of opponent content with a body (text or image) and three answers (each text or image). Visible during a Riddle Encounter; hidden during a Riddle Gap. Sits behind WASD prompts in z-order when visible. Answer cards are shuffled per display: each time `RiddleBox.display(prompt)` is called, the three answers are reshuffled before being placed into the left/middle/right slots.
- **Riddle Encounter** — A discrete window during Defense Phase in which the riddle box and answer cards are visible and the player can navigate / submit an answer with IJKL. The encounter starts when the riddle UI snaps in (the previous gap ends), and ends when one of these events fires:
  - Player K-presses an answer (wrong → Breather Gap; neutral → "Try again!" banner + Simon chain replay, same prompt and encounter continue; right → Attack Phase begins immediately, riddle hides, no gap until Attack Phase ends).
  - Player takes Simon damage (encounter ends, Breather Gap begins, prompt advances to the next entry in the deck).
- **Riddle Gap** — The complement of a Riddle Encounter: a window during Defense Phase when no riddle UI is visible on screen. Two flavors:
  - **Fresh-Start Gap** — 3 seconds total. The first 1 second is "dead air" with Simon defense paused (opponent idle). Then Simon defense activates for the remaining 2 seconds, with the riddle still hidden, before the next encounter starts. Used at Round 1 start (after the Fight! banner), Round 2 start (after the Fight! banner), and immediately after a knockdown's clock pause ends.
  - **Breather Gap** — 4 seconds. Simon defense remains active the entire time (no dead air). Used after a wrong answer, player Simon damage, and attack-phase end (non-knockdown).
- **Gap Timing Rules** —
  - The gap timer starts at the *event itself* (K-press, punch landed, attack-phase-end), not after the event's effects (damage flash, outcome banner) finish playing — effects play *inside* the gap.
  - A new gap-triggering event during an active gap *resets* the timer to the new event's full duration. Rapid consecutive events (e.g., repeated Simon damage) can therefore push the next riddle further out, by design.
  - Show/hide is a snap, not a fade. Fade is reserved as a polish item for a later milestone.
  - The match clock keeps ticking through every gap. Knockdown remains the only event that pauses the clock.
- **Outcome** — The classification of a riddle answer. One of: `wrong` (deals 1 damage, resets Simon chain), `neutral` (shows a "Try again!" banner and replays the current Simon chain at the same length from step 0; the prompt stays the same and answer cards re-shuffle on re-display), `right` (triggers Attack Phase).
- **Dialogue Deck** — The pool of prompts for one opponent. Shuffled without replacement. Resets at the start of each round.
- **Combo** — The player's escalation state during the match. Displayed as `x1`, `x2`, `x3`. Resets to `x1` only when the player takes damage during Defense. Failed attack inputs do *not* reset combo.
- **Knockdown** — A successful Attack Phase completed at combo level `x3`. Increments the Knockdown counter and pauses the match clock for ~5 seconds.
- **Knockout (KO)** — Third Knockdown in a Match. Ends the match in a player win.

## Player and Opponent

- **Gorgeous** — Player-controlled character. Only two visible sprites: left glove and right glove, positioned in the bottom corners.
- **Opponent** — The AI character centered on screen. Rendered as a **single body sprite** that is swapped per action (idle, swinging at each height, taking a hit at each height, guard-down, knocked-down). Some directions are drawn by horizontally flipping the canonical sprite — see Mirroring Rules below. (Earlier drafts of the design used a three-part rig of body + left arm + right arm; that has been retired.)
- **Opponent Roster** — Three opponents, one per difficulty tier:
  - `tofu` — Tier 1 (easy)
  - `minty` — Tier 2 (medium)
  - `sebastian` — Tier 3 (hard)

## Input Vocabulary

- **WASD** — Reserved for Defense and Attack inputs (gameplay). `W` = head, `A` = left hook, `D` = right hook, `S` = body.
- **IJKL** — Reserved for Riddle navigation and Menu navigation. `I` = up/middle, `J` = left, `L` = right, `K` = confirm.
- **Arrow keys + Enter + Mouse** — Fallback for menus only (not for gameplay).

## UI Regions

- **Heart Row** — Top-left. Five heart slots showing current HP.
- **Combo Meter** — Below the Heart Row. Shows current Combo state (x1/x2/x3).
- **Knockdown Meter** — Top-right. One icon added per Knockdown.
- **Match Timer** — Top-center. `5:00` countdown.
- **Riddle Box** — Center of screen, top edge aligned with the X (vertical) midline. Renders text or image content.
- **Answer Cards** — Three boxes in a row below the Riddle Box. Each renders text or image content.
- **WASD Prompts** — Input indicators flashed during Simon Sequences. `W` over the opponent's head, `S` over the opponent's body center, `A` to the opponent's left, `D` to the opponent's right. Higher z-index than Riddle Box. Each direction has three variants (`prompt`, `success`, `fail`) — see Command Sprites in the asset manifest.
- **Announcement Banner** — Full-screen overlay used for state transitions (Ready?, Fight!, Round Over!, Knock Down!, Knock Out!, You Win!, You Lose!, Draw!).

## Asset Naming Conventions

All asset filenames are lowercase, underscore-separated, and follow these patterns:

### Player Gloves (bottom corners)
- `player_glove_left_idle.png`
- `player_glove_left_block.png`
- `player_glove_left_punch.png`
- `player_glove_right_idle.png`
- `player_glove_right_block.png`
- `player_glove_right_punch.png`

### Opponent Body (per opponent: tofu, minty, sebastian)

Single sprite, swapped per action. Nine sprites per opponent (no per-arm variants).

| Sprite | Shown when |
|---|---|
| `opponent_<name>_body_idle.png` | Default stance; also serves as the guard pose (no separate guard sprite) |
| `opponent_<name>_body_guard_down.png` | Both arms lowered, after the player gives a *right* riddle answer; opponent is exposed for the attack phase |
| `opponent_<name>_body_knocked_down.png` | Knockdown interlude |
| `opponent_<name>_body_talking.png` | Optional overlay while dialogue is typing (the typewriter cue) |
| `opponent_<name>_body_swing_high.png` | Opponent telegraphs a head punch (W defense step) |
| `opponent_<name>_body_swing_mid.png` | Opponent telegraphs a body punch (S defense step) |
| `opponent_<name>_body_swing_low.png` | Opponent telegraphs a hook punch (A or D defense step) |
| `opponent_<name>_body_hit_high.png` | Player W-attack lands on the opponent's head |
| `opponent_<name>_body_hit_low.png` | Player A / S / D attack lands on the opponent's body |

**Note:** there is no separate `body_hurt` sprite; `hit_high` and `hit_low` are the only hurt poses, chosen by player attack direction.

### Mirroring Rules

All opponent sprites are drawn as if the action happens on **the gorilla's left side** (player's right). When the action belongs on the other side, render the sprite with `flip_h = true`.

Applies to:

| Gameplay direction | Sprite | Mirror? |
|---|---|---|
| Opponent W-defense (head punch) | `body_swing_high` | No |
| Opponent A-defense (left hook from opponent) | `body_swing_low` | No |
| Opponent D-defense (right hook from opponent) | `body_swing_low` | **Yes** (flip_h) |
| Opponent S-defense (body punch) | `body_swing_mid` | No |
| Player W-attack (gorilla hit on top) | `body_hit_high` | No |
| Player A-attack (gorilla hit on its right) | `body_hit_low` | No |
| Player D-attack (gorilla hit on its left) | `body_hit_low` | **Yes** (flip_h) |
| Player S-attack (gorilla hit center) | `body_hit_low` | No |

Only the **D** directions are mirrored. Idle, guard-down, knocked-down, talking, and the swing_high / swing_mid / hit_high sprites are inherently centered or symmetric and never need mirroring.

### UI
- Hearts: `heart_full.png`, `heart_empty.png`
- Combo: `combo_x1.png`, `combo_x2.png`, `combo_x3.png`
- Knockdown: `knockdown_icon.png`
- Timer background: `timer_bg.png`
- Boxes: `riddle_box.png`, `answer_box.png` (must accommodate text or image content)

### Command Sprites (in `assets/sprites/commands/`)

Per-direction WASD sprites with three variants. The Simon show phase displays the `prompt` variant; the repeat phase flashes `success` on a correct keystroke and `fail` on a missed keystroke (or input-window timeout).

- Prompt: `w_prompt.png`, `a_prompt.png`, `s_prompt.png`, `d_prompt.png`
- Success: `w_success.png`, `a_success.png`, `s_success.png`, `d_success.png`
- Fail: `w_fail.png`, `a_fail.png`, `s_fail.png`, `d_fail.png`

### Banners (full-screen overlays)
- `banner_ready.png`, `banner_fight.png`, `banner_round_over.png`
- `banner_knock_down.png`, `banner_knock_out.png`
- `banner_you_win.png`, `banner_you_lose.png`, `banner_draw.png`

### Backgrounds
- `bg_ring.png` (one background, shared across opponents in first pass)

## Persistence

- **Progress File** — Stored at `user://progress.cfg` (Godot `ConfigFile` format). Holds only `unlocked_tier` (1, 2, or 3). Wipeable for testing.

## Technical Conventions

- **Base Resolution** — 1920×1080, 16:9. Stretch mode `canvas_items`, aspect `keep` (letterbox on non-16:9).
- **Window Default** — 1280×720 windowed, resizable.
- **Audio** — Routed through an `AudioBus` autoload that exposes `play_sfx(name)`. No audio files in first pass; calls are stubbed.
- **Testing** — GUT 9.x (Godot 4 branch). Pure-logic classes are unit-tested; scene composition and animation are validated manually per milestone.
