# UI Animations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the snap show / snap hide of `AnnouncementBanner` and `WasdPromptLayer` with tween-driven animations. Banners get a horizontal slide + opacity envelope on every show/dismiss. WASD prompts get a universal opacity envelope plus per-variant beats — pulse grow-in for PROMPT, shake for defense-SUCCESS, double-pulse + slight shake for defense-FAIL, quick pulse + toss arc for attack-SUCCESS, double-pulse + fade for attack-FAIL.

**Architecture:** All animations use `create_tween()` with a stored `_active_tween` reference per node for hard-cancel preemption. `AnnouncementBanner` learns about a slide offset + in/out durations + a `total_duration_for(hold)` helper; `show_banner / show_message / show_prompt / dismiss` all become async and await their respective tweens. `WasdPrompt.display(direction, variant)` dispatches to one of five variant animations; `hide_prompt()` snap-hides + tween-kills + state-resets. `gameplay.gd` changes minimally — the only structural fixes are awaiting the new async `dismiss()` and using `AnnouncementBanner.total_duration_for()` for the `KNOCKDOWN_PAUSE` remainder math.

**Tech Stack:** Godot 4.6 (GDScript, `Tween` API, `Control.modulate.a`, `Control.scale`, `Control.position`), GUT 9.x for unit tests of pure-math helpers (toss horizontal sign per direction, shake step displacements).

**Reference glossary:** `CONTEXT.md` § "UI Visual Behavior"

**Branch:** `feature/ui-animations`, cut from `main` after `git fetch && git pull origin main`. `feature/actor-animations` is already merged.

---

## Cross-cutting constraints

- **Manual playtest is the test harness for visual/feel work.** Animations are validated by playing the game, not by unit tests. Unit tests cover only pure-math helpers (toss direction sign, shake step displacement table).
- **Each increment ends with a Manual Playtest task** that boots the game and demonstrates the new visible behavior. Do not skip these. If an increment's playtest fails, fix inline before moving on.
- **Animation durations are starting estimates.** The user has approved them as starting values; expect a tuning pass in playtest. Do not over-tune; ship the defaults below.
- **Hold Godot binary invocations to a minimum.** Each `Godot --headless` run causes a dock-icon focus flash on macOS. Batch test runs when possible; only invoke at the end of a task (not after every step).
- **CLAUDE.md applies:** YAGNI on speculative features (no reduced-motion toggle, no per-opponent UI tuning, no animation events / signals); don't add error handling for scenarios that can't happen; trust internal code.
- **Hard-cancel is the universal cancellation policy.** Every new `display()` / `show_*()` / `hide_prompt()` / `dismiss()` must kill the prior tween before starting its own. No queueing, no graceful-finish hand-off.

---

## File Structure

**Create:**
- `tests/unit/test_wasd_prompt_animation.gd` — pure-math helpers: `toss_horizontal_for(direction)` returns the per-direction horizontal toss offset (A=+80, D=−80, W=−40, S=+40); `shake_axis_for(direction)` returns the (dominant, perpendicular) axis pair for a given direction.

**Modify:**
- `scripts/ui/announcement_banner.gd` — add slide / opacity tween infrastructure; `show_banner` / `show_message` / `show_prompt` / `dismiss` all become async; add `_active_tween` ref; add static `total_duration_for(hold_seconds)` helper; constants `_SLIDE_OFFSET_X`, `_IN_DURATION`, `_OUT_DURATION`, ease curves.
- `scenes/ui/announcement_banner.tscn` — no node changes; the existing `CenterContainer` + `Image` + `Label` + `Backdrop` are sufficient. (Confirm during Increment 1 that `CenterContainer` doesn't fight the slide; if it does, switch the slide to apply to the `CenterContainer`'s `position` directly or animate `Image` + `Label` individually.)
- `scripts/ui/wasd_prompt.gd` — replace `display() / hide_prompt()` with a tween-driven implementation; add `_active_tween` ref; add per-variant private methods (`_animate_prompt_pulse`, `_animate_block_shake`, `_animate_damage_double_pulse`, `_animate_hit_toss`, `_animate_miss_double_pulse`); add constants block.
- `scripts/ui/wasd_prompt_layer.gd` — `flash / flash_success / flash_fail` keep the same signature; internally they call the new variant-aware `display()`. `hide_all()` stays snap-hide semantics (but routes through the new `hide_prompt` which now also kills the tween).
- `scripts/gameplay.gd` — three call sites:
  - line 156 `_banner.dismiss()` → `await _banner.dismiss()`.
  - lines 434-436 (`_play_knockdown_sequence` remainder math) — replace `MatchPacing.KNOCKDOWN_PAUSE - MatchPacing.KNOCK_DOWN_BANNER` with `MatchPacing.KNOCKDOWN_PAUSE - AnnouncementBanner.total_duration_for(MatchPacing.KNOCK_DOWN_BANNER)`.
  - No changes to flash sites (lines 225, 245, 262, 357, 371, 408) — the new behavior is internal to `WasdPrompt`.

**No changes:** `scripts/match_pacing.gd` (constants keep their existing meanings; the docstring is updated in CONTEXT.md, not in code), `scenes/ui/wasd_prompt.tscn`, `scenes/ui/wasd_prompt_layer.tscn`, any actor code, any gameplay phase logic, any audio/SFX wiring.

**UID files:** New `.gd` files get `.uid` sidecars auto-generated by Godot's project scan. Commit them alongside.

---

## Tuning constants (target values for this branch)

### `announcement_banner.gd`

```
const _SLIDE_OFFSET_X := 120.0
const _IN_DURATION := 0.25
const _OUT_DURATION := 0.20
# In: TRANS_QUAD / EASE_OUT (decelerate into rest)
# Out: TRANS_QUAD / EASE_IN  (accelerate out of rest)
```

### `wasd_prompt.gd`

```
# PROMPT variant
const _PROMPT_OVERSHOOT_SCALE := 1.15
const _PROMPT_PULSE_OUT_SECONDS := 0.08       # 0 → 1.15× ; opacity 0 → 1
const _PROMPT_PULSE_SETTLE_SECONDS := 0.04    # 1.15× → 1.0×
const _PROMPT_FADE_OUT_SECONDS := 0.08

# SUCCESS variant — Defense (Block Shake)
const _BLOCK_SHAKE_TOTAL_SECONDS := 0.18
const _BLOCK_SHAKE_STEPS := 5
const _BLOCK_SHAKE_DOMINANT_PX := 18.0
const _BLOCK_SHAKE_PERPENDICULAR_PX := 6.0
const _BLOCK_SETTLE_HOLD_SECONDS := 0.04
const _BLOCK_FADE_OUT_SECONDS := 0.08
# Step displacement table (dominant axis): [+18, -12, +8, -4, 0]
# Perpendicular: random ±6 per step. Linear transitions per step.

# FAIL variant — Defense (Damage Double-Pulse)
const _DAMAGE_PULSE1_TOTAL := 0.09            # 0 → 1.15× → 1.0× ; opacity 0 → 1
const _DAMAGE_PULSE2_TOTAL := 0.08            # 1.0× → 1.15× → 1.0×
const _DAMAGE_SHAKE_TOTAL := 0.10
const _DAMAGE_SHAKE_STEPS := 4
const _DAMAGE_SHAKE_DOMINANT_PX := 6.0
const _DAMAGE_SHAKE_PERPENDICULAR_PX := 2.0
const _DAMAGE_FADE_OUT_SECONDS := 0.08

# SUCCESS variant — Attack (Hit Toss)
const _ATTACK_HIT_PULSE_OUT := 0.05           # 0 → 1.15× ; opacity 0 → 1
const _ATTACK_HIT_PULSE_SETTLE := 0.03        # 1.15× → 1.0×
const _ATTACK_HIT_TOSS_SECONDS := 0.22
const _ATTACK_HIT_TOSS_END_SCALE := 0.85
const _ATTACK_HIT_TOSS_HORIZ_HOOK_PX := 80.0  # A / D
const _ATTACK_HIT_TOSS_HORIZ_JAB_PX  := 40.0  # W / S
const _ATTACK_HIT_TOSS_APEX_Y_PX := -80.0     # peak up
const _ATTACK_HIT_TOSS_END_Y_PX := 40.0       # past rest, below

# FAIL variant — Attack (Miss Double-Pulse)
const _ATTACK_MISS_PULSE1_TOTAL := 0.09
const _ATTACK_MISS_PULSE2_TOTAL := 0.08
const _ATTACK_MISS_HOLD := 0.10
const _ATTACK_MISS_FADE_OUT := 0.08
```

---

## Direction-to-axis mapping (locked)

These are the inputs to `toss_horizontal_for` and `shake_axis_for`. Tested directly via `tests/unit/test_wasd_prompt_animation.gd`.

### Toss horizontal direction (attack SUCCESS)

| Player attack | Punch travels | Toss horizontal | Toss magnitude |
|---|---|---|---|
| W (head, right glove) | up-left | **−x (left)** | jab (40 px) |
| A (left hook, left glove) | up-right | **+x (right)** | hook (80 px) |
| S (body, left glove) | up-right | **+x (right)** | jab (40 px) |
| D (right hook, right glove) | up-left | **−x (left)** | hook (80 px) |

Vertical component of the arc is uniform across all four (apex −80 px, end +40 px).

### Shake dominant axis (defense SUCCESS, defense FAIL)

The expected direction (the direction the opponent is punching) drives the shake. The prompt is pushed in the direction the punch's force carries.

| Opponent punch | Dominant axis | Sign |
|---|---|---|
| W (head punch lands top) | vertical | downward (+y) |
| A (left hook lands player-side) | horizontal | leftward from prompt POV (−x) |
| S (body punch lands center) | vertical | downward (+y) |
| D (right hook lands player-side) | horizontal | rightward from prompt POV (+x) |

(Perpendicular jitter is random per shake step; sign doesn't matter.)

---

# Increment 1 — Banner Slide + dismiss-async + KNOCKDOWN_PAUSE math fix

Replaces the snap-show / snap-hide of `AnnouncementBanner` with a horizontal slide + opacity envelope. `dismiss()` becomes async and is awaited at the one call site. Pays back the `KNOCKDOWN_PAUSE` math so the post-knockdown clock-pause stays a true 5.0s after the longer banner.

**Visible after this increment:** every banner — Ready, Fight, Round Over, Knock Down, Knock Out, You Win, You Lose, "Try again!", "Press K to start Round N" — slides in from the left + fades in, then slides out to the right + fades out. Backdrop fades with the banner. The match's clock-pause after a knockdown is unchanged in total wall-clock duration.

### Tasks

- [ ] **1.1** Cut branch. `git fetch && git pull origin main && git checkout -b feature/ui-animations`.
- [ ] **1.2** Add `_SLIDE_OFFSET_X`, `_IN_DURATION`, `_OUT_DURATION` constants + `_active_tween` field to `announcement_banner.gd`.
- [ ] **1.3** Refactor `show_banner`:
  - Set image / label visibility as today.
  - Set initial state: `position.x = rest_x - _SLIDE_OFFSET_X`, `modulate.a = 0`, `visible = true`.
  - Kill any prior tween. Tween position → rest_x and modulate.a → 1.0 over `_IN_DURATION` with `TRANS_QUAD / EASE_OUT` (parallel).
  - Await `tween.finished`.
  - Wait `duration_seconds` (the hold).
  - Run the out-tween: kill prior, tween position → rest_x + _SLIDE_OFFSET_X and modulate.a → 0 over `_OUT_DURATION` with `TRANS_QUAD / EASE_IN`. Await.
  - Set `visible = false`. Reset modulate.a = 1.0 and position.x = rest_x so the next show starts clean.
- [ ] **1.4** Apply the same refactor to `show_message` (text path).
- [ ] **1.5** Refactor `show_prompt` (held variant): same in-animation as 1.3 but **do not** wait for a duration or play out-animation. Returns once the in-animation finishes. `dismiss()` is now responsible for the out-animation.
- [ ] **1.6** Refactor `dismiss()`: kill prior tween, run the out-animation, await, then set `visible = false` and reset state. Now async.
- [ ] **1.7** Add `static func total_duration_for(hold_seconds: float) -> float: return _IN_DURATION + hold_seconds + _OUT_DURATION` on `AnnouncementBanner`.
- [ ] **1.8** Capture the rest position at `_ready()`. The slide tweens the `Control` root's `position.x` between rest_x − offset, rest_x, rest_x + offset. Confirm via a test boot that the centered banner image still lands at screen-center after the in-tween. If `CenterContainer` fights the position tween (likely — `CenterContainer` re-centers on every layout pass), animate the `CenterContainer.position.x` directly instead and document the choice inline.
- [ ] **1.9** Backdrop: animate the `Backdrop` ColorRect's `modulate.a` in parallel with the banner's modulate.a. Same in/out durations; no slide on the backdrop. The backdrop's *opacity* fades; the underlying color (0, 0, 0, 0.4) is multiplied by modulate.a so the effective opacity peaks at 0.4 and bottoms at 0.
- [ ] **1.10** Update `gameplay.gd` line 156: `_banner.dismiss()` → `await _banner.dismiss()`.
- [ ] **1.11** Update `gameplay.gd` lines 432-434 (`_play_knockdown_sequence` remainder math): replace `MatchPacing.KNOCKDOWN_PAUSE - MatchPacing.KNOCK_DOWN_BANNER` with `MatchPacing.KNOCKDOWN_PAUSE - AnnouncementBanner.total_duration_for(MatchPacing.KNOCK_DOWN_BANNER)`.
- [ ] **1.12** **Manual Playtest:**
  - Start a match. Ready slides in (left → center), fades to full opacity, holds, slides out (center → right), fades. Same for Fight. Both transitions move rightward and pass through center.
  - Lose a match (let HP drop to 0). "You Lose!" slides in/out.
  - Trigger a wrong-answer riddle (or just take Simon damage). Take damage enough times to deplete HP and verify the You-Lose path.
  - Trigger a neutral-answer riddle if available. "Try again!" slides in/out.
  - Trigger a knockdown (combo to x3 + complete attack phase). "Knock Down!" slides in/out, then verify the post-knockdown clock-pause feels ~5 seconds (not 5.45s — the math fix should keep it at the original total).
  - Lose Round 1 cleanly (let the clock run out). "Round Over!" slides in/out, then "Press K to start Round 2" slides in and **stays** (held), K-press → slides out, then Ready/Fight for Round 2.
  - Confirm no banner overlaps the next banner. Each fully completes its out-animation before the next begins.
- [ ] **1.13** Commit. Suggested message: `feat(ui): add banner slide+fade animations and async dismiss`.

---

# Increment 2 — Prompt Pulse (PROMPT variant, defense + attack show phases)

Replaces the snap-show / snap-hide of the PROMPT variant with a pulse grow-in + hold + quick fade-out. Same code path covers both defense and attack show phases — both call `display(direction, PROMPT)`.

**Visible after this increment:** every WASD show-phase telegraph pulses in (scale 0 → 1.15× → 1.0× with opacity fade-in) instead of snapping. Hold at rest. Then fades out quickly before the next step's PROMPT begins (or the next phase change clears it).

### Tasks

- [ ] **2.1** Add the PROMPT-variant constants block + `_active_tween` field + `_rest_scale` / `_rest_position` captures in `wasd_prompt.gd` (`_ready()` records the post-instance transform).
- [ ] **2.2** Add `_kill_active_tween()` helper that calls `if _active_tween: _active_tween.kill()` and nulls the ref. Used at the top of every `display()` call.
- [ ] **2.3** Add `_reset_to_clean_state()` that sets `position = _rest_position`, `scale = Vector2.ZERO`, `modulate.a = 0.0`. Called after `_kill_active_tween()` before each variant animation starts.
- [ ] **2.4** Add `_animate_prompt_pulse(duration_seconds)` private method:
  - Set sprite/label/background per the variant + direction (existing `display` body).
  - `_reset_to_clean_state()`. `visible = true`.
  - Parallel tween: scale 0 → 1.15× over `_PROMPT_PULSE_OUT_SECONDS`, then 1.15× → 1.0× over `_PROMPT_PULSE_SETTLE_SECONDS`; opacity 0 → 1.0 over `(_PROMPT_PULSE_OUT_SECONDS + _PROMPT_PULSE_SETTLE_SECONDS)`. (Two-stage scale via tween chain, opacity via one tween in parallel.)
  - Compute `hold = duration_seconds - _PROMPT_PULSE_OUT_SECONDS - _PROMPT_PULSE_SETTLE_SECONDS - _PROMPT_FADE_OUT_SECONDS`. If hold is negative (very fast difficulty), clamp to 0 — the pulse+fade alone consume the budget. Wait `hold`.
  - Final tween: opacity 1.0 → 0 over `_PROMPT_FADE_OUT_SECONDS`. Scale stays at 1.0. Await.
  - `visible = false`. Don't reset state yet — `_kill_active_tween` + `_reset_to_clean_state` on the next `display()` handles it.
- [ ] **2.5** Refactor `display(direction, variant)`: `_kill_active_tween()` first. Then switch on variant. For PROMPT, call `_animate_prompt_pulse(duration_seconds)`. (SUCCESS/FAIL still fall back to old snap-show in this increment; they get their own animations in Increments 3–6.) **Signature changes:** `display(direction, variant)` already takes the variant; the `duration_seconds` arg has to be threaded through. The cleanest path is to merge the existing layer-level `_flash_variant(direction, duration, variant)` so it passes duration into `display(direction, variant, duration_seconds)`.
- [ ] **2.6** Update `wasd_prompt_layer.gd`'s `_flash_variant` to call `prompt.display(direction, variant, duration_seconds)` and **remove** the `await get_tree().create_timer(duration_seconds).timeout` + `prompt.hide_prompt()` — the prompt now owns its own timing. The layer's flash methods (`flash`, `flash_success`, `flash_fail`) become fire-and-forget (no longer await an external timer).
- [ ] **2.7** Update `hide_prompt()` in `wasd_prompt.gd` to call `_kill_active_tween()`, `_reset_to_clean_state()`, then `visible = false`. (Hide remains a snap.)
- [ ] **2.8** Unit test in `tests/unit/test_wasd_prompt_animation.gd`: verify the constants block expected values (`_PROMPT_OVERSHOOT_SCALE == 1.15`, etc.). Not strictly necessary but cheap and catches accidental edits. No animation-behavior tests.
- [ ] **2.9** **Manual Playtest:**
  - Start a match. Each show-phase step's WASD prompt should pulse in (visibly grow with overshoot) instead of snapping. Should hold visible for the rest of the step. Should fade out before the next step's PROMPT pulses in.
  - Watch the Sebastian tier (highest difficulty, fastest `step_seconds` = 0.35s) to confirm the pulse + fade still fit in the budget. (Run the game, change `Globals.selected_difficulty` via the level select screen, or directly edit `Globals.selected_difficulty` if there's a debug path.) The pulse should still feel snappy — the hold may be negligible (0.15s).
  - Answer a riddle right to enter attack phase. Attack-phase show telegraphs should pulse identically (same `display()` codepath).
- [ ] **2.10** Commit. Suggested message: `feat(ui): add pulse grow-in for PROMPT variant flashes`.

---

# Increment 3 — Block Shake (defense SUCCESS variant)

Adds the SUCCESS-variant animation in defense: prompt appears at rest, shakes in 5 discrete stuttered steps along the impact axis with perpendicular jitter, then fades out.

**Visible after this increment:** when the player blocks a punch correctly, the W/A/S/D prompt at the expected direction shakes in place per direction (W and S shake vertically, A shakes left, D shakes right) before disappearing. Compare with the still-snappy FAIL/HIT_TOSS/MISS variants which haven't been animated yet.

### Tasks

- [ ] **3.1** Add `shake_axis_for(direction)` pure function: returns `Vector2(dominant_axis, perpendicular_axis)` where one component is `_BLOCK_SHAKE_DOMINANT_PX * sign` and the other is `_BLOCK_SHAKE_PERPENDICULAR_PX` (perpendicular jitter is added as `randf_range(-perp, +perp)` per step at use site).
  - W: `Vector2(0, +_BLOCK_SHAKE_DOMINANT_PX)` dominant (downward), perp = horizontal.
  - A: `Vector2(-_BLOCK_SHAKE_DOMINANT_PX, 0)` dominant (leftward), perp = vertical.
  - S: `Vector2(0, +_BLOCK_SHAKE_DOMINANT_PX)` dominant (downward), perp = horizontal.
  - D: `Vector2(+_BLOCK_SHAKE_DOMINANT_PX, 0)` dominant (rightward), perp = vertical.
  - Return value is just the magnitudes + axis assignment; the step displacement table is applied at the use site.
- [ ] **3.2** Add `_animate_block_shake(direction, duration_seconds)`:
  - Set sprite per variant + direction.
  - `_reset_to_clean_state()`. `visible = true`. Snap to `scale = Vector2.ONE` and `modulate.a = 1.0` instantly (no pulse-in).
  - Build a Tween. For each of the 5 steps `[+18, -12, +8, -4, 0]` in the dominant-axis displacement table:
    - Step duration = `_BLOCK_SHAKE_TOTAL_SECONDS / _BLOCK_SHAKE_STEPS` ≈ 0.036s.
    - Tween `position` to `_rest_position + (dominant_vec * step_factor) + perpendicular_jitter` using `TRANS_LINEAR` (stuttered).
    - `step_factor = step / 18.0` so the table normalizes to the actual displacement (the table values above are the px offsets directly; if `_BLOCK_SHAKE_DOMINANT_PX` is changed, the table scales proportionally).
  - After the shake, wait `_BLOCK_SETTLE_HOLD_SECONDS`.
  - Final tween: opacity 1.0 → 0 over `_BLOCK_FADE_OUT_SECONDS`. Position stays at `_rest_position` (last step set it to 0 offset).
  - `visible = false`.
- [ ] **3.3** Update `display()` switch: when variant == SUCCESS and not in attack phase, call `_animate_block_shake(direction, duration_seconds)`. **But** `WasdPrompt` doesn't currently know if it's in defense vs. attack — both use `Variant.SUCCESS`. Two options: (a) add an enum value `Variant.SUCCESS_ATTACK` so the variant itself carries the distinction; (b) add a `phase` parameter to `display()`. **Recommendation: option (a)** — add `Variant.SUCCESS_ATTACK` and `Variant.FAIL_ATTACK` to the `Variant` enum, route `WasdPromptLayer.flash_success` / `flash_fail` to choose between the defense and attack variants based on a new `phase` argument. The sprite swap (`<token>_success.png` vs `<token>_fail.png`) is unchanged — both SUCCESS variants load `<token>_success.png`.
  - Tweak: `WasdPromptLayer.flash_success(direction, duration)` becomes `flash_success(direction, duration, attack: bool = false)`. Gameplay defense path passes `false`; gameplay attack path passes `true`.
  - `gameplay.gd` line 245: `_prompts.flash_success(direction, _BLOCK_FLASH_SECONDS)` — stays the default (defense).
  - `gameplay.gd` line 371: `_prompts.flash_success(direction, _PUNCH_FLASH_SECONDS)` — adds `, true` for attack. (Held for Increment 5 if doing strict iteration ordering, but it's cleaner to thread the param in this increment and just have `_animate_hit_toss` still be a snap-show in this increment.) **Decision: thread the param in 3.3; Increments 5 + 6 fill in the attack-side animation bodies.**
- [ ] **3.4** Update `WasdPromptLayer.flash_fail` the same way (`attack: bool = false`) for parity. Defense damage path keeps default; attack miss path passes `true` in Increment 6.
- [ ] **3.5** Unit test in `tests/unit/test_wasd_prompt_animation.gd`: assert `shake_axis_for(HEAD).dominant == Vector2(0, _BLOCK_SHAKE_DOMINANT_PX)`, etc., for all four directions.
- [ ] **3.6** **Manual Playtest:**
  - Start a match. Block a W punch correctly. The W prompt should shake downward (5 stuttered jerks) then fade out.
  - Block an A punch. The A prompt should shake leftward.
  - Block a D punch. The D prompt should shake rightward.
  - Block an S punch. The S prompt should shake downward.
  - Confirm the shake feels "stuttered/jerky" (linear discrete steps, not smooth sine).
- [ ] **3.7** Commit. Suggested message: `feat(ui): add Block Shake for defense SUCCESS variant`.

---

# Increment 4 — Damage Double-Pulse (defense FAIL variant)

Adds the FAIL-variant animation in defense: two consecutive pulses, then a slight shake tail (~⅓ the amplitude of Block Shake), then fade out.

**Visible after this increment:** when the player takes a Simon hit (wrong key or timeout during repeat phase), the expected-direction prompt double-pulses then slightly shakes before disappearing. Reads as "you flubbed it — *thump-thump-rumble*".

### Tasks

- [ ] **4.1** Add `_animate_damage_double_pulse(direction, duration_seconds)`:
  - Set sprite per variant + direction. `_reset_to_clean_state()`. `visible = true`.
  - Pulse 1 (0 → _DAMAGE_PULSE1_TOTAL):
    - Parallel: scale 0 → 1.15× over 0.06s then 1.15× → 1.0× over 0.03s; opacity 0 → 1.0 over 0.09s.
  - Pulse 2 (immediate, no gap):
    - Scale 1.0× → 1.15× over 0.05s then 1.15× → 1.0× over 0.03s. Opacity stays 1.0.
  - Shake tail (immediate):
    - 4 discrete linear steps over `_DAMAGE_SHAKE_TOTAL` (0.10s). Step displacement table on dominant axis: `[+6, -4, +3, 0]`. Perpendicular jitter `±2` per step. Same `shake_axis_for(direction)` axis assignment as Block Shake but scaled to the damage amplitude.
  - Fade out: opacity 1.0 → 0 over `_DAMAGE_FADE_OUT_SECONDS`. Position returns to rest (last shake step sets it to 0 offset already).
  - `visible = false`.
- [ ] **4.2** Wire `display()`: when variant == FAIL and defense (default), call `_animate_damage_double_pulse`. Attack-FAIL still falls back to snap in this increment (Increment 6).
- [ ] **4.3** **Manual Playtest:**
  - Start a match. Deliberately fail a defense input (press the wrong key or let the input window expire).
  - Confirm the prompt at the *expected* direction (not the wrong key you pressed) double-pulses then shakes slightly, then fades out.
  - Try each direction (W, A, S, D) so the shake tail's per-direction axis is verified.
  - Compare against Block Shake — the FAIL shake should be visibly smaller (~⅓).
- [ ] **4.4** Commit. Suggested message: `feat(ui): add Damage Double-Pulse for defense FAIL variant`.

---

# Increment 5 — Hit Toss (attack SUCCESS variant)

Adds the SUCCESS-variant animation in attack: quick pulse grow-in, then "tossed" — translates along the punch's travel vector in a vertical arc while scaling down and fading out.

**Visible after this increment:** when the player lands an attack input, the just-pressed direction's prompt does a quick pulse then flies in the direction the punch was traveling — A/D (hooks) get larger horizontal travel than W/S (jabs); all four arc up then down past rest while fading to invisible.

### Tasks

- [ ] **5.1** Add `toss_horizontal_for(direction)` pure function. Returns the per-direction horizontal toss offset:
  - W → `-_ATTACK_HIT_TOSS_HORIZ_JAB_PX` (−40)
  - A → `+_ATTACK_HIT_TOSS_HORIZ_HOOK_PX` (+80)
  - S → `+_ATTACK_HIT_TOSS_HORIZ_JAB_PX` (+40)
  - D → `-_ATTACK_HIT_TOSS_HORIZ_HOOK_PX` (−80)
- [ ] **5.2** Add `_animate_hit_toss(direction, duration_seconds)`:
  - Set sprite per variant + direction. `_reset_to_clean_state()`. `visible = true`.
  - Pulse-in (0 → _ATTACK_HIT_PULSE_OUT + _ATTACK_HIT_PULSE_SETTLE = 0.08s):
    - Parallel: scale 0 → 1.15× over 0.05s then 1.15× → 1.0× over 0.03s; opacity 0 → 1.0 over 0.08s.
  - Toss phase (0.08 → 0.30s, duration 0.22s):
    - Let `horiz = toss_horizontal_for(direction)`.
    - Three sub-tweens chained, all running in parallel:
      - Position x: rest_x → rest_x + horiz * 0.5 (apex) → rest_x + horiz * 0.83 (descent) → rest_x + horiz (end). Approximated as a single tween with `TRANS_QUAD / EASE_IN` to taper toward the end. (Linear is acceptable as a starting value.)
      - Position y: rest_y → rest_y + _ATTACK_HIT_TOSS_APEX_Y_PX → rest_y → rest_y + _ATTACK_HIT_TOSS_END_Y_PX. The "up then down" arc. Implement as a tween chain: 0 → 0.5 of the toss duration tweens to apex (TRANS_QUAD EASE_OUT), 0.5 → 1.0 tweens to end_y (TRANS_QUAD EASE_IN).
      - Scale: 1.0 → _ATTACK_HIT_TOSS_END_SCALE over the full 0.22s, linear.
      - Opacity: 1.0 → 0 over the full 0.22s, linear.
  - `visible = false`. Position will be off-rest at the end; `_reset_to_clean_state()` on the next `display()` snaps it back.
- [ ] **5.3** Wire `display()`: when variant == SUCCESS_ATTACK (or whatever the enum value resolves to from Increment 3.3), call `_animate_hit_toss(direction, duration_seconds)`.
- [ ] **5.4** Unit test: `toss_horizontal_for(A) == +80`, `toss_horizontal_for(D) == -80`, `toss_horizontal_for(W) == -40`, `toss_horizontal_for(S) == +40`.
- [ ] **5.5** **Manual Playtest:**
  - Start a match. Answer a riddle correctly to enter attack phase.
  - Land each attack direction (W, A, S, D) and watch the prompt:
    - A → prompt flies rightward (+x) in an up-then-down arc, fades.
    - D → prompt flies leftward (−x) in an up-then-down arc, fades.
    - W → prompt flies leftward (smaller horizontal travel than D's hook), up-then-down, fades.
    - S → prompt flies rightward (smaller horizontal travel than A's hook), up-then-down, fades.
  - Confirm the prompt is *gone* (faded to invisible + off-rest) by the time the next attack step's PROMPT pulses in.
  - Run the chain at x3 finisher (longer chain — 3 or more inputs) to verify back-to-back tosses don't conflict.
- [ ] **5.6** Commit. Suggested message: `feat(ui): add Hit Toss for attack SUCCESS variant`.

---

# Increment 6 — Miss Double-Pulse (attack FAIL variant)

Adds the FAIL-variant animation in attack: two consecutive pulses, then a hold, then a fade-out. No shake (the prompt wasn't physically hit). No toss (the punch missed).

**Visible after this increment:** when the player misses an attack input (wrong key or timeout), the expected-direction prompt double-pulses, holds briefly, and fades — distinguishable from defense-FAIL (which has the shake tail) and from attack-SUCCESS (which has the toss arc).

### Tasks

- [ ] **6.1** Add `_animate_miss_double_pulse(direction, duration_seconds)`:
  - Set sprite per variant + direction (`<token>_fail.png`). `_reset_to_clean_state()`. `visible = true`.
  - Pulse 1 (0 → 0.09s): scale 0 → 1.15× → 1.0×; opacity 0 → 1.0.
  - Pulse 2 (0.09 → 0.17s): scale 1.0× → 1.15× → 1.0×.
  - Hold (0.17 → 0.27s): no animation, just wait `_ATTACK_MISS_HOLD`.
  - Fade out (0.27 → 0.35s): opacity 1.0 → 0 over `_ATTACK_MISS_FADE_OUT`. Scale stays 1.0. Position never leaves rest.
  - `visible = false`.
- [ ] **6.2** Wire `display()`: when variant == FAIL_ATTACK, call `_animate_miss_double_pulse(direction, duration_seconds)`.
- [ ] **6.3** **Manual Playtest:**
  - Start a match. Enter attack phase (answer a riddle right).
  - Miss an attack input (press the wrong key, or let the input window time out).
  - The expected-direction prompt should double-pulse, hold briefly, then fade. **No shake. No toss.**
  - Compare visually to defense-FAIL (which has a shake tail) — the difference should be obvious.
  - Compare to attack-SUCCESS — the missed prompt sits in place; the landed prompt flies away.
- [ ] **6.4** Commit. Suggested message: `feat(ui): add Miss Double-Pulse for attack FAIL variant`.

---

# Increment 7 — Final integration playtest + branch finish

End-to-end pass to catch interaction bugs that didn't show up in any single increment.

### Tasks

- [ ] **7.1** **Full match playtest:**
  - Start a match. Ready → Fight slide in/out.
  - Engage in defense for ~30 seconds. Confirm every PROMPT pulses cleanly. Block a few punches → Block Shake. Take a hit deliberately → Damage Double-Pulse.
  - Answer a riddle right → enter attack phase. Confirm PROMPT pulses in attack phase look identical to defense. Land all attack inputs → Hit Toss for each direction. Verify hooks (A/D) toss further than jabs (W/S).
  - Trigger an attack miss → Miss Double-Pulse.
  - Build to x3 and land a knockdown. "Knock Down!" slides in/out. The post-knockdown clock pause should feel ~5.0s (not 5.45s — confirms the math fix).
  - Take three knockdowns to trigger "Knock Out!" → "You Win!". Both banners slide in/out, no overlap.
  - Start a fresh match, lose all HP → "You Lose!" slides in/out.
  - Start a fresh match, let Round 1 expire → "Round Over!" → "Press K to start Round 2" (held) → K-press → out-animation → Ready/Fight Round 2.
- [ ] **7.2** **Fast-difficulty playtest:** play through Sebastian (or whichever is the highest tier) for 60+ seconds. Confirm PROMPT pulses still fit inside the 0.35s step budget without visible truncation. If the hold is too short to read, consider whether the pulse-in or fade-out durations need shrinking — but per the user's "starting values OK" approval, just observe and report; don't tune.
- [ ] **7.3** **Snap-clear regression check:** trigger every snap-clear path and confirm no prompt or banner is left stranded mid-animation:
  - Wrong-answer riddle → `_snap_clear_simon_visuals` is called → all prompts should disappear instantly.
  - Neutral-answer riddle → "Try again!" banner + chain replay → no leftover ghosts.
  - Right-answer riddle → attack phase entry → defense prompts disappear instantly.
  - Round-end while a prompt is mid-animation → `hide_all` + round-end banner. No flicker.
  - Match-loss while a prompt is mid-animation → `hide_all` + You-Lose banner. No flicker.
- [ ] **7.4** Run unit tests one last time: `Godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit`. Confirm the two new tests pass (`shake_axis_for`, `toss_horizontal_for`) and no existing test regressed.
- [ ] **7.5** Use the `superpowers:finishing-a-development-branch` skill to decide on merge / PR / cleanup. Suggested route: open a PR against `main`.

---

## Risk register

- **CenterContainer fighting the slide tween.** Godot's `CenterContainer` recomputes child positions every layout pass. If we tween the root `Control.position.x` and the `CenterContainer` snaps the image back to centered, the slide will be invisible. Mitigation: detect during Increment 1 task 1.8; if it fights, animate the `CenterContainer.position.x` directly (since the outer `Control` is full-screen). Worst case, drop `CenterContainer` and use direct anchors + offsets on the `Image` / `Label`.
- **Sebastian's 0.35s step budget eaten by pulse + fade.** The pulse-in is 0.12s and the fade-out is 0.08s — together 0.20s of the 0.35s budget. The hold is only 0.15s. Not a bug; flagged for the user's awareness in Increment 2's playtest.
- **Held-banner ("Press K to start Round N") + K-press during in-animation.** If the user presses K before the in-animation finishes, the in-tween must be killed and the out-tween started from the current state. The hard-cancel policy (`_kill_active_tween()` at the top of `dismiss()`) covers this — but worth explicitly testing in Increment 1 task 1.12.
- **Attack-SUCCESS prompt not back at rest when the next step's PROMPT fires.** The toss leaves the prompt at +horiz / +40 y / scale 0.85. The next `display()` calls `_reset_to_clean_state()` which restores rest_position, scale ZERO, opacity 0 before the new variant animates. Confirmed by design; tested in Increment 5 task 5.5.
- **`hide_all()` snap-hide during `_snap_clear_simon_visuals`.** Each prompt's `hide_prompt` kills its active tween + resets state. No graceful fade. This is intentional per Q10. Risk: a half-faded SUCCESS prompt could momentarily appear at rest-state-defaults (scale 0, opacity 0) before the `visible = false` lands — but in practice both happen in the same frame so it's invisible. Flagged for Increment 7 task 7.3.
- **Tween leak under rapid input.** If a player mashes through inputs at the x3 finisher pace, multiple back-to-back `display()` calls on the same prompt might leak tween references if `_active_tween` isn't reassigned correctly. Mitigation: `_kill_active_tween()` checks `if _active_tween:` (handles null) and `_active_tween = null` after kill; new tween is assigned to `_active_tween` after creation.
