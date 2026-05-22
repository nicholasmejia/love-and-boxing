# Attract Sequence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the animated opening "Attract Sequence" that plays from cold-boot — three character pennants slide in, an attract punch knocks them off, the camera pans down onto the boxing ring, the title slams in with a flash, and `Press K to start` pulses — then fades to the existing button menu.

**Architecture:** New `scenes/attract_sequence.tscn` becomes the cold-boot `main_scene`. The existing `title_screen.tscn` (which is actually the button menu) gets renamed to `main_menu.tscn` to match CONTEXT.md. A single controller script (`scripts/attract_sequence.gd`) holds the state machine, the tunable constants block (same convention as `announcement_banner.gd` / `wasd_prompt.gd`), the tween orchestration, and the input handler. Phase timing is locked against the 11.636s `title_intro.ogg` stinger as a master clock; the Title Slam's white flash coincides with a hard cut to `title_main_loop.ogg`.

**Tech Stack:** Godot 4.6 (Control nodes + Tween), GDScript, AudioBus autoload, GUT 9.x for pure-logic tests. Visual phases are manually playtested per the project's "user is the test harness for visual/feel work" convention.

---

## File Structure

**Renames (Task 1):**
- `scenes/title_screen.tscn` → `scenes/main_menu.tscn`
- `scripts/title_screen.gd` → `scripts/main_menu.gd`
- `scripts/title_screen.gd.uid` → `scripts/main_menu.gd.uid`

**Modifies:**
- `scripts/autoload/scene_router.gd` — `TITLE` const → `MAIN_MENU`, `goto_title()` → `goto_main_menu()`, plus add `ATTRACT_SEQUENCE` const and main-scene flip stays consistent.
- `scripts/autoload/audio_bus.gd` — adds `"title_intro"` and `"title_main_loop"` to `MUSIC_TRACKS`.
- `project.godot` — `run/main_scene` flips to `res://scenes/attract_sequence.tscn`.

**Creates:**
- `scenes/attract_sequence.tscn` — the new screen, single scene file with all sprite nodes.
- `scripts/attract_sequence.gd` — controller (constants, state machine, tween orchestration, input).
- `tests/unit/test_audio_bus_title_tracks.gd` — verifies the two new MUSIC_TRACKS entries resolve.

---

## Task 1: Rename `title_screen` → `main_menu` (no behavior change)

CONTEXT.md now classifies the button screen as **Main Menu**, not Title Screen. This task aligns the filesystem with the glossary. Pure rename + path updates, zero behavior delta. The game must boot to the same screen with the same buttons working identically.

**Files:**
- Rename: `scenes/title_screen.tscn` → `scenes/main_menu.tscn`
- Rename: `scripts/title_screen.gd` → `scripts/main_menu.gd`
- Rename: `scripts/title_screen.gd.uid` → `scripts/main_menu.gd.uid`
- Modify: `scripts/autoload/scene_router.gd` (rename constant + method)
- Modify: `scenes/main_menu.tscn` (after rename — update `ext_resource` path)
- Modify: `project.godot:14` (update `run/main_scene`)

- [ ] **Step 1: Rename the three files**

```bash
git mv scenes/title_screen.tscn scenes/main_menu.tscn
git mv scripts/title_screen.gd scripts/main_menu.gd
git mv scripts/title_screen.gd.uid scripts/main_menu.gd.uid
```

- [ ] **Step 2: Update the scene file's script reference**

Open `scenes/main_menu.tscn`. The third line currently reads:

```
[ext_resource type="Script" path="res://scripts/title_screen.gd" id="1_lab01"]
```

Replace with:

```
[ext_resource type="Script" path="res://scripts/main_menu.gd" id="1_lab01"]
```

Also update the root node name on line 5 — currently `[node name="TitleScreen" type="Control"]`. Replace with:

```
[node name="MainMenu" type="Control"]
```

- [ ] **Step 3: Update `scripts/autoload/scene_router.gd`**

Replace the entire file contents with:

```gdscript
extends Node

const ATTRACT_SEQUENCE := "res://scenes/attract_sequence.tscn"
const MAIN_MENU := "res://scenes/main_menu.tscn"
const LEVEL_SELECT := "res://scenes/level_select.tscn"
const GAMEPLAY := "res://scenes/gameplay.tscn"
const MATCH_RESULTS := "res://scenes/match_results.tscn"

func goto_attract_sequence() -> void:
	get_tree().change_scene_to_file(ATTRACT_SEQUENCE)

func goto_main_menu() -> void:
	get_tree().change_scene_to_file(MAIN_MENU)

func goto_level_select() -> void:
	get_tree().change_scene_to_file(LEVEL_SELECT)

func goto_gameplay() -> void:
	get_tree().change_scene_to_file(GAMEPLAY)

func goto_match_results() -> void:
	get_tree().change_scene_to_file(MATCH_RESULTS)

func quit_game() -> void:
	get_tree().quit()
```

Note: `ATTRACT_SEQUENCE` and `goto_attract_sequence` are added now even though the scene doesn't exist yet — Task 3 creates it. The const is a string literal, so this compiles fine.

- [ ] **Step 4: Update `project.godot` main_scene to the renamed path**

Open `project.godot`. Find line 14:

```
run/main_scene="res://scenes/title_screen.tscn"
```

Replace with:

```
run/main_scene="res://scenes/main_menu.tscn"
```

(We'll flip this to `attract_sequence.tscn` in Task 3 once that scene exists. Pointing main_scene at the renamed Main Menu in this task keeps the game bootable between tasks.)

- [ ] **Step 5: Verify no other call sites reference the old names**

Run:

```bash
grep -rn "title_screen\|goto_title\|SceneRouter.TITLE" scripts scenes project.godot
```

Expected: **no matches**. If anything matches, update it before moving on.

- [ ] **Step 6: Boot the game in the Godot editor and confirm Main Menu still works**

Manual playtest checklist:
- Game opens to the Main Menu (red-tinted background, four buttons).
- Arrow / IJKL navigation moves focus.
- K / Enter on Start → Level Select.
- K / Enter on Quit → game quits.

- [ ] **Step 7: Commit**

```bash
git add scenes/main_menu.tscn scripts/main_menu.gd scripts/main_menu.gd.uid scripts/autoload/scene_router.gd project.godot
git commit -m "refactor: rename title_screen scene to main_menu to match glossary"
```

---

## Task 2: Wire `title_intro` and `title_main_loop` into AudioBus

The two new BGM files (`title_intro.ogg` stinger and `title_main_loop.ogg` seamless loop) already live in `assets/audio/bgm/` with the correct `.import` loop flags (verified during planning: intro=false, loop=true). All that's left is registering them as named tracks in `MUSIC_TRACKS`.

**Files:**
- Modify: `scripts/autoload/audio_bus.gd:3-7`
- Test: `tests/unit/test_audio_bus_title_tracks.gd` (create)

- [ ] **Step 1: Write the failing GUT test**

Create `tests/unit/test_audio_bus_title_tracks.gd`:

```gdscript
extends GutTest

func test_title_intro_track_registered():
	assert_true(AudioBus.MUSIC_TRACKS.has("title_intro"),
		"AudioBus.MUSIC_TRACKS should contain 'title_intro' key")
	assert_not_null(AudioBus.MUSIC_TRACKS["title_intro"],
		"'title_intro' should resolve to an AudioStream resource")

func test_title_main_loop_track_registered():
	assert_true(AudioBus.MUSIC_TRACKS.has("title_main_loop"),
		"AudioBus.MUSIC_TRACKS should contain 'title_main_loop' key")
	assert_not_null(AudioBus.MUSIC_TRACKS["title_main_loop"],
		"'title_main_loop' should resolve to an AudioStream resource")
```

- [ ] **Step 2: Run the test to verify failure**

Run from the Godot editor (Project → Tools → GUT panel → Run All), or via the GUT CLI if configured:

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_audio_bus_title_tracks.gd
```

Expected: both assertions fail because the keys are missing.

- [ ] **Step 3: Add the two preloads to AudioBus**

Open `scripts/autoload/audio_bus.gd`. Replace lines 3-7:

```gdscript
const MUSIC_TRACKS := {
	"menu": preload("res://assets/audio/bgm/menu.ogg"),
	"victory": preload("res://assets/audio/bgm/victory.ogg"),
	"defeat": preload("res://assets/audio/bgm/defeat.ogg"),
}
```

With:

```gdscript
const MUSIC_TRACKS := {
	"menu": preload("res://assets/audio/bgm/menu.ogg"),
	"victory": preload("res://assets/audio/bgm/victory.ogg"),
	"defeat": preload("res://assets/audio/bgm/defeat.ogg"),
	"title_intro": preload("res://assets/audio/bgm/title_intro.ogg"),
	"title_main_loop": preload("res://assets/audio/bgm/title_main_loop.ogg"),
}
```

- [ ] **Step 4: Run the test to verify it now passes**

Same command as Step 2. Expected: both tests pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/autoload/audio_bus.gd tests/unit/test_audio_bus_title_tracks.gd
git commit -m "feat(audio): register title_intro stinger + title_main_loop in AudioBus"
```

---

## Task 3: Stub `attract_sequence` scene that immediately routes to Main Menu

Stand up the new scene as the cold-boot entry point. In this task it does nothing visually — it just routes straight to Main Menu so the game remains bootable end-to-end. Subsequent tasks add the actual content. This is the playable scaffold.

**Files:**
- Create: `scenes/attract_sequence.tscn`
- Create: `scripts/attract_sequence.gd`
- Modify: `project.godot:14`

- [ ] **Step 1: Create the stub controller script**

Create `scripts/attract_sequence.gd`:

```gdscript
extends Control

func _ready() -> void:
	# TODO: full Attract Sequence animation. For now, route to Main Menu so
	# the game remains bootable while later tasks build out the content.
	call_deferred("_route_to_main_menu")

func _route_to_main_menu() -> void:
	SceneRouter.goto_main_menu()
```

- [ ] **Step 2: Create the stub scene**

Create `scenes/attract_sequence.tscn`:

```
[gd_scene load_steps=2 format=3 uid="uid://battractseq001"]

[ext_resource type="Script" path="res://scripts/attract_sequence.gd" id="1_attract"]

[node name="AttractSequence" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
script = ExtResource("1_attract")

[node name="Background" type="ColorRect" parent="."]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
color = Color(0, 0, 0, 1)
```

- [ ] **Step 3: Flip main_scene to the new scene**

Open `project.godot`. Find line 14:

```
run/main_scene="res://scenes/main_menu.tscn"
```

Replace with:

```
run/main_scene="res://scenes/attract_sequence.tscn"
```

- [ ] **Step 4: Boot the game and confirm routing**

Manual playtest checklist:
- Game opens. You see a black frame briefly, then it lands on the Main Menu.
- Main Menu buttons still work as before.

If a "uid collision" warning appears for `uid://battractseq001`, change it to a unique value (run `uuidgen` and prefix with `uid://` — Godot will accept any unique string). The placeholder is unlikely to collide but isn't guaranteed unique.

- [ ] **Step 5: Commit**

```bash
git add scenes/attract_sequence.tscn scripts/attract_sequence.gd scripts/attract_sequence.gd.uid project.godot
git commit -m "feat(attract): stub attract_sequence scene routing to main menu"
```

---

## Task 4: Static composite — Title Screen at rest (no animation yet)

Stamp all the sprites for the resting Title Screen composite (per `final_title_desired_result.png`) at their final positions, with `title_main_loop` playing and a `menu_confirm` handler that fades to Main Menu. No animation — this is the rest state that all later phases build toward. Establishes the canonical scene node hierarchy and z-order.

The pennants (`attraction_*_slide_in`) and `attract_punch` are NOT in this composite — they only appear during phases 1–2. Task 7 / Task 8 add them.

**Files:**
- Modify: `scenes/attract_sequence.tscn` (extend with all rest-state sprites)
- Modify: `scripts/attract_sequence.gd` (replace stub with state machine + audio)

- [ ] **Step 1: Replace the controller script**

Open `scripts/attract_sequence.gd`. Replace its entire contents with:

```gdscript
extends Control

# ── Tunable constants ────────────────────────────────────────────────────────
# Audio
const TITLE_INTRO_LENGTH := 11.636  # measured length of title_intro.ogg
const MAIN_MENU_FADE_DURATION := 0.4

# Press-K pulse (CONTEXT.md: opacity 0.3 ↔ 1.0 over ~1.0s, sinusoidal)
const PRESS_K_PERIOD := 1.0
const PRESS_K_FLOOR := 0.3
const PRESS_K_CEILING := 1.0

# SFX hook keys (named constants so the bespoke-SFX follow-up is a one-line edit)
const SFX_CONFIRM := "menu_option_select"
# const SFX_PUNCH_IMPACT := "opponent_punch_body"      # wired in Task 10
# const SFX_PENNANT_FLYOFF := "swing"                  # wired in Task 10
# const SFX_PENNANT_WHOOSH := ""                       # TODO: bespoke clip
# const SFX_TITLE_SLAM := ""                           # TODO: bespoke clip

# ── State ────────────────────────────────────────────────────────────────────
enum Phase { SLIDE_IN, ATTRACT_PUNCH, CAMERA_PAN, TITLE_SLAM, SETTLE_HOLD, PRESS_K_FLASH, FADING_OUT }

var _phase: Phase = Phase.PRESS_K_FLASH
var _press_k_armed := false
var _press_k_tween: Tween = null
var _fade_tween: Tween = null

@onready var _press_k: Label = $PressK
@onready var _fade_overlay: ColorRect = $FadeOverlay

func _ready() -> void:
	AudioBus.play_music("title_main_loop")
	_fade_overlay.color = Color(0, 0, 0, 0)
	_fade_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_start_press_k_pulse()
	_press_k_armed = true

func _unhandled_input(event: InputEvent) -> void:
	if _phase == Phase.FADING_OUT:
		return
	if event.is_action_pressed("menu_confirm") and _press_k_armed:
		_confirm_to_main_menu()

func _start_press_k_pulse() -> void:
	# Sinusoidal opacity pulse: floor → ceiling → floor every PRESS_K_PERIOD.
	_press_k.modulate.a = PRESS_K_FLOOR
	_press_k_tween = create_tween().set_loops()
	_press_k_tween.tween_property(_press_k, "modulate:a", PRESS_K_CEILING, PRESS_K_PERIOD * 0.5).set_trans(Tween.TRANS_SINE)
	_press_k_tween.tween_property(_press_k, "modulate:a", PRESS_K_FLOOR, PRESS_K_PERIOD * 0.5).set_trans(Tween.TRANS_SINE)

func _confirm_to_main_menu() -> void:
	_phase = Phase.FADING_OUT
	AudioBus.play_sfx(SFX_CONFIRM)
	if _press_k_tween and _press_k_tween.is_valid():
		_press_k_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_fade_overlay, "color:a", 1.0, MAIN_MENU_FADE_DURATION)
	_fade_tween.tween_callback(SceneRouter.goto_main_menu)
```

- [ ] **Step 2: Extend the scene file with all rest-state nodes**

Open `scenes/attract_sequence.tscn`. Replace its entire contents with:

```
[gd_scene load_steps=8 format=3 uid="uid://battractseq001"]

[ext_resource type="Script" path="res://scripts/attract_sequence.gd" id="1_attract"]
[ext_resource type="Texture2D" path="res://assets/sprites/title/title_background.png" id="2_bg"]
[ext_resource type="Texture2D" path="res://assets/sprites/title/title_ring.png" id="3_ring"]
[ext_resource type="Texture2D" path="res://assets/sprites/title/title_tofu.png" id="4_tofu"]
[ext_resource type="Texture2D" path="res://assets/sprites/title/title_minty.png" id="5_minty"]
[ext_resource type="Texture2D" path="res://assets/sprites/title/title_sebastian.png" id="6_sebastian"]
[ext_resource type="Texture2D" path="res://assets/sprites/title/title_text.png" id="7_text"]

[node name="AttractSequence" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
script = ExtResource("1_attract")

[node name="Background" type="ColorRect" parent="."]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
color = Color(0, 0, 0, 1)

[node name="TitleBackground" type="TextureRect" parent="."]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
texture = ExtResource("2_bg")
expand_mode = 1
stretch_mode = 6

[node name="TitleSebastian" type="TextureRect" parent="."]
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -160.0
offset_top = -360.0
offset_right = 160.0
offset_bottom = 60.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
texture = ExtResource("6_sebastian")
expand_mode = 1
stretch_mode = 5

[node name="TitleRing" type="TextureRect" parent="."]
layout_mode = 1
anchors_preset = 7
anchor_left = 0.0
anchor_top = 1.0
anchor_right = 1.0
anchor_bottom = 1.0
offset_top = -540.0
grow_horizontal = 2
grow_vertical = 0
mouse_filter = 2
texture = ExtResource("3_ring")
expand_mode = 1
stretch_mode = 6

[node name="TitleMinty" type="TextureRect" parent="."]
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -540.0
offset_top = -200.0
offset_right = -140.0
offset_bottom = 360.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
texture = ExtResource("5_minty")
expand_mode = 1
stretch_mode = 5

[node name="TitleTofu" type="TextureRect" parent="."]
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = 140.0
offset_top = -200.0
offset_right = 540.0
offset_bottom = 360.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
texture = ExtResource("4_tofu")
expand_mode = 1
stretch_mode = 5

[node name="TitleText" type="TextureRect" parent="."]
layout_mode = 1
anchors_preset = 10
anchor_right = 1.0
offset_top = 60.0
offset_bottom = 260.0
grow_horizontal = 2
mouse_filter = 2
texture = ExtResource("7_text")
expand_mode = 1
stretch_mode = 5

[node name="PressK" type="Label" parent="."]
layout_mode = 1
anchors_preset = 7
anchor_left = 0.5
anchor_top = 1.0
anchor_right = 0.5
anchor_bottom = 1.0
offset_left = -200.0
offset_top = -120.0
offset_right = 200.0
offset_bottom = -60.0
grow_horizontal = 2
grow_vertical = 0
horizontal_alignment = 1
vertical_alignment = 1
text = "Press K to Start"

[node name="FadeOverlay" type="ColorRect" parent="."]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
color = Color(0, 0, 0, 0)
```

The offsets are first-pass guesses based on `final_title_desired_result.png`. The user will tune positions during playtest — that's expected per the project's "user is the test harness for visual/feel work" convention.

- [ ] **Step 3: Boot the game and verify the rest state**

Manual playtest checklist:
- Game opens directly to the Title Screen composite: stadium background, ring corners at bottom, Sebastian centered behind, Minty/Tofu in foreground, "LOVE AND BOXING" logo near top.
- "Press K to Start" pulses smoothly between dim and bright at the bottom.
- `title_main_loop.ogg` is playing on a seamless loop.
- Pressing K or Enter fades to black over ~0.4s, then the Main Menu appears.
- A short "menu select" SFX plays on confirm.

If sprite positions are wildly off, tune the `offset_*` values in the scene file — don't block on perfect positioning, the user will fine-tune later.

- [ ] **Step 4: Commit**

```bash
git add scenes/attract_sequence.tscn scripts/attract_sequence.gd
git commit -m "feat(attract): static title screen rest composite + press-k pulse + fade to main menu"
```

---

## Task 5: Title Slam phase + master clock + audio cross-cut

Add the Title Slam (phase 4) on top of the rest state. The scene now starts in phase TITLE_SLAM (not at rest) — `title_text` is pushed off-screen above and scaled up; `title_intro.ogg` plays from t=0; phases 1–3 are skipped (still black filler before the slam) but the audio runs its full 11.636s; at t = 11.0s, `title_text` begins falling into place; at t = 11.636s, the white flash peaks and audio hard-cuts to `title_main_loop`. After Settle Hold (2s) the Press-K Flash begins.

**Files:**
- Modify: `scripts/attract_sequence.gd` (add slam + flash + settle + state machine driver)
- Modify: `scenes/attract_sequence.tscn` (add WhiteFlash ColorRect)

- [ ] **Step 1: Add the WhiteFlash overlay to the scene**

Open `scenes/attract_sequence.tscn`. Just before the `FadeOverlay` node block, insert:

```
[node name="WhiteFlash" type="ColorRect" parent="."]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
color = Color(1, 1, 1, 0)
```

Order matters: WhiteFlash must come AFTER all sprite nodes but BEFORE FadeOverlay, so the flash sits above the composite but below the black fade-out.

- [ ] **Step 2: Expand the controller with phase scheduling**

Open `scripts/attract_sequence.gd`. Replace its entire contents with:

```gdscript
extends Control

# ── Tunable constants ────────────────────────────────────────────────────────
# Audio (master clock = title_intro.ogg measured length)
const TITLE_INTRO_LENGTH := 11.636
const MAIN_MENU_FADE_DURATION := 0.4

# Title Slam (phase 4)
const SLAM_DURATION := 0.636                    # 11.0 → 11.636
const SLAM_START_TIME := TITLE_INTRO_LENGTH - SLAM_DURATION
const SLAM_START_OFFSET_Y := -800.0             # off-screen above
const SLAM_START_SCALE := Vector2(1.3, 1.3)
const FLASH_DECAY := 0.25                       # white → clear

# Settle Hold (phase 5)
const SETTLE_HOLD := 2.0

# Press-K Flash (phase 6)
const PRESS_K_PERIOD := 1.0
const PRESS_K_FLOOR := 0.3
const PRESS_K_CEILING := 1.0

# SFX hook keys
const SFX_CONFIRM := "menu_option_select"
# const SFX_PUNCH_IMPACT := "opponent_punch_body"      # wired in Task 10
# const SFX_PENNANT_FLYOFF := "swing"                  # wired in Task 10
# const SFX_PENNANT_WHOOSH := ""                       # TODO: bespoke clip
# const SFX_TITLE_SLAM := ""                           # TODO: bespoke clip

# ── State ────────────────────────────────────────────────────────────────────
enum Phase { SLIDE_IN, ATTRACT_PUNCH, CAMERA_PAN, TITLE_SLAM, SETTLE_HOLD, PRESS_K_FLASH, FADING_OUT }

var _phase: Phase = Phase.TITLE_SLAM
var _press_k_armed := false
var _press_k_tween: Tween = null
var _fade_tween: Tween = null
var _slam_tween: Tween = null

@onready var _title_text: TextureRect = $TitleText
@onready var _press_k: Label = $PressK
@onready var _white_flash: ColorRect = $WhiteFlash
@onready var _fade_overlay: ColorRect = $FadeOverlay

func _ready() -> void:
	_fade_overlay.color = Color(0, 0, 0, 0)
	_fade_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_white_flash.color = Color(1, 1, 1, 0)
	_white_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_press_k.modulate.a = 0.0  # hidden until phase 6
	_prepare_title_text_offscreen()
	AudioBus.play_music("title_intro")
	_run_sequence()

func _unhandled_input(event: InputEvent) -> void:
	if _phase == Phase.FADING_OUT:
		return
	if event.is_action_pressed("menu_confirm") and _press_k_armed:
		_confirm_to_main_menu()

# ── Phase orchestration ──────────────────────────────────────────────────────

func _run_sequence() -> void:
	# Phases 1–3 are placeholder waits in this task — Tasks 6/7/8 fill them in.
	# Their cumulative duration must equal SLAM_START_TIME.
	await get_tree().create_timer(SLAM_START_TIME).timeout
	await _play_title_slam()
	await _settle_hold()
	_enter_press_k_flash()

func _prepare_title_text_offscreen() -> void:
	_title_text.pivot_offset = _title_text.size * 0.5
	_title_text.position.y += SLAM_START_OFFSET_Y
	_title_text.scale = SLAM_START_SCALE

func _play_title_slam() -> void:
	_phase = Phase.TITLE_SLAM
	var rest_y := _title_text.position.y - SLAM_START_OFFSET_Y
	_slam_tween = create_tween().set_parallel(true)
	_slam_tween.tween_property(_title_text, "position:y", rest_y, SLAM_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_slam_tween.tween_property(_title_text, "scale", Vector2.ONE, SLAM_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await _slam_tween.finished
	# Impact frame: cross-cut music and fire flash simultaneously.
	AudioBus.play_music("title_main_loop")
	_white_flash.color.a = 1.0
	var flash_tween := create_tween()
	flash_tween.tween_property(_white_flash, "color:a", 0.0, FLASH_DECAY).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await flash_tween.finished

func _settle_hold() -> void:
	_phase = Phase.SETTLE_HOLD
	await get_tree().create_timer(SETTLE_HOLD).timeout

func _enter_press_k_flash() -> void:
	_phase = Phase.PRESS_K_FLASH
	_start_press_k_pulse()
	_press_k_armed = true

func _start_press_k_pulse() -> void:
	_press_k.modulate.a = PRESS_K_FLOOR
	_press_k_tween = create_tween().set_loops()
	_press_k_tween.tween_property(_press_k, "modulate:a", PRESS_K_CEILING, PRESS_K_PERIOD * 0.5).set_trans(Tween.TRANS_SINE)
	_press_k_tween.tween_property(_press_k, "modulate:a", PRESS_K_FLOOR, PRESS_K_PERIOD * 0.5).set_trans(Tween.TRANS_SINE)

func _confirm_to_main_menu() -> void:
	_phase = Phase.FADING_OUT
	AudioBus.play_sfx(SFX_CONFIRM)
	if _press_k_tween and _press_k_tween.is_valid():
		_press_k_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_fade_overlay, "color:a", 1.0, MAIN_MENU_FADE_DURATION)
	_fade_tween.tween_callback(SceneRouter.goto_main_menu)
```

- [ ] **Step 3: Boot and verify the slam**

Manual playtest checklist:
- Game opens to the static composite, but `title_text` is missing (it's off-screen above).
- `title_intro.ogg` plays for ~11 seconds. During this window, nothing animates visually (phases 1–3 are still empty).
- At ~t=11.0s, `title_text` falls from above with a slight overshoot bounce and lands in its rest position.
- At ~t=11.636s exactly, a white flash overlays the entire screen and fades to clear over ~0.25s. The audio cross-cuts from `title_intro` to `title_main_loop` at the same frame.
- 2 seconds of held silence (relative to motion) pass on the new music loop.
- Press-K then begins pulsing at the bottom.
- K/Enter fades to Main Menu.

If the slam timing feels off relative to the music, tune `SLAM_DURATION`. If the bounce is too aggressive, swap `TRANS_BACK` for `TRANS_QUART`.

- [ ] **Step 4: Commit**

```bash
git add scenes/attract_sequence.tscn scripts/attract_sequence.gd
git commit -m "feat(attract): title slam phase with white flash + hard audio cross-cut on impact"
```

---

## Task 6: Camera Pan phase (background fades + parallax up)

Add phase 3 in front of the slam. At scene start, the background is invisible (α=0) and the foreground sprites (ring + character stand-ups) are pushed down off their rest positions. During the pan window (6.7s → 11.0s), background fades in while translating up at 1.0× rate; foreground translates up at 1.6× rate, producing parallax. Punch sprite — added in Task 7 — will also fade out during this window. By 11.0s, every layer is in its final rest position, ready for the slam.

**Files:**
- Modify: `scripts/attract_sequence.gd` (add pan phase + parallax setup)

- [ ] **Step 1: Add pan constants and pan phase to the controller**

Open `scripts/attract_sequence.gd`. Insert these constants after the `# Title Slam (phase 4)` block, before `# Settle Hold`:

```gdscript
# Camera Pan (phase 3)
const PAN_DURATION := 4.3                       # 6.7 → 11.0
const PAN_BACKGROUND_RISE := 200.0              # px; background starts this far below rest
const PAN_FOREGROUND_MULTIPLIER := 1.6          # foreground rises this much faster
const PAN_TRANS := Tween.TRANS_SINE
const PAN_EASE := Tween.EASE_OUT
```

Find the SLAM_START_TIME constant and replace it with a computed cumulative offset. Replace:

```gdscript
const SLAM_START_TIME := TITLE_INTRO_LENGTH - SLAM_DURATION
```

With:

```gdscript
# Phase windows (computed from durations — cumulative time-since-scene-start)
const PAN_START_TIME := TITLE_INTRO_LENGTH - SLAM_DURATION - PAN_DURATION   # 6.7
const SLAM_START_TIME := TITLE_INTRO_LENGTH - SLAM_DURATION                  # 11.0
```

Add `@onready` references to the four layers we'll pan. Insert after the existing `@onready` block:

```gdscript
@onready var _title_background: TextureRect = $TitleBackground
@onready var _title_ring: TextureRect = $TitleRing
@onready var _title_tofu: TextureRect = $TitleTofu
@onready var _title_minty: TextureRect = $TitleMinty
@onready var _title_sebastian: TextureRect = $TitleSebastian
```

Add a helper that captures rest positions and pushes each layer to its pre-pan start. Insert it just below `_prepare_title_text_offscreen`:

```gdscript
var _bg_rest_y: float
var _ring_rest_y: float
var _tofu_rest_y: float
var _minty_rest_y: float
var _sebastian_rest_y: float

func _prepare_camera_pan_offscreen() -> void:
	_bg_rest_y = _title_background.position.y
	_ring_rest_y = _title_ring.position.y
	_tofu_rest_y = _title_tofu.position.y
	_minty_rest_y = _title_minty.position.y
	_sebastian_rest_y = _title_sebastian.position.y
	_title_background.position.y = _bg_rest_y + PAN_BACKGROUND_RISE
	_title_background.modulate.a = 0.0
	var fg_rise := PAN_BACKGROUND_RISE * PAN_FOREGROUND_MULTIPLIER
	_title_ring.position.y = _ring_rest_y + fg_rise
	_title_tofu.position.y = _tofu_rest_y + fg_rise
	_title_minty.position.y = _minty_rest_y + fg_rise
	_title_sebastian.position.y = _sebastian_rest_y + fg_rise
```

Add the pan playback function. Insert it just below `_prepare_camera_pan_offscreen`:

```gdscript
func _play_camera_pan() -> void:
	_phase = Phase.CAMERA_PAN
	var pan_tween := create_tween().set_parallel(true)
	pan_tween.tween_property(_title_background, "position:y", _bg_rest_y, PAN_DURATION).set_trans(PAN_TRANS).set_ease(PAN_EASE)
	pan_tween.tween_property(_title_background, "modulate:a", 1.0, PAN_DURATION).set_trans(PAN_TRANS).set_ease(PAN_EASE)
	pan_tween.tween_property(_title_ring, "position:y", _ring_rest_y, PAN_DURATION).set_trans(PAN_TRANS).set_ease(PAN_EASE)
	pan_tween.tween_property(_title_tofu, "position:y", _tofu_rest_y, PAN_DURATION).set_trans(PAN_TRANS).set_ease(PAN_EASE)
	pan_tween.tween_property(_title_minty, "position:y", _minty_rest_y, PAN_DURATION).set_trans(PAN_TRANS).set_ease(PAN_EASE)
	pan_tween.tween_property(_title_sebastian, "position:y", _sebastian_rest_y, PAN_DURATION).set_trans(PAN_TRANS).set_ease(PAN_EASE)
	await pan_tween.finished
```

Call the prep helper from `_ready()` and the playback from `_run_sequence()`. In `_ready`, just before `AudioBus.play_music("title_intro")`, add:

```gdscript
	_prepare_camera_pan_offscreen()
```

In `_run_sequence`, replace:

```gdscript
	# Phases 1–3 are placeholder waits in this task — Tasks 6/7/8 fill them in.
	# Their cumulative duration must equal SLAM_START_TIME.
	await get_tree().create_timer(SLAM_START_TIME).timeout
	await _play_title_slam()
```

With:

```gdscript
	# Phases 1–2 are placeholder waits in this task — Tasks 7/8 fill them in.
	# Their cumulative duration must equal PAN_START_TIME.
	await get_tree().create_timer(PAN_START_TIME).timeout
	await _play_camera_pan()
	await _play_title_slam()
```

- [ ] **Step 2: Boot and verify the pan**

Manual playtest checklist:
- Game opens to a near-black screen (only the not-yet-faded-in background is at α=0; the foreground sprites are pushed down off-screen).
- For ~6.7 seconds: nothing visible (phases 1–2 still empty).
- At ~t=6.7s, the background begins fading in while gliding up; ring + characters glide up faster, producing a depth parallax read.
- By ~t=11.0s, everything is in its final rest position.
- The slam fires immediately after.
- Everything else (settle, press-K, K-confirm fade) still works as in Task 5.

If parallax feels too aggressive, lower `PAN_FOREGROUND_MULTIPLIER`. If the rise feels too short, raise `PAN_BACKGROUND_RISE`. Phase 1–2 still being dark is expected; Task 7 + 8 fill them in.

- [ ] **Step 3: Commit**

```bash
git add scripts/attract_sequence.gd
git commit -m "feat(attract): camera pan phase with parallax background fade and rise"
```

---

## Task 7: Attract Punch + pennant fly-off (phase 2)

Add the Attract Punch and pennant fly-off. At scene start, the three pennants are stamped in their final composite arrangement (the rest of phase 1's destination), and `attract_punch` is parented BEHIND them (lower index in the parent's child list), invisible because the pennants overlap it. During phase 2 (5.1s → 6.7s), the punch grows from rest scale to 1.6× (revealing itself as the pennants begin their fly-off), the three pennants spin and fly off in their assigned directions, and the punch shrinks back to 1.0× as it begins fading out. By 6.7s the pennants are off-screen and the punch is half-faded — the camera pan begins, fading the punch to 0.

**Files:**
- Modify: `scenes/attract_sequence.tscn` (add pennant + punch nodes)
- Modify: `scripts/attract_sequence.gd` (add punch + fly-off phase)

- [ ] **Step 1: Add pennant + punch nodes to the scene**

Open `scenes/attract_sequence.tscn`. Add three ext_resources just after the existing `7_text` line:

```
[ext_resource type="Texture2D" path="res://assets/sprites/title/attract_punch.png" id="8_punch"]
[ext_resource type="Texture2D" path="res://assets/sprites/title/attraction_tofu_slide_in.png" id="9_pennant_tofu"]
[ext_resource type="Texture2D" path="res://assets/sprites/title/attraction_minty_slide_in.png" id="10_pennant_minty"]
[ext_resource type="Texture2D" path="res://assets/sprites/title/attraction_sebastian_slide_in.png" id="11_pennant_sebastian"]
```

Bump `load_steps` on line 1 from `8` to `12`.

Insert these nodes between `TitleText` and `PressK` blocks. Order matters: `AttractPunch` MUST come before the three pennants (lower z-order — placed behind):

```
[node name="AttractPunch" type="TextureRect" parent="."]
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -300.0
offset_top = -300.0
offset_right = 300.0
offset_bottom = 300.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
texture = ExtResource("8_punch")
expand_mode = 1
stretch_mode = 5
pivot_offset = Vector2(300, 300)

[node name="PennantTofu" type="TextureRect" parent="."]
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -540.0
offset_top = -360.0
offset_right = -140.0
offset_bottom = 40.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
texture = ExtResource("9_pennant_tofu")
expand_mode = 1
stretch_mode = 5
pivot_offset = Vector2(200, 200)

[node name="PennantMinty" type="TextureRect" parent="."]
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = 140.0
offset_top = -360.0
offset_right = 540.0
offset_bottom = 40.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
texture = ExtResource("10_pennant_minty")
expand_mode = 1
stretch_mode = 5
pivot_offset = Vector2(200, 200)

[node name="PennantSebastian" type="TextureRect" parent="."]
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -200.0
offset_top = 40.0
offset_right = 200.0
offset_bottom = 440.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
texture = ExtResource("11_pennant_sebastian")
expand_mode = 1
stretch_mode = 5
pivot_offset = Vector2(200, 200)
```

Pennant positions are first-pass guesses approximating `attract_desired_result.png`. User will fine-tune.

- [ ] **Step 2: Add punch + fly-off constants and phase**

Open `scripts/attract_sequence.gd`. Insert these constants after the `# Camera Pan (phase 3)` block, before `# Title Slam (phase 4)`:

```gdscript
# Attract Punch (phase 2)
const PUNCH_DURATION := 1.6                     # 5.1 → 6.7
const PUNCH_GROW_DURATION := 0.5                # punch wind-up before pennants fly
const PUNCH_PEAK_SCALE := Vector2(1.6, 1.6)
const PUNCH_REST_SCALE := Vector2(1.0, 1.0)
const PUNCH_FADE_OVERLAP := 0.6                 # fades to 0 during early camera pan
const FLY_OFF_DURATION := 1.1                   # 5.6 → 6.7 (after grow start at +0.5)
const FLY_OFF_DISTANCE := 1400.0                # px; how far each pennant travels
const FLY_OFF_SPIN_DEGREES := 180.0
```

Update `PAN_START_TIME` block — replace the existing comment-and-const block with:

```gdscript
# Phase windows (cumulative time-since-scene-start)
const PUNCH_START_TIME := TITLE_INTRO_LENGTH - SLAM_DURATION - PAN_DURATION - PUNCH_DURATION  # 5.1
const PAN_START_TIME := TITLE_INTRO_LENGTH - SLAM_DURATION - PAN_DURATION                     # 6.7
const SLAM_START_TIME := TITLE_INTRO_LENGTH - SLAM_DURATION                                    # 11.0
```

Add `@onready` references for the new nodes. Append to the existing `@onready` block:

```gdscript
@onready var _attract_punch: TextureRect = $AttractPunch
@onready var _pennant_tofu: TextureRect = $PennantTofu
@onready var _pennant_minty: TextureRect = $PennantMinty
@onready var _pennant_sebastian: TextureRect = $PennantSebastian
```

Add a prep helper for the punch. Insert just below `_prepare_camera_pan_offscreen`:

```gdscript
func _prepare_attract_punch() -> void:
	_attract_punch.scale = PUNCH_REST_SCALE
	_attract_punch.modulate.a = 1.0
	_attract_punch.pivot_offset = _attract_punch.size * 0.5
	for pennant in [_pennant_tofu, _pennant_minty, _pennant_sebastian]:
		pennant.pivot_offset = pennant.size * 0.5
```

Add the phase 2 playback function. Insert just below `_prepare_attract_punch`:

```gdscript
func _play_attract_punch() -> void:
	_phase = Phase.ATTRACT_PUNCH
	# Wind-up: punch grows from behind the pennant composite.
	var grow_tween := create_tween()
	grow_tween.tween_property(_attract_punch, "scale", PUNCH_PEAK_SCALE, PUNCH_GROW_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await grow_tween.finished
	# Impact: pennants begin spin + fly-off; punch starts shrinking back.
	var fly_tween := create_tween().set_parallel(true)
	fly_tween.tween_property(_attract_punch, "scale", PUNCH_REST_SCALE, FLY_OFF_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	_schedule_pennant_flyoff(fly_tween, _pennant_tofu, Vector2(-1.0, -0.6).normalized(), -FLY_OFF_SPIN_DEGREES)
	_schedule_pennant_flyoff(fly_tween, _pennant_minty, Vector2(1.0, -0.6).normalized(), FLY_OFF_SPIN_DEGREES)
	_schedule_pennant_flyoff(fly_tween, _pennant_sebastian, Vector2(0.0, 1.0).normalized(), FLY_OFF_SPIN_DEGREES)
	await fly_tween.finished

func _schedule_pennant_flyoff(tween: Tween, pennant: TextureRect, direction: Vector2, spin_degrees: float) -> void:
	var target_position := pennant.position + direction * FLY_OFF_DISTANCE
	tween.tween_property(pennant, "position", target_position, FLY_OFF_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(pennant, "rotation_degrees", spin_degrees, FLY_OFF_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
```

Add a punch fade-out helper. The punch must fade to 0 during the early camera pan so it doesn't sit visibly behind the rising background. Insert just below `_schedule_pennant_flyoff`:

```gdscript
func _start_punch_fadeout() -> void:
	var fade := create_tween()
	fade.tween_property(_attract_punch, "modulate:a", 0.0, PUNCH_FADE_OVERLAP).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
```

Wire the prep call and the phase call. In `_ready`, just before `AudioBus.play_music("title_intro")`, add:

```gdscript
	_prepare_attract_punch()
```

In `_run_sequence`, replace:

```gdscript
	# Phases 1–2 are placeholder waits in this task — Tasks 7/8 fill them in.
	# Their cumulative duration must equal PAN_START_TIME.
	await get_tree().create_timer(PAN_START_TIME).timeout
	await _play_camera_pan()
```

With:

```gdscript
	# Phase 1 (Slide-In) is still placeholder in this task — Task 8 fills it in.
	# Its duration must equal PUNCH_START_TIME.
	await get_tree().create_timer(PUNCH_START_TIME).timeout
	await _play_attract_punch()
	_start_punch_fadeout()
	await _play_camera_pan()
```

(The punch fade-out runs in parallel with the camera pan — that's intentional; not awaited.)

- [ ] **Step 3: Boot and verify**

Manual playtest checklist:
- Game opens with three pennants stamped in a triangular arrangement (Tofu top-left, Minty top-right, Sebastian bottom). Background still hidden (foreground positions are pinned to rest until pan).
- For ~5.1 seconds: pennants sit there static (phase 1 still placeholder).
- At ~t=5.1s, `attract_punch` grows from behind the pennants (~0.5s wind-up).
- At ~t=5.6s, pennants begin flying off — Tofu up-left + CCW spin, Minty up-right + CW spin, Sebastian down + CW spin. Punch starts shrinking back.
- By ~t=6.7s, pennants are off-screen, punch is back at rest scale and beginning to fade out.
- Camera pan starts at t=6.7s (punch continues fading to invisible over the first ~0.6s).
- Title slam + flash + audio cross-cut fire at the right times.
- Press-K + K-confirm work.

If pennants overlap the punch sprite incorrectly during wind-up, check that `AttractPunch` is BEFORE the pennants in the scene file (lower index = drawn first = behind).

- [ ] **Step 4: Commit**

```bash
git add scenes/attract_sequence.tscn scripts/attract_sequence.gd
git commit -m "feat(attract): attract punch + pennant fly-off phase with spin and fade"
```

---

## Task 8: Slide-In phase (Tofu → Minty → Sebastian, strict sequential)

Add phase 1 in front of the punch. At scene start, the three pennants are pushed off-screen (each toward the edge closest to its rest position). Phase 1 (0 → 5.1s) slides them in one at a time, strict sequential — Tofu first, fully home, then Minty, then Sebastian — each with `TRANS_BACK / EASE_OUT` for a subtle overshoot. By 5.1s all three are at their rest positions; phase 2 (Attract Punch) takes over.

**Files:**
- Modify: `scripts/attract_sequence.gd` (add slide-in prep + phase)

- [ ] **Step 1: Add slide-in constants and phase**

Open `scripts/attract_sequence.gd`. Insert these constants after the `# Attract Punch (phase 2)` block, before `# Camera Pan (phase 3)`:

```gdscript
# Slide-In (phase 1) — strict sequential: Tofu → Minty → Sebastian
const SLIDE_IN_PER_CHARACTER := 1.7             # 1.7s × 3 = 5.1 total
const SLIDE_IN_DISTANCE := 1400.0               # px; off-screen start offset
const SLIDE_IN_TRANS := Tween.TRANS_BACK
const SLIDE_IN_EASE := Tween.EASE_OUT
```

Update the phase-window block. Replace:

```gdscript
# Phase windows (cumulative time-since-scene-start)
const PUNCH_START_TIME := TITLE_INTRO_LENGTH - SLAM_DURATION - PAN_DURATION - PUNCH_DURATION  # 5.1
const PAN_START_TIME := TITLE_INTRO_LENGTH - SLAM_DURATION - PAN_DURATION                     # 6.7
const SLAM_START_TIME := TITLE_INTRO_LENGTH - SLAM_DURATION                                    # 11.0
```

With:

```gdscript
# Phase windows (cumulative time-since-scene-start)
const SLIDE_IN_TOTAL := SLIDE_IN_PER_CHARACTER * 3.0                                          # 5.1
const PUNCH_START_TIME := SLIDE_IN_TOTAL                                                       # 5.1
const PAN_START_TIME := PUNCH_START_TIME + PUNCH_DURATION                                      # 6.7
const SLAM_START_TIME := TITLE_INTRO_LENGTH - SLAM_DURATION                                    # 11.0
# Invariant: PAN_START_TIME + PAN_DURATION == SLAM_START_TIME (asserted in _ready).
```

Add an invariant assertion in `_ready`. Insert just after the existing `_fade_overlay.color = Color(0, 0, 0, 0)` line:

```gdscript
	assert(is_equal_approx(PAN_START_TIME + PAN_DURATION, SLAM_START_TIME),
		"Phase budget invariant: pan must end exactly when slam starts")
```

Add a slide-in prep helper. Insert just below `_prepare_attract_punch`:

```gdscript
var _pennant_rest_positions := {}

func _prepare_slide_in_offscreen() -> void:
	# Each pennant starts off-screen toward the edge closest to its rest position.
	# Tofu (left) → from left, Minty (right) → from right, Sebastian (bottom) → from bottom.
	_pennant_rest_positions[_pennant_tofu] = _pennant_tofu.position
	_pennant_rest_positions[_pennant_minty] = _pennant_minty.position
	_pennant_rest_positions[_pennant_sebastian] = _pennant_sebastian.position
	_pennant_tofu.position.x -= SLIDE_IN_DISTANCE
	_pennant_minty.position.x += SLIDE_IN_DISTANCE
	_pennant_sebastian.position.y += SLIDE_IN_DISTANCE
```

Add the phase 1 playback function. Insert just below `_prepare_slide_in_offscreen`:

```gdscript
func _play_slide_in() -> void:
	_phase = Phase.SLIDE_IN
	# TODO play_sfx(SFX_PENNANT_WHOOSH) once authored — three calls, one per slide-in start.
	await _slide_pennant(_pennant_tofu)
	await _slide_pennant(_pennant_minty)
	await _slide_pennant(_pennant_sebastian)

func _slide_pennant(pennant: TextureRect) -> void:
	var rest_position: Vector2 = _pennant_rest_positions[pennant]
	var tween := create_tween()
	tween.tween_property(pennant, "position", rest_position, SLIDE_IN_PER_CHARACTER).set_trans(SLIDE_IN_TRANS).set_ease(SLIDE_IN_EASE)
	await tween.finished
```

Wire the prep + playback. In `_ready`, just before `AudioBus.play_music("title_intro")`, add:

```gdscript
	_prepare_slide_in_offscreen()
```

In `_run_sequence`, replace:

```gdscript
	# Phase 1 (Slide-In) is still placeholder in this task — Task 8 fills it in.
	# Its duration must equal PUNCH_START_TIME.
	await get_tree().create_timer(PUNCH_START_TIME).timeout
	await _play_attract_punch()
```

With:

```gdscript
	await _play_slide_in()
	await _play_attract_punch()
```

- [ ] **Step 2: Boot and verify the full sequence**

Manual playtest checklist:
- Game opens, screen is mostly black (pennants are off-screen, foreground sprites pushed down, background invisible).
- `title_intro.ogg` starts playing.
- At ~t=0, Tofu pennant slides in from the left with a slight overshoot, landing in its rest position.
- At ~t=1.7, Minty slides in from the right.
- At ~t=3.4, Sebastian slides in from the bottom.
- At ~t=5.1, the attract punch begins growing from behind the composite.
- At ~t=5.6, pennants fly off with spin; punch shrinks back.
- At ~t=6.7, camera pan begins; background fades in, parallax up.
- At ~t=11.0, title slams in.
- At ~t=11.636, white flash + audio cross-cut to title_main_loop.
- 2s settle.
- Press-K pulses; K/Enter fades to Main Menu.

This is the full sequence end-to-end. Sit with it and note any phase that feels rushed, sluggish, or mistimed against the music — the constants block is the tuning surface.

- [ ] **Step 3: Commit**

```bash
git add scripts/attract_sequence.gd
git commit -m "feat(attract): slide-in phase — three pennants sequentially overshoot into composite"
```

---

## Task 9: Skip behavior (menu_confirm during animated phases)

Wire the K/Enter skip contract per the grilling spec. During phases 1–4, `menu_confirm` snaps every element to its final composited state, kills `title_intro`, hard-starts `title_main_loop` from t=0, and jumps directly to phase 5 entry. During phase 5 (Settle Hold), it fast-forwards to phase 6. Phase 6 already handles confirm-to-Main-Menu from Task 4.

**Files:**
- Modify: `scripts/attract_sequence.gd` (extend input handler + add skip helper)

- [ ] **Step 1: Track active tweens and the sequence loop**

Open `scripts/attract_sequence.gd`. Add an array to track all in-flight sequence tweens so the skip can kill them cleanly. Add this after the existing `var _slam_tween: Tween = null` line:

```gdscript
var _settle_timer: SceneTreeTimer = null
var _phase_wait_timer: SceneTreeTimer = null
var _skip_requested := false
```

- [ ] **Step 2: Replace `_unhandled_input` and add the skip handler**

Replace the existing `_unhandled_input` function with:

```gdscript
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("menu_confirm"):
		return
	match _phase:
		Phase.FADING_OUT:
			return
		Phase.PRESS_K_FLASH:
			if _press_k_armed:
				_confirm_to_main_menu()
		Phase.SETTLE_HOLD:
			_fast_forward_settle()
		Phase.SLIDE_IN, Phase.ATTRACT_PUNCH, Phase.CAMERA_PAN, Phase.TITLE_SLAM:
			_skip_to_rest()
```

Add the skip + fast-forward helpers. Insert just below `_confirm_to_main_menu`:

```gdscript
func _skip_to_rest() -> void:
	# Snap every animated element to its rest state; cross-cut audio to the main loop;
	# enter phase 5 entry. Phase 5 still holds for its full SETTLE_HOLD duration.
	_skip_requested = true
	_kill_sequence_tweens()
	# Pennants: hide them (they would have flown off by now in the natural flow).
	for pennant in [_pennant_tofu, _pennant_minty, _pennant_sebastian]:
		pennant.modulate.a = 0.0
	# Punch: hidden.
	_attract_punch.modulate.a = 0.0
	# Camera pan endpoints: every layer to rest.
	_title_background.modulate.a = 1.0
	_title_background.position.y = _bg_rest_y
	_title_ring.position.y = _ring_rest_y
	_title_tofu.position.y = _tofu_rest_y
	_title_minty.position.y = _minty_rest_y
	_title_sebastian.position.y = _sebastian_rest_y
	# Title slam endpoint.
	_title_text.position.y -= SLAM_START_OFFSET_Y if _title_text.position.y < 0 else 0.0
	_title_text.scale = Vector2.ONE
	# White flash: brief decay starting now.
	_white_flash.color.a = 1.0
	var flash_tween := create_tween()
	flash_tween.tween_property(_white_flash, "color:a", 0.0, FLASH_DECAY).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# Audio: hard-start the main loop from t=0.
	AudioBus.play_music("title_main_loop")
	# Resume into settle hold from this point.
	_run_post_skip()

func _fast_forward_settle() -> void:
	# Cut the settle hold short and jump straight into phase 6.
	if _settle_timer:
		# Force the timer to expire immediately by emitting timeout via 0-delay timer.
		# (SceneTreeTimer has no kill API; we replace its effect by entering phase 6 now.)
		_settle_timer = null
	_skip_requested = true
	# _run_sequence is awaiting the settle timer; setting _skip_requested signals it to
	# break out of the wait. As a belt-and-suspenders we also directly enter phase 6:
	_enter_press_k_flash()

func _run_post_skip() -> void:
	_phase = Phase.SETTLE_HOLD
	await _wait_with_skip(SETTLE_HOLD)
	if _phase != Phase.PRESS_K_FLASH:  # only enter if fast-forward didn't already
		_enter_press_k_flash()

func _kill_sequence_tweens() -> void:
	# Kill every active tween created on this node. _press_k_tween is left alone —
	# it only starts in phase 6 (post-skip) and the skip path doesn't touch it.
	for tween in get_tree().get_processed_tweens():
		if tween.is_valid():
			tween.kill()
```

- [ ] **Step 3: Make the sequence loop respect `_skip_requested`**

Replace `_run_sequence` and add `_wait_with_skip`:

```gdscript
func _run_sequence() -> void:
	if await _wait_with_skip_during_phase(_play_slide_in): return
	if await _wait_with_skip_during_phase(_play_attract_punch): return
	_start_punch_fadeout()
	if await _wait_with_skip_during_phase(_play_camera_pan): return
	if await _wait_with_skip_during_phase(_play_title_slam): return
	await _settle_hold_skippable()
	if _phase != Phase.PRESS_K_FLASH:
		_enter_press_k_flash()

func _wait_with_skip_during_phase(phase_func: Callable) -> bool:
	# Runs the phase function; returns true if skip was requested while it ran.
	await phase_func.call()
	return _skip_requested

func _settle_hold_skippable() -> void:
	_phase = Phase.SETTLE_HOLD
	await _wait_with_skip(SETTLE_HOLD)

func _wait_with_skip(seconds: float) -> void:
	_settle_timer = get_tree().create_timer(seconds)
	await _settle_timer.timeout
	_settle_timer = null
```

Note: the skip from phase 1–4 calls `_run_post_skip()` which kicks off its own settle wait — that's why `_run_sequence` checks `_skip_requested` after each phase and returns early. Two flows, one terminal state.

- [ ] **Step 4: Boot and exercise the skip contract**

Manual playtest checklist:
- Cold boot, press K during Tofu slide-in (within first 1.7s): everything snaps to rest, brief white flash decays, `title_main_loop` starts from t=0, 2s settle, Press-K appears, K → Main Menu.
- Cold boot, press K during the camera pan (~8s): same skip behavior.
- Cold boot, let the sequence run naturally past the slam, press K during the 2s settle: Press-K appears immediately, then K → Main Menu (a second K press is needed).
- Cold boot, let it run naturally, press K after Press-K appears: normal fade-to-Main-Menu.

If skip-during-slam looks janky because the slam tween was mid-flight, fine-tune `_skip_to_rest` to skip the flash if `_phase == Phase.TITLE_SLAM` and the slam has already landed (the music cross-cut already fired). Defer that polish to playtest unless it's obviously broken.

- [ ] **Step 5: Commit**

```bash
git add scripts/attract_sequence.gd
git commit -m "feat(attract): skip contract — menu_confirm skips to rest / fast-forwards settle"
```

---

## Task 10: SFX hook wiring (final pass)

Wire the three SFX call sites approved during grilling. The two TODO placeholders (pennant whoosh, title slam) stay as comments — those need bespoke clips per the saved follow-up memory.

**Files:**
- Modify: `scripts/attract_sequence.gd` (uncomment the two SFX constants + add three call sites)

- [ ] **Step 1: Uncomment the SFX constants**

Open `scripts/attract_sequence.gd`. Replace the commented SFX block:

```gdscript
# SFX hook keys
const SFX_CONFIRM := "menu_option_select"
# const SFX_PUNCH_IMPACT := "opponent_punch_body"      # wired in Task 10
# const SFX_PENNANT_FLYOFF := "swing"                  # wired in Task 10
# const SFX_PENNANT_WHOOSH := ""                       # TODO: bespoke clip
# const SFX_TITLE_SLAM := ""                           # TODO: bespoke clip
```

With:

```gdscript
# SFX hook keys (named so the bespoke-SFX follow-up is a one-line edit per key).
const SFX_CONFIRM := "menu_option_select"
const SFX_PUNCH_IMPACT := "opponent_punch_body"
const SFX_PENNANT_FLYOFF := "swing"
# TODO bespoke clips (planned follow-up — see memory project_attract_sequence_sfx_followup):
#   const SFX_PENNANT_WHOOSH := "attract_pennant_whoosh"  # one per slide-in start, 3 calls
#   const SFX_TITLE_SLAM := "title_slam"                  # at slam impact frame
```

- [ ] **Step 2: Add the call sites**

In `_play_attract_punch`, just after the `await grow_tween.finished` line (impact moment — the punch peaked, pennants are about to fly), add:

```gdscript
	AudioBus.play_sfx(SFX_PUNCH_IMPACT)
	AudioBus.play_sfx(SFX_PENNANT_FLYOFF)
```

In `_play_title_slam`, just after the `await _slam_tween.finished` line (impact frame), add the TODO comment:

```gdscript
	# TODO: AudioBus.play_sfx(SFX_TITLE_SLAM) once a bespoke title slam clip is authored.
```

In `_play_slide_in`, replace the existing single-line TODO comment with three call sites (still TODO until the bespoke clip is authored — leave them commented so the structure is visible):

```gdscript
func _play_slide_in() -> void:
	_phase = Phase.SLIDE_IN
	# TODO: AudioBus.play_sfx(SFX_PENNANT_WHOOSH) at each slide_pennant() start once a bespoke clip is authored.
	await _slide_pennant(_pennant_tofu)
	await _slide_pennant(_pennant_minty)
	await _slide_pennant(_pennant_sebastian)
```

- [ ] **Step 3: Boot and verify SFX**

Manual playtest checklist:
- Cold boot, listen for: at ~t=5.6s, an `opponent_punch_body` thud + a `swing` whoosh stack on the punch impact (slight overlap is expected — they're a deliberate combat-style stack per CONTEXT.md).
- K-confirm at the end still plays `menu_option_select`.
- No SFX during slide-in (TODO placeholders not yet wired).
- No SFX at the title slam impact (TODO placeholder not yet wired).

If the punch SFX stack feels too thin without the slam hit, that's expected — the slam clip is a planned follow-up. Don't substitute another existing SFX as a shim; the user wants it bespoke.

- [ ] **Step 4: Commit**

```bash
git add scripts/attract_sequence.gd
git commit -m "feat(attract): wire SFX hooks — punch impact, pennant flyoff, menu confirm"
```

---

## Task 11: End-to-end review + tuning pass

Final playtest pass. Everything is wired. The user is the test harness for visual/feel work — sit with the full sequence multiple times and note anything that feels off. Adjustments are constant tweaks in `scripts/attract_sequence.gd`, no structural changes expected.

- [ ] **Step 1: Watch the full sequence three times back-to-back**

Cold-boot, watch end-to-end. Repeat twice more. For each run, watch one specific dimension:
- Run 1: motion + composition. Do positions read right? Is the parallax believable? Does the slam land?
- Run 2: audio sync. Does the flash hit the cross-cut on the same frame? Does the punch SFX land with the visual impact?
- Run 3: pacing. Any phase feel rushed or sluggish?

- [ ] **Step 2: Exercise the skip contract**

For each of these inputs, confirm the right thing happens:

| Test | Expected |
|---|---|
| K during Tofu slide-in | Snap to rest, settle hold, then Press-K |
| K during attract punch wind-up | Snap to rest, settle hold, then Press-K |
| K during attract punch fly-off | Snap to rest, settle hold, then Press-K |
| K during camera pan | Snap to rest, settle hold, then Press-K |
| K during title slam fall | Snap to rest, settle hold, then Press-K |
| K during white flash decay (1ms window — best-effort) | Already in settle hold, behavior should be: fast-forward |
| K during 2s settle | Press-K appears immediately |
| K after Press-K is visible | Fade to Main Menu |
| Enter (instead of K) at any point | Same behavior as K (menu_confirm covers both) |

- [ ] **Step 3: Adjust constants based on notes**

The tuning surface is the constants block at the top of `scripts/attract_sequence.gd`. Common adjustments:
- `SLIDE_IN_PER_CHARACTER` — if slide-in feels sluggish or rushed.
- `PAN_FOREGROUND_MULTIPLIER` / `PAN_BACKGROUND_RISE` — parallax depth feel.
- `PUNCH_PEAK_SCALE` — punch hugeness.
- `FLY_OFF_DISTANCE` / `FLY_OFF_SPIN_DEGREES` — pennant exit energy.
- `SLAM_START_OFFSET_Y` / `SLAM_START_SCALE` — slam impact strength.
- `FLASH_DECAY` — flash duration.
- `PRESS_K_PERIOD` / `PRESS_K_FLOOR` — pulse feel.

Critically: if you adjust `SLIDE_IN_PER_CHARACTER`, `PUNCH_DURATION`, or `PAN_DURATION`, the `SLAM_START_TIME` invariant must still hold — phases 1+2+3+slam must equal `TITLE_INTRO_LENGTH`. The `assert` in `_ready` will catch a violation at runtime; check it.

- [ ] **Step 4: Commit any tuning changes**

```bash
git add scripts/attract_sequence.gd
git commit -m "tune(attract): playtest tuning pass — <summary of what was tuned>"
```

(Multiple tuning commits over the playtest cycle are fine and expected, per the project's UI-animation iteration pattern.)

---

## Self-Review Checklist

After implementing all tasks, verify against the grilling-confirmed spec:

- [ ] CONTEXT.md "Screens" section covers Attract Sequence, Title Screen, Main Menu — verified at top of plan.
- [ ] `scenes/title_screen.tscn` is renamed to `main_menu.tscn`; no references to the old name anywhere — Task 1.
- [ ] `SceneRouter.goto_title()` renamed to `goto_main_menu()`; `goto_attract_sequence()` added — Task 1.
- [ ] `project.godot` `main_scene` points at `attract_sequence.tscn` — Task 3.
- [ ] `AudioBus.MUSIC_TRACKS` includes `title_intro` and `title_main_loop` — Task 2.
- [ ] Six phases implemented in `scripts/attract_sequence.gd`: Slide-In (T8), Attract Punch (T7), Camera Pan (T6), Title Slam (T5), Settle Hold (T5), Press-K Flash (T4) — covered.
- [ ] Pennants enter sequentially (Tofu → Minty → Sebastian) — T8.
- [ ] `attract_punch` parented behind pennants (lower index in tscn) — T7 Step 1 + checklist.
- [ ] Phase 1–4 cumulative duration equals `TITLE_INTRO_LENGTH` (asserted in `_ready`) — T8.
- [ ] White flash + audio cross-cut land on the same frame — T5.
- [ ] No crossfade; hard cut on flash — T5 (`play_music("title_main_loop")` with default 0s crossfade).
- [ ] `menu_confirm` handled per phase: skip-to-rest (1–4), fast-forward (5), confirm (6) — T9.
- [ ] SFX wired: punch impact, pennant flyoff, menu confirm — T10.
- [ ] SFX TODO placeholders for pennant whoosh + title slam visible as comments — T10.
- [ ] Press-K pulse: opacity 0.3 ↔ 1.0, period 1.0s, sinusoidal — T4 / T5.
- [ ] Main Menu fade: 0.4s, black overlay — T4.
- [ ] No new tests beyond `test_audio_bus_title_tracks.gd` (visual phases are manually playtested per project convention) — T2.
