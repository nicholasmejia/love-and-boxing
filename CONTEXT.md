# Love and Boxing — Project Glossary

This file is the canonical vocabulary for the project. When code, plans, or art use a term, the meaning here is authoritative.

## Core Gameplay Terms

- **Match** — A full game session against one opponent. Two rounds of five minutes each (max 10:00 of clock time, plus paused-time during knockdowns). Riddle Gaps do *not* pause the clock — knockdown is the only pause source.
- **Round** — One five-minute segment of a Match. Round 1 ends at 0:00; Round 2 begins after a brief transition.
- **Defense Phase** — The default state when the player isn't attacking. Player blocks incoming punches via a Simon-style sequence. The riddle box flickers in and out during this phase: it is visible during **Riddle Encounters** and hidden during **Riddle Gaps**. The Simon-defense loop is gated by the **Riddle Render Gate** — it activates only after the current encounter's prompt has rendered (typewriter complete) plus a fixed read floor, and stops on any triggering event (WRONG / Simon damage / attack-end / round-end / knockdown / RIGHT). Riddle Gaps therefore play out with defense fully paused; defense restarts at the end of the next gate.
- **Attack Phase** — Entered when the player answers a riddle with the *right* outcome. Player executes a sequence of attack inputs to build combo or knock down the opponent. The opponent's guard is down throughout. No riddle is visible during Attack Phase.
- **Simon Sequence** — The accumulating chain of WASD inputs that drives both defense and attack phases. Classic Simon rules: show phase flashes the sequence, repeat phase requires the player to reproduce it from memory. Starts at length 1, extends by 1 each successful cycle, resets to 1 on damage taken or phase transition. No natural cap — chain grows indefinitely until interrupted. After a chain completes inside a single Defense Phase session, an inter-round breath (`DefensePhase.inter_round_seconds`, currently 1.5s) plays before the next round's show phase begins. The first round after `start()` skips this breath — the Riddle Render Gate already owns that beat.
- **Show Phase** — The part of a Simon Sequence where the game flashes the chain to the player. Pace is per-opponent (difficulty config).
- **Repeat Phase** — The part of a Simon Sequence where the player must reproduce the chain. The player has 3 seconds per keystroke on Easy (Tofu), shorter on harder tiers.
- **Riddle / Dialogue Prompt** — A piece of opponent content with a body (text or image) and three answers (each text or image). Visible during a Riddle Encounter. During a Riddle Gap the box is hidden by default, or remains mounted in the **Reaction State** if the picked answer carried a non-empty `reaction_text`. Sits behind WASD prompts in z-order when visible. Answer cards are shuffled per display: each time `AnswerCarousel.display_prompt(prompt)` is called, the three answers are reshuffled before being assigned to the carousel's left / center / right rotational positions.
- **Riddle Render Gate** — The window between a prompt becoming visible and DefensePhase activating. Composed of the typewriter pass (0s for image-body prompts like Tofu, ~1–2s for text-body prompts like Minty / Sebastian) plus a fixed `RIDDLE_READ_FLOOR` post-type read window (`MatchPacing.RIDDLE_READ_FLOOR`, currently 1.0s). Defense is fully paused for the duration — no WASD prompts flash, opponent stays IDLE — so the player can read before being asked to block. The **Answer Carousel** (a sibling UI node in `gameplay.tscn`, not a child of RiddleBox) is hidden during the typewriter portion (cards are not rendered at all) and fades in once the typewriter completes — it listens for `RiddleBox.body_render_complete` to trigger the fade. All carousel input (`menu_left` / `menu_right` cycling and `menu_confirm`) is gated behind the fade-in completing — there is no pre-positioning during typewriter. Image-body prompts (Tofu) and the NEUTRAL re-display path (`RiddleBox.display_instant()`) skip the typewriter and the fade — the carousel is operable the frame the prompt is shown. The NEUTRAL re-display path skips the gate entirely (the 2s reaction read window has already served the read-before-defense purpose).
- **Reaction State** — Post-answer beat that runs inside the existing Riddle Gap. K-confirm triggers a punch choreography: the right glove tweens to the chosen card (~150ms, `swing` SFX), the card flashes white on impact (`opponent_punch_body` + `menu_option_select` SFX), the two unpicked cards animate out (slide to off-screen wrap positions + fade to transparent), and the picked card flies toward the opponent's body (~200ms, scale 1.0→0.4, alpha 1.0→0). At impact-frame, the body area renders the picked `DialogueAnswer.reaction_text` via the same typewriter used for prompt bodies, and `answer_submitted(outcome, picked_answer)` emits so gameplay can fire the outcome SFX and queue the next phase. When the picked card hits the opponent body (~350ms after K), `card_struck_opponent(direction)` emits → gameplay calls `Opponent.set_action(HIT_LOW, Direction.RIGHT)` (mirrored to face the card coming from screen-right), holds `HIT_HOLD_DURATION` (~250ms), then transitions to `GUARD_DOWN`. Carousel input (`menu_left` / `menu_right` / `menu_confirm`) is locked the moment K fires (`_is_punching` gate) and stays locked until the punch chain completes. Tofu's deck (image-only) skips the reaction typewriter — gameplay calls `RiddleBox.hide()` instead of `show_reaction()` — but the punch choreography still plays. On the WRONG path, Reaction State persists through the breather gap until the next prompt loads. On the NEUTRAL path, gameplay waits for the reaction typewriter to complete (via the `body_render_complete` signal), then holds `MatchPacing.NEUTRAL_READ_HOLD` seconds, then re-displays the SAME prompt instantly via `RiddleBox.display_instant()` — no typewriter, no read floor — and replays the Simon chain at its current length from step 0. On the RIGHT path, it persists into the Attack Phase show/repeat until the first registered W/A/S/D press, which hides the riddle for the rest of the phase; an attack timeout leaves the reaction visible through `_return_to_defense` until the next prompt loads.
- **Riddle Encounter** — A discrete window during Defense Phase in which the riddle box (bottom-center) and the **Answer Carousel** (upper-right play area) are visible and the player can cycle / submit an answer. The encounter starts when the riddle UI snaps in (the previous gap ends) and the body begins rendering; the carousel itself appears only after the body typewriter completes (see Riddle Render Gate). Navigation is `menu_left` (J) / `menu_right` (L) to cycle the carousel — both wrap. `menu_confirm` (K) picks whichever answer is currently in the carousel's center slot. `menu_up` (I) is intentionally unused inside RiddleBox (it remains bound for other menus). Defense activates at the end of the encounter's Riddle Render Gate. The encounter ends when one of these events fires:
  - Player K-presses an answer (wrong → Reaction State + Breather Gap; neutral → Reaction State + `MatchPacing.NEUTRAL_READ_HOLD` hold (after reaction typewriter) + instant prompt re-display + Simon chain replay, encounter continues; right → Attack Phase begins immediately, riddle stays in Reaction State until the first attack input hides it).
  - Player takes Simon damage (encounter ends, Breather Gap begins, prompt advances to the next entry in the deck).
- **Riddle Gap** — The complement of a Riddle Encounter: a window during Defense Phase when no riddle UI is visible on screen. Defense is fully paused throughout (opponent IDLE, no WASD prompts) — the next show phase doesn't fire until the subsequent encounter's Riddle Render Gate completes. Two flavors:
  - **Fresh-Start Gap** — `MatchPacing.FRESH_START_SETTLE` seconds (currently 0.5s). Riddle hidden, opponent IDLE, defense paused. Used at Round 1 start (after the Fight! banner), Round 2 start (after the Fight! banner), and immediately after a knockdown's clock pause ends.
  - **Breather Gap** — `MatchPacing.BREATHER_GAP` seconds (currently 4s). The picked answer's reaction text stays visible in REACTION state through the gap (or the box is hidden, for empty-reaction prompts like Tofu). Used after a wrong answer, player Simon damage, and attack-phase end (non-knockdown).
- **Gap Timing Rules** —
  - The gap timer starts at the *event itself* (K-press, punch landed, attack-phase-end), not after the event's effects (damage flash, outcome banner) finish playing — effects play *inside* the gap.
  - A new gap-triggering event during an active gap *resets* the timer to the new event's full duration. Rapid consecutive events (e.g., repeated Simon damage) can therefore push the next riddle further out, by design. A new event can also fire during the Riddle Render Gate — the gate is also invalidated by `_gap_generation`, so the new event's gap timer wins.
  - Show/hide is a snap, not a fade. Fade is reserved as a polish item for a later milestone.
  - The match clock keeps ticking through every gap and gate. Knockdown remains the only event that pauses the clock.
- **Outcome** — The classification of a riddle answer. One of: `wrong` (deals 1 damage, resets Simon chain), `neutral` (waits for the reaction typewriter to complete, holds `MatchPacing.NEUTRAL_READ_HOLD` seconds, then re-displays the same prompt instantly via `display_instant()` and replays the current Simon chain at the same length from step 0), `right` (triggers Attack Phase).
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
- **IJKL** — Reserved for Riddle navigation and Menu navigation. `I` = up/middle, `J` = left, `L` = right, `K` = confirm. Riddle-specific note: the Answer Carousel only uses `J` / `L` (cycle, wrap) and `K` (confirm) — `I` is intentionally unused inside RiddleBox but remains active for other menus.
- **Arrow keys + Enter + Mouse** — Fallback for menus only (not for gameplay).

## Screens

Top-level scenes the player moves through. Distinct from UI Regions (which are sub-components inside a screen).

- **Attract Sequence** — The animated opening that runs from cold start of the game. Plays a multi-phase sequence and comes to rest on the Title Screen layout. Fades out to the Main Menu when the player confirms after `Press K to start` has appeared. Skippable to the Title Screen rest state at any earlier point. The animated phases (1–4) are timed against the `title_intro` stinger as a master clock — the Title Slam's white flash and the cross-cut to `title_main_loop` coincide exactly. The six phases are:
  - **Slide-In** — The three attraction pennants (Tofu, then Minty, then Sebastian, strictly sequential) slide into a composite triangular arrangement. The `attract_punch` sprite is parented behind the pennants from scene init so it is invisible until the pennants leave.
  - **Attract Punch** — `attract_punch` scales up from behind the assembled composite (revealing itself); at peak scale the three pennants begin a spin-and-fly-off in separate directions; the punch then shrinks back toward its rest scale as the pennants exit the screen.
  - **Camera Pan** — Reads as the camera tilting down onto the ring: `title_background` fades in while translating upward, and `title_ring` plus the three character stand-ups also translate upward, at faster rates than the background, producing parallax. The `attract_punch` fades out during this phase.
  - **Title Slam** — `title_text` slams in from above with scale-overshoot. A full-screen flash to white peaks at the moment of impact, which is also the exact moment `title_intro` ends and `title_main_loop` begins.
  - **Settle Hold** — A short held beat at the resting composite with `title_main_loop` playing. No new motion. `Press K to start` is not yet visible.
  - **Press-K Flash** — `Press K to start` begins flashing at the bottom of the screen. This is the persistent Title Screen rest state. Confirm input is armed; pressing it fades the scene to black and transitions to the Main Menu.
- **Title Screen** — The composite layout shown in `assets/sprites/title/final_title_desired_result.png`: stadium background, ring corners, three character stand-ups, the `LOVE AND BOXING` logo, and `Press K to start` at the bottom. It is the final, resting phase of the Attract Sequence — not a separate scene. From this rest state the player presses K to fade into the Main Menu.
- **Main Menu** — The button screen with `Start / Options / Credits / Quit`. Lives at `scenes/main_menu.tscn` (the file historically called `title_screen.tscn` — it was misnamed; the *animated* sequence is the title screen, the buttons are the main menu). Reached from the Title Screen via K-confirm.

## UI Regions

- **Heart Row** — Top-left. Five heart slots showing current HP.
- **Combo Meter** — Below the Heart Row. Shows current Combo state (x1/x2/x3).
- **Knockdown Meter** — Top-right. One icon added per Knockdown.
- **Match Timer** — Top-center. `5:00` countdown.
- **Riddle Box** — Bottom-center of screen. Body-text-or-image only. Snaps in/out at encounter boundaries. No longer contains the answer cards — those live in the **Answer Carousel** above.
- **Answer Carousel** — Upper-right play area (rough anchor ~1280, 410 on the 1920×1080 stage), free-floating UI cluster of three `AnswerCard` instances arranged on a diagonal axis (L lower-left, M center, R upper-right). The selected answer is always the center card at full scale; the two unselected sit at `SIDE_SCALE` (0.7) on the diagonal, z-ordered behind so they overlap the center card by ~60px. J/L rotates the carousel along the diagonal (wrap-around — the side card displaced toward the rotation direction slides off the corresponding edge and re-enters from the opposite edge); K picks the center card and triggers the punch choreography. The carousel is hidden during the body typewriter and fades in once typing completes (no fade for image-body / NEUTRAL re-display paths). All card positions/scales/z route through a single transform seam in `answer_carousel.gd` (`_compute_card_transform(index, rotation_state)` + `_make_position(anchor)`) per ADR-0001.
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
