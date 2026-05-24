# Sweat Particle FX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When the player lands an attack, spawn a brief CPUParticles2D-driven spray of light-blue-grey "sweat" droplets at the impact zone, flying in the direction the punch traveled.

**Architecture:** A new `SweatFX` Node2D scene with four pre-configured `CPUParticles2D` children (one per attack direction — `Head`, `Left`, `Body`, `Right`). Each emitter owns its own anchor offset and launch vector so overlapping bursts from finisher combos play in parallel without clobbering each other. The scene is mounted as a child of `Opponent`. Opponent exposes a `play_sweat(direction)` method; `gameplay.gd` calls it from `_on_attack_step_landed` on the same frame as the impact SFX and HIT pose.

**Tech Stack:** Godot 4.6 (GDScript), `CPUParticles2D` (web-export safe — no GPU compute shaders), `Gradient` resource for per-particle saturation variance. No tests — pure visual FX, motion-tuned by playtest per the design spec.

---

## File Structure

**Created:**
- `scripts/fx/sweat_fx.gd` — `SweatFX` class. Holds the per-direction anchor / launch constants, a `Direction → CPUParticles2D` lookup populated in `_ready`, and the `emit_for(direction: int)` entry point.
- `scenes/fx/sweat_fx.tscn` — Root `Node2D` named `SweatFX`, script attached, four `CPUParticles2D` children (`Head`, `Left`, `Body`, `Right`) each pre-wired with that direction's anchor position, launch direction vector, and shared motion config.

**Modified:**
- `scripts/actors/opponent.gd` — adds `@onready var _sweat_fx` and `play_sweat(direction: int)` method that forwards to `_sweat_fx.emit_for(direction)`.
- `scenes/actors/opponent.tscn` — adds a `SweatFX` instance as a child of the `Opponent` root, sibling of `Body` / `ReactionEmoteNeutral` / `ReactionEmoteWrong`.
- `scripts/gameplay.gd` — one line added in `_on_attack_step_landed` immediately after `_hit_opponent_for(direction)` (line 472).

**Untouched (verified against design):**
- `scripts/autoload/audio_bus.gd` — no new SFX; impact already carries `combo_success_*` + `opponent_punch_body`.
- `scripts/ui/wasd_prompt_layer.gd` and friends — no interaction with prompt animations; FX is purely opponent-side.
- `tests/` — no unit tests added per spec. Visual FX is verified by playtest.

---

### Task 1: Single-direction MVP — BODY-only sweat burst on S-attacks

**Files:**
- Create: `scripts/fx/sweat_fx.gd`
- Create: `scenes/fx/sweat_fx.tscn`
- Modify: `scripts/actors/opponent.gd:67-69` (add `_sweat_fx` `@onready` ref)
- Modify: `scripts/actors/opponent.gd` (append `play_sweat` method, end of file)
- Modify: `scenes/actors/opponent.tscn` (add `SweatFX` instance as child of root)
- Modify: `scripts/gameplay.gd:472` (insert one line)

The point of this task is to prove the end-to-end integration path — gameplay → opponent → SweatFX → visible CPUParticles2D burst — with the minimum surface area. Only the BODY direction emits; the other three directions silently no-op until Task 2 fills them in. Color treatment and tuning are deferred (default-white squares, generic motion).

- [ ] **Step 1: Create the SweatFX script with BODY-only routing**

Create `scripts/fx/sweat_fx.gd`:

```gdscript
class_name SweatFX
extends Node2D

# Per-direction sweat burst on player-landed attacks. Each Direction owns its
# own CPUParticles2D child so overlapping finisher bursts play in parallel
# without restart() clobbering an in-flight spray.
#
# This file is the single-source tuning surface — playtest iteration is a
# constants-only edit. See docs/superpowers/specs/2026-05-24-sweat-particle-fx-design.md.

# Anchor offsets in Opponent-local coordinates. Y values are placeholder
# guesses — Task 3 verifies them against the actual sprite layout in the
# editor and snapshots the corrected values back.
const IMPACT_OFFSETS := {
	SimonSequence.Direction.HEAD:  Vector2(  0, 690),
	SimonSequence.Direction.LEFT:  Vector2(-90, 690),
	SimonSequence.Direction.BODY:  Vector2(  0, 820),
	SimonSequence.Direction.RIGHT: Vector2( 90, 690),
}

# Per-direction launch vectors. Sign convention matches
# WasdPrompt.toss_horizontal_for(): jabs (W/S) lean slightly upward in the
# matching horizontal direction, hooks (A/D) lean more horizontal.
const LAUNCH_VECTORS := {
	SimonSequence.Direction.HEAD:  Vector2(-0.5, -1.0),
	SimonSequence.Direction.LEFT:  Vector2( 1.0, -0.6),
	SimonSequence.Direction.BODY:  Vector2( 0.5, -1.0),
	SimonSequence.Direction.RIGHT: Vector2(-1.0, -0.6),
}

var _emitters: Dictionary = {}

func _ready() -> void:
	_emitters[SimonSequence.Direction.HEAD]  = get_node_or_null("Head")
	_emitters[SimonSequence.Direction.LEFT]  = get_node_or_null("Left")
	_emitters[SimonSequence.Direction.BODY]  = get_node_or_null("Body")
	_emitters[SimonSequence.Direction.RIGHT] = get_node_or_null("Right")

func emit_for(direction: int) -> void:
	var emitter: CPUParticles2D = _emitters.get(direction)
	if emitter == null:
		return
	emitter.restart()
```

- [ ] **Step 2: Create the sweat_fx.tscn scene with the BODY emitter only**

Create `scenes/fx/sweat_fx.tscn`. Write the file by hand using the content below; Godot will normalize and assign UIDs the first time the editor opens it.

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/fx/sweat_fx.gd" id="1_sweat_fx"]

[node name="SweatFX" type="Node2D"]
script = ExtResource("1_sweat_fx")

[node name="Body" type="CPUParticles2D" parent="."]
position = Vector2(0, 820)
emitting = false
amount = 12
lifetime = 0.6
one_shot = true
explosiveness = 1.0
direction = Vector2(0.5, -1.0)
spread = 18.0
gravity = Vector2(0, 980)
initial_velocity_min = 180.0
initial_velocity_max = 320.0
scale_amount_min = 2.0
scale_amount_max = 4.0
```

The other three `CPUParticles2D` children (`Head`, `Left`, `Right`) are deliberately omitted — Task 2 adds them. The script's `_ready` already calls `get_node_or_null(...)` for all four names, so the missing children resolve to `null` and the script's lookup safely no-ops.

- [ ] **Step 3: Wire SweatFX into the Opponent scene**

Open `scenes/actors/opponent.tscn` and add a new node block. The new content should appear after the existing `ReactionEmoteWrong` block (around line 25). Add this `[ext_resource]` near the top of the file alongside the existing ones, and the `[node]` block at the bottom:

Add to the resource list:
```
[ext_resource type="PackedScene" path="res://scenes/fx/sweat_fx.tscn" id="4_sweat_fx"]
```

Append after the existing `ReactionEmoteWrong` node:
```
[node name="SweatFX" parent="." instance=ExtResource("4_sweat_fx")]
```

Update the `[gd_scene]` header's `load_steps` value to account for the new ext_resource (was `4`, becomes `5`).

- [ ] **Step 4: Add the Opponent API**

In `scripts/actors/opponent.gd`, add an `@onready` field for the new node. Around line 67-69, beneath the existing `_sprite`/`_emote_*` declarations:

```gdscript
@onready var _sprite: Sprite2D = $Body
@onready var _emote_neutral: Sprite2D = $ReactionEmoteNeutral
@onready var _emote_wrong: Sprite2D = $ReactionEmoteWrong
@onready var _sweat_fx: SweatFX = $SweatFX
```

Then append the public method to the end of the file:

```gdscript

# Trigger a per-direction sweat burst at the impact zone. Called by
# gameplay.gd from _on_attack_step_landed, on the same frame as the
# combo_success SFX and the HIT_* pose.
func play_sweat(direction: int) -> void:
	_sweat_fx.emit_for(direction)
```

- [ ] **Step 5: Wire the gameplay call site**

In `scripts/gameplay.gd`, find `_on_attack_step_landed` (around line 455). After the existing `_hit_opponent_for(direction)` call at line 472, insert the sweat call:

Before:
```gdscript
	_prompts.flash_success(direction, _PUNCH_FLASH_SECONDS, true)
	_hit_opponent_for(direction)
	_gloves.set_state(PlayerGloves.State.PUNCH, direction)
```

After:
```gdscript
	_prompts.flash_success(direction, _PUNCH_FLASH_SECONDS, true)
	_hit_opponent_for(direction)
	_opponent.play_sweat(direction)
	_gloves.set_state(PlayerGloves.State.PUNCH, direction)
```

- [ ] **Step 6: Playtest — confirm BODY direction emits**

Open Godot to let it import the new files (auto-generates UIDs and `.import` sidecars), then run the game and play through a match until you reach the attack phase.

Verify:
1. When you land an S (body) attack, a brief white-square spray fires from the torso area of the opponent and arcs downward under gravity.
2. When you land W / A / D attacks, **no** sweat fires — those directions are deliberately wired to no-op until Task 2.
3. The W/A/D attacks still behave normally otherwise (HIT poses, SFX, prompts) — confirms the call site isn't breaking the other directions' flow.
4. No errors in the Godot console — particularly no "null instance" errors from `_sweat_fx`.

If the BODY burst appears at the wrong vertical position on the opponent's torso, leave it for Task 3 — that's where anchor offsets get verified in the editor.

- [ ] **Step 7: Commit**

```bash
git add scripts/fx/sweat_fx.gd scenes/fx/sweat_fx.tscn \
        scripts/actors/opponent.gd scenes/actors/opponent.tscn \
        scripts/gameplay.gd
git commit -m "$(cat <<'EOF'
feat(fx): wire sweat-burst MVP on player BODY attacks

Single CPUParticles2D emitter fires from the opponent's torso when
the player lands an S-attack. Proves the gameplay → opponent → SweatFX
integration path end-to-end. Other three directions wired in next task.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Expand to all four directions

**Files:**
- Modify: `scenes/fx/sweat_fx.tscn` (add three more `CPUParticles2D` children)

After this task, every landed attack (W/A/S/D) fires a sweat burst with that direction's launch vector and (placeholder) anchor offset. Anchor verification is still deferred to Task 3 — for now, all three new emitters use the same Y placeholder values as in `IMPACT_OFFSETS`, so heads-targeted attacks may visibly originate from the wrong vertical slot. That's fine — Task 3 fixes it.

- [ ] **Step 1: Add the three remaining emitter children to sweat_fx.tscn**

Append after the existing `Body` node block in `scenes/fx/sweat_fx.tscn`:

```
[node name="Head" type="CPUParticles2D" parent="."]
position = Vector2(0, 690)
emitting = false
amount = 12
lifetime = 0.6
one_shot = true
explosiveness = 1.0
direction = Vector2(-0.5, -1.0)
spread = 18.0
gravity = Vector2(0, 980)
initial_velocity_min = 180.0
initial_velocity_max = 320.0
scale_amount_min = 2.0
scale_amount_max = 4.0

[node name="Left" type="CPUParticles2D" parent="."]
position = Vector2(-90, 690)
emitting = false
amount = 12
lifetime = 0.6
one_shot = true
explosiveness = 1.0
direction = Vector2(1.0, -0.6)
spread = 18.0
gravity = Vector2(0, 980)
initial_velocity_min = 180.0
initial_velocity_max = 320.0
scale_amount_min = 2.0
scale_amount_max = 4.0

[node name="Right" type="CPUParticles2D" parent="."]
position = Vector2(90, 690)
emitting = false
amount = 12
lifetime = 0.6
one_shot = true
explosiveness = 1.0
direction = Vector2(-1.0, -0.6)
spread = 18.0
gravity = Vector2(0, 980)
initial_velocity_min = 180.0
initial_velocity_max = 320.0
scale_amount_min = 2.0
scale_amount_max = 4.0
```

Each node's `position` matches `IMPACT_OFFSETS` for that direction; each node's `direction` matches `LAUNCH_VECTORS`. All other motion parameters are identical to the BODY emitter from Task 1 — Task 5 tunes them as a global pass.

- [ ] **Step 2: Playtest — confirm all four directions emit**

Run the game and play through an attack phase. Trigger each of W / A / S / D at least once. For each landed attack, verify:

1. A spray fires from somewhere on the opponent (exact head vs. torso position is still placeholder-ish — fix in Task 3).
2. The spray's horizontal direction matches the punch's travel direction:
   - W (head jab, right glove going up-left) → spray flies up-and-to-the-left
   - A (left hook, glove going up-right) → spray flies right
   - S (body jab, left glove going up-right) → spray flies up-and-to-the-right
   - D (right hook, glove going up-left) → spray flies left
3. Trigger a 3-hit finisher and confirm overlapping bursts play in parallel — the 2nd punch's spray does **not** wipe the 1st's particles mid-flight.
4. No errors in the console.

If a direction's spray flies the wrong way, double-check the matching `direction` vector in the `.tscn` against the `LAUNCH_VECTORS` table in `sweat_fx.gd`.

- [ ] **Step 3: Commit**

```bash
git add scenes/fx/sweat_fx.tscn
git commit -m "$(cat <<'EOF'
feat(fx): wire sweat bursts for all four attack directions

Three additional CPUParticles2D emitters (Head/Left/Right) each
pre-configured with that direction's launch vector and placeholder
anchor offset. Overlapping finisher bursts now play in parallel.
Anchor offsets verified in the next task.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Verify and adjust anchor offsets in the editor

**Files:**
- Modify: `scenes/fx/sweat_fx.tscn` (snapshot corrected per-direction `position` values)
- Modify: `scripts/fx/sweat_fx.gd` (snapshot corrected `IMPACT_OFFSETS` constants)

The spec flags the head/torso Y-values in `IMPACT_OFFSETS` as `— VERIFY` placeholders because the opponent Body sprite's center sits at world `(960, 1220)` — well below the 1920x1080 viewport. The visible character must extend upward from its sprite center, but the exact head and torso pixel positions depend on the texture layout. This task verifies them visually.

- [ ] **Step 1: Open the opponent scene in Godot**

Open `scenes/actors/opponent.tscn` in the Godot editor. Find the `SweatFX` instance in the Scene tree. Expand its children — you should see `Head`, `Left`, `Body`, `Right`.

- [ ] **Step 2: Drag each emitter onto the correct visual zone**

For each of the four child emitters, with the Opponent sprite visible in the 2D viewport:

1. Select the emitter in the Scene tree.
2. In the 2D viewport, drag the emitter's gizmo to the visible target zone:
   - `Head` → center of the visible head/face
   - `Left` → opponent's right cheek (left from our viewer POV)
   - `Body` → center of the visible torso
   - `Right` → opponent's left cheek (right from our viewer POV)
3. Note the new `position` value in the Inspector.

These positions are now in Opponent-local coordinates and will be reflected in `sweat_fx.tscn`'s `position = Vector2(...)` lines.

- [ ] **Step 3: Save the scene and snapshot the values back into the script**

After saving the scene, open `scripts/fx/sweat_fx.gd` and update `IMPACT_OFFSETS` so its values match what's now in the `.tscn`. The script constants are the documentation; the scene is the runtime source of truth — keeping them in sync makes the design self-explanatory.

Drop the `— VERIFY` comment tail from each line at the same time.

Example (your actual values will differ):

```gdscript
const IMPACT_OFFSETS := {
	SimonSequence.Direction.HEAD:  Vector2(  0, 350),
	SimonSequence.Direction.LEFT:  Vector2(-80, 380),
	SimonSequence.Direction.BODY:  Vector2(  0, 600),
	SimonSequence.Direction.RIGHT: Vector2( 80, 380),
}
```

- [ ] **Step 4: Playtest — confirm anchor positions read correctly**

Run the game and trigger each of W / A / S / D. For each:

1. The spray clearly originates from the matching visible body part (head front, right cheek, torso, left cheek).
2. The spray direction still points the way the punch was traveling.
3. Bursts at different directions are visually distinguishable as "different impact zones," not all clustered at one anchor.

- [ ] **Step 5: Commit**

```bash
git add scenes/fx/sweat_fx.tscn scripts/fx/sweat_fx.gd
git commit -m "$(cat <<'EOF'
fix(fx): snapshot verified per-direction sweat anchor offsets

Adjusted each emitter's position to its visible head/torso zone on
the opponent and mirrored the values into IMPACT_OFFSETS so the
script constants document the runtime layout.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Color treatment — light-blue-grey with per-particle saturation variance

**Files:**
- Modify: `scenes/fx/sweat_fx.tscn` (add color + gradient resources, reference them from each emitter)

Replaces the default white squares with a light-blue-grey palette where each emitted droplet samples a random saturation point along a gradient, so a single burst reads as a mix of cooler and warmer drops rather than a uniform monochrome blob.

CPUParticles2D color knobs:
- `color` — base tint multiplied with everything else.
- `color_initial_ramp` — `Gradient` sampled **once at emission** per particle. This is the per-particle variance knob.
- `color_ramp` — `Gradient` sampled across each particle's lifetime. Drives the alpha fade-out.

- [ ] **Step 1: Add the two Gradient sub-resources to the .tscn header**

`CPUParticles2D.color_initial_ramp` and `color_ramp` both take a raw `Gradient` resource (verified against Godot 4.6's API — this differs from `ParticleProcessMaterial` which uses `GradientTexture1D`; don't confuse the two).

At the top of `scenes/fx/sweat_fx.tscn`, after the existing `[ext_resource]` line, add two `[sub_resource]` blocks. Bump `load_steps` in the `[gd_scene]` header to `4` (was `2`).

```
[gd_scene load_steps=4 format=3]

[ext_resource type="Script" path="res://scripts/fx/sweat_fx.gd" id="1_sweat_fx"]

[sub_resource type="Gradient" id="Gradient_initial"]
offsets = PackedFloat32Array(0, 1)
colors = PackedColorArray(0.78, 0.80, 0.82, 1, 0.65, 0.78, 0.92, 1)

[sub_resource type="Gradient" id="Gradient_alpha"]
offsets = PackedFloat32Array(0, 1)
colors = PackedColorArray(1, 1, 1, 1, 1, 1, 1, 0)
```

`Gradient_initial` runs from `(0.78, 0.80, 0.82)` (near-grey) to `(0.65, 0.78, 0.92)` (cooler blue-grey); each particle samples a random point at emission for per-droplet saturation variance.

`Gradient_alpha` fades alpha from 1.0 → 0.0 across the particle's lifetime. RGB is held at white throughout so the fade doesn't fight the base `color` or the initial-ramp tint — only the alpha channel changes.

- [ ] **Step 2: Reference the color resources from each of the four emitters**

For each of the four `[node ... type="CPUParticles2D"]` blocks (`Head`, `Left`, `Body`, `Right`), add these three property lines:

```
color = Color(0.72, 0.80, 0.86, 1)
color_initial_ramp = SubResource("Gradient_initial")
color_ramp = SubResource("Gradient_alpha")
```

Insert them after the existing `scale_amount_max = 4.0` line on each block. Same three lines on all four emitters — color treatment is uniform across directions.

- [ ] **Step 3: Playtest — confirm color treatment reads**

Run the game. Trigger each direction's attack and verify:

1. Droplets are no longer pure white — they're a cool light-blue-grey.
2. Within a single burst, individual droplets visibly differ in saturation: some look more neutral grey, others tinted bluer. The variance should be subtle but noticeable.
3. Droplets fade out smoothly toward the end of their lifetime (don't pop out of existence).
4. The fade doesn't blow out — drops shouldn't go to pure black or pure white at the end. If they do, recheck `Gradient_alpha`'s color values (should be `(1,1,1,1)` → `(1,1,1,0)` — only alpha changes).

- [ ] **Step 4: Commit**

```bash
git add scenes/fx/sweat_fx.tscn
git commit -m "$(cat <<'EOF'
feat(fx): paint sweat droplets light-blue-grey with per-drop variance

Two gradient sub-resources drive the look: color_initial_ramp samples
a random saturation per emitted particle (near-grey → cool blue-grey),
color_ramp fades alpha over the particle's lifetime. Base color tint
binds the palette.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Motion feel tuning pass

**Files:**
- Modify: `scenes/fx/sweat_fx.tscn` (adjust shared motion constants on each emitter)

This is the playtest-driven tuning pass. The starting numbers (`amount=12`, `lifetime=0.6`, `gravity=(0,980)`, `initial_velocity_min=180`, `initial_velocity_max=320`, `spread=18°`, `scale_amount_min=2.0`, `scale_amount_max=4.0`) are educated guesses — Task 5 turns them into final values by feel.

Because the four emitters share identical motion config (only `position` and `direction` differ between them), any change applies to all four — when adjusting, change all four `.tscn` blocks consistently.

- [ ] **Step 1: Run extended playtest across all four directions and finisher chains**

Play several rounds, focusing on the attack phases. Pay attention to:

1. **Count** — Is 12 drops enough to feel like a "burst"? Too many to read individually? Tune `amount` (try 8 / 15 / 20).
2. **Speed** — Do drops launch with enough force to feel like impact ejecta? Or do they trickle? Tune `initial_velocity_min` / `initial_velocity_max`.
3. **Gravity** — Do drops arc and fall the way real sweat would, or do they hang too long / fall too fast? Tune the `gravity` Y component (currently 980 — try 600 / 1400).
4. **Lifetime** — Are drops still on screen after they've physically "landed," looking stale? Or do they fade before the eye registers the arc? Tune `lifetime`.
5. **Spread** — Is the spray cone too tight (rope-like) or too wide (cloud-like)? Tune `spread` (try 10° / 30° / 45°).
6. **Size** — Are drops visible at the gameplay distance? Or do they get lost? Tune `scale_amount_min` / `scale_amount_max`.

- [ ] **Step 2: Apply tuned values to all four emitter blocks in sweat_fx.tscn**

Each property change must be made on all four `[node ... type="CPUParticles2D"]` blocks (`Head`, `Left`, `Body`, `Right`) so the motion stays uniform across directions.

For example, if you settle on `amount = 15`, `lifetime = 0.5`, and `gravity = Vector2(0, 1200)`, those three lines change identically across all four blocks.

- [ ] **Step 3: Final playtest pass — golden path + edge cases**

1. **Single hits at each direction** — burst reads correctly in isolation.
2. **2-hit and 3-hit finishers** — overlapping bursts compose well; the cumulative effect at the 3rd hit is escalating, not muddy.
3. **Edge of the input window** — a punch landing late in the input window still produces a clean burst; no timing-driven artifacts.
4. **KO frame** — if the player lands the killing blow, the burst still fires before the knockdown sequence takes over. (The burst is fire-and-forget — it owns its own lifetime — so a KO immediately after shouldn't truncate the spray.)
5. **Web export sanity check** — export to web (Project → Export → Web), open the result in a browser, and confirm the bursts render correctly in WebGL 2 with no console errors. CPU particles should be web-safe, but worth a one-time verification.

- [ ] **Step 4: Commit**

```bash
git add scenes/fx/sweat_fx.tscn
git commit -m "$(cat <<'EOF'
chore(fx): tune sweat burst motion — final feel pass

Final values for amount, lifetime, velocity range, gravity, spread,
and scale settled by playtest across all four directions and at
finisher density. Web export verified.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```
