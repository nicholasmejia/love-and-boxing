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
- **Riddle / Dialogue Prompt** — A piece of opponent content with a body (text or image) and three answers (each text or image). Visible during a Riddle Encounter. During a Riddle Gap the box is hidden by default, or remains mounted in the **Reaction State** if the picked answer carried a non-empty `reaction_text`. Sits behind WASD prompts in z-order when visible. Answer cards are shuffled per display: each time `RiddleBox.display(prompt)` is called, the three answers are reshuffled before being placed into the left/middle/right slots.
- **Reaction State** — Post-answer beat that runs inside the existing Riddle Gap. The body area renders the picked `DialogueAnswer.reaction_text` via the same typewriter used for prompt bodies; only the picked answer card remains visible in its shuffled slot; menu input (`menu_left` / `menu_up` / `menu_right` / `menu_confirm`) is ignored. Tofu's deck (image-only) skips Reaction State because its answers have empty `reaction_text` — RiddleBox falls back to `hide()` in that case. On the WRONG path, Reaction State persists through the breather gap until the next prompt loads. On the NEUTRAL path, it persists for `MatchPacing.TRY_AGAIN_BANNER` seconds (the "Try again!" banner is gone; the reaction line is what the player reads) until the same prompt re-displays. On the RIGHT path, it persists into the Attack Phase show/repeat until the first registered W/A/S/D press, which hides the riddle for the rest of the phase; an attack timeout leaves the reaction visible through `_return_to_defense` until the next prompt loads.
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

## Visual Behavior

Neither actor is a static sprite — each gameplay beat triggers a small animation. The terms below name those animations so plans, code, and commit messages can be specific. Numeric tuning lives in `OpponentAnimationProfile` (per opponent) and as constants in `player_gloves.gd` (player gloves are consistent across all matches).

### Continuous loops (run while in their owning state)

- **Idle Bob** — Opponent's footwork loop while in `Action.IDLE`. Horizontal sway with two lift-bumps per cycle (light on feet between plants, heavy at extremes).
- **Glove Sway** — Both gloves drift in a small elliptical orbit (180° out of phase) while in `State.IDLE`. Reads as breathing/stance.
- **Guard-Dropped Bounce** — Opponent hops vertically in place while in `Action.GUARD_DOWN_EXCITED` (i.e., after a right riddle answer, before the first player hit lands). Stops on the first hit for the remainder of the attack phase.

### Transient one-shots (hard-cancel on next state change)

- **Block Pose** — Both gloves tween to per-WASD-direction positions when defending. W = both up. S = both toward center. A = left small-right + right big-cross-left. D = mirror of A.
- **Punch Throw** — One glove (A→left, D→right, S→left toward center, W→right toward head) tweens forward with shrink + rotation. Reads as committing into the punch.
- **Attack Lunge** — Opponent shifts horizontally (per Shift Map) while growing then shrinking. Reads as stepping into the punch.
- **Hit Recoil** — Opponent shifts horizontally (same Shift Map) while shrinking then growing. Reads as flinching back and stepping forward to recover.
- **Knockdown Fall** — Multi-phase: sway-with-shrink → rotate + lower. Texture swaps to `KNOCKED_DOWN` at the start of the fall; sprite holds at lowered+tipped+small at the end.
- **Knockdown Recover** — Non-KO only. The `KNOCKED_DOWN` sprite tweens back to base transform; final frame swaps to `IDLE` ("stand again"). KO leaves the opponent fallen through the win banners.

### Shift Map (used by Attack Lunge and Hit Recoil)

Both beats shift the opponent in the direction OPPOSITE the attack side:

| Direction | Shift |
|---|---|
| A | screen right (+X) |
| D | screen left (−X) |
| W | screen right (treated like A) |
| S | screen left (treated like D) |

### Animation Profile

Per-opponent timings (amplitudes, durations, transition curves) live in an `OpponentAnimationProfile` Resource at `data/opponent_animation/<opponent>.tres`, referenced from `DifficultyConfig.animation_profile_path`. Missing path falls back to Tofu's profile (same pattern as `dialogue_deck_path`). Player gloves have no profile — values are constants in `player_gloves.gd`.

Personality intents (tuning targets, not code branches):
- **Tofu** — wild: larger amplitudes, longer periods, bouncier transitions.
- **Minty** — refined: moderate amplitudes, smooth (`TRANS_SINE`) transitions.
- **Sebastian** — efficient: small amplitudes, sharp (`TRANS_QUART`) transitions.

Initial ship: Tofu's profile is tuned; Minty and Sebastian fall back to Tofu's. Per-opponent tuning is a follow-up effort.

## UI Visual Behavior

Banners and WASD prompts are no longer snap show / snap hide — each carries a per-event animation that punctuates the gameplay beat. Numeric tuning lives as constants in `announcement_banner.gd` (universal banner timing) and `wasd_prompt.gd` (per-variant prompt timing). UI animations are universal — they do not vary by opponent or difficulty.

### Banner Slide

The in/out animation for any `AnnouncementBanner` mode (`show_banner`, `show_message`, `show_prompt`):

- **On show:** banner starts left of its rest position with opacity 0, slides right to rest with opacity 1.0.
- **On dismiss/timeout:** slides further right past rest while opacity drops back to 0.

Both transitions move rightward — the banner "passes through" its resting position. The 40% black backdrop fades with the same opacity envelope but does not slide.

`AnnouncementBanner.dismiss()` is **awaitable** — callers must await it before the next banner / state change so consecutive banners do not overlap. The `MatchPacing` banner constants (`READY_BANNER`, `KNOCK_DOWN_BANNER`, etc.) define banner **hold** time only; total wall-clock is `IN_DURATION + hold + OUT_DURATION`. Code that subtracts a banner duration from a larger pause (e.g., the `KNOCKDOWN_PAUSE` remainder math) must use `AnnouncementBanner.total_duration_for(hold_seconds)`, not the raw constant.

### WASD Prompt Animations (per variant)

Every variant follows a universal envelope — slow opacity fade in (during the variant's entry beat), hold at rest, much quicker opacity fade out — with variant-specific behavior layered on top. Any new `display()` call hard-cancels the in-flight tween and resets modulate/scale/position to a clean state. `hide_all()` is snap-hide for round-end / match-loss / phase-transition snap-clears.

- **Prompt Pulse** — The PROMPT variant's grow-in: scale 0 → overshoot (~1.15×) → rest (1.0×) with opacity 0→1.0, then hold at rest, then opacity fade-out. Used for show-phase telegraphs in both defense and attack.
- **Block Shake** — The SUCCESS variant in defense. Prompt appears at rest scale/opacity (no pre-pulse), then shakes in discrete stuttered steps along the impact axis (dominant) with smaller perpendicular jitter, before fading out. Reads as "solid object absorbing the blow". Shake direction follows the opponent's punch direction.
- **Damage Double-Pulse** — The FAIL variant in defense. Two consecutive Prompt Pulses with no gap, then a slight tail shake (~⅓ the amplitude of Block Shake) before fading out. Reads as "missed the block and got tagged". Shake direction follows the *expected* opponent punch direction (same direction the FAIL sprite is flashed at).
- **Hit Toss** — The SUCCESS variant in attack. A quicker Prompt Pulse, then the prompt is "tossed" — translates along the punch's travel vector in a vertical arc (up then back down past rest), tapering in scale, while opacity fades to 0. Hooks (A/D) get a larger horizontal offset than jabs (W/S) to match the more horizontal swing. After the toss the prompt is gone for the rest of the beat.
- **Miss Double-Pulse** — The FAIL variant in attack. Two consecutive Prompt Pulses, then hold, then fade out. No shake (the prompt was not physically hit) and no toss (the punch did not connect). Distinguishes the attack-miss case from the defense-damage case via the absence of shake.

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
| `opponent_<name>_body_guard_down.png` | Shared by `Action.GUARD_DOWN` (post-first-hit, no bounce) and `Action.GUARD_DOWN_EXCITED` (initial drop, with Guard-Dropped Bounce). Both arms lowered, after a *right* riddle answer; opponent is exposed for the attack phase |
| `opponent_<name>_body_knocked_down.png` | Knockdown interlude |
| `opponent_<name>_body_talking.png` | Optional overlay while dialogue is typing (the typewriter cue) |
| `opponent_<name>_body_swing_high.png` | Opponent telegraphs a head punch (W defense step) |
| `opponent_<name>_body_swing_mid.png` | Opponent telegraphs a body punch (S defense step) |
| `opponent_<name>_body_swing_low.png` | Opponent telegraphs a hook punch (A or D defense step) |
| `opponent_<name>_body_hit_high.png` | Player W-attack lands on the opponent's head |
| `opponent_<name>_body_hit_low.png` | Shared by `Action.HIT_LOW` (player A or D side attack) and `Action.HIT_BODY` (player S center attack). Player A / S / D attack lands on the opponent's body |

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

`Action.HIT_BODY` and `Action.GUARD_DOWN_EXCITED` are animation-only disambiguations — they don't change which sprite loads or whether it mirrors. See "Visual Behavior" above.

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
- **Audio** — Routed through an `AudioBus` autoload. Music and sound effects are routed through two named child buses of `Master`:
  - **Music Bus** — Carries every BGM track. Volume controls and ducking attach here.
  - **SFX Bus** — Carries every short sound effect. Volume controls attach here.

  `AudioBus` exposes a single music entry point that takes either a track name (looked up in an internal name → stream table for menu/stinger tracks) or an `AudioStream` resource (for per-opponent BGM authored on `DifficultyConfig`). Music calls are **idempotent on Track ID**: asking for the track that is already playing is a no-op, so scene-to-scene continuity does not restart the loop. SFX calls go through `play_sfx(key)` and are non-idempotent — every call schedules a voice, freely layering on top of any in-flight SFX.

  Bus baselines (`default_bus_layout.tres`): Music is at -1.41 dB and SFX is at +0.83 dB relative to Master. These are the tunable trim points; per-file gain is reserved for normalizing within a Variant Pool.

- **BGM** — A long-form music track tied to a screen, match, or outcome. Each BGM file is one of two shapes: a **seamless loop** (authored so end → start has no audible seam — `menu`, `tofu`, `minty`, `sebastian`, `title_main_loop`) or a **stinger** (one-shot that plays once and decays into silence — `title_intro`, `victory`, `defeat`). The loop flag is set per-file in the `.import` file, never at runtime.
- **Stinger** — A non-looping BGM one-shot used to punctuate a state transition (currently `victory.ogg` on the YOU_WIN banner and `defeat.ogg` on the YOU_LOSE banner; eventually `title_intro.ogg` leading into the attract loop). Stingers play to completion, are interruptible by a K-skip (the final banner is skippable while its stinger is playing), and are pre-empted by a cross-fade into the next track; they are never looped or re-bedded under other music.
- **Track ID** — The string used to identify the currently-playing BGM for idempotency checks. For named tracks it is the lookup key (e.g. `"menu"`, `"victory"`). For per-opponent streams played from a resource it is the opponent slug (e.g. `"tofu"`). Two consecutive `play_music` calls with the same Track ID do not restart the stream.
- **SFX** — A short, polyphonic sound effect routed through the SFX Bus. Stored as 16-bit PCM .wav at 44.1 kHz stereo under `assets/audio/sfx/`. Looked up by **key** in `play_sfx(key)`: each key matches either a single file (`combo_reset.wav`) or a multi-file **Variant Pool** (e.g. `swing_01.wav` … `swing_06.wav` all collapse to key `swing`). Polyphony is 16 voices, round-robin; when the pool wraps, the oldest voice is stolen rather than dropping the new call. Combat moments are designed as deliberate stacks: a landed combo hit fires `swing` + `opponent_punch_body` + `combo_success_N_hit` simultaneously; a defense miss fires `swing` + `player_block_or_hit` + `input_failure` (+ `combo_reset` if combo > 1). All layering is implicit through the voice pool — there is no priority system or duck logic.
- **Variant Pool** — A set of `.wav` files sharing a base key, distinguished by a trailing `_NN` index (`opponent_punch_body_01.wav` … `_10.wav`, `swing_01.wav` … `_06.wav`). The AudioBus auto-discovers pools at startup by scanning `assets/audio/sfx/` and stripping `_NN` suffixes; single-file keys with no numeric suffix (e.g. `combo_reset`, `combo_success_1_hit`) pass through unchanged. `play_sfx(base_key)` picks one entry at random per call. Use a pool when the same gameplay event repeats frequently and a fixed clip would feel mechanical; use a single file when the cue is one-shot per-event (riddle outcomes, round bells, menu cues).
- **Testing** — GUT 9.x (Godot 4 branch). Pure-logic classes are unit-tested; scene composition and animation are validated manually per milestone.
