# Love and Boxing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Godot 4.6 boxing-meets-dating game where the player defends via a Simon-style memory game while concurrently answering personality riddles to break the opponent's guard, then attacks with combo-escalating sequences until three knockdowns secure a KO.

**Architecture:** Pure-logic game systems (Simon sequence, combo state, match clock, dialogue deck, hearts, knockdowns) live in `scripts/game/` as plain `Resource` or `RefCounted` classes with full GUT test coverage. Scene composition lives in `scenes/`. State coordination flows through four autoload singletons (`Globals`, `SaveData`, `AudioBus`, `SceneRouter`). The Gameplay scene composes the HUD, the player gloves, and the opponent rig, and delegates rule decisions to the pure-logic classes via signals. Difficulty and dialogue data live as `.tres` resources per opponent so content is editable without code changes.

**Tech Stack:** Godot 4.6 (GL Compatibility renderer), GDScript, GUT 9.x for unit testing, ConfigFile for save persistence.

**Iterative Test Strategy:** Each milestone ends with a clearly defined manual test the user performs in the running game *and* a green GUT suite. Milestones are ordered so every increment is playable: scaffolding → menu shell → save → HUD shell → timer → sprites → defense show phase → defense repeat phase + damage → dialogue → attack phase → round transitions → damage FX → difficulty tiers → final polish. Each milestone has its own commit.

**Source of truth for terminology and asset names:** `CONTEXT.md` at project root. If a term in this plan disagrees with `CONTEXT.md`, `CONTEXT.md` wins.

---

## Project Folder Structure

The plan creates this structure incrementally. Reference, not a task in itself:

```
res://
  addons/gut/                       # GUT plugin (installed in Milestone 0)
  assets/
    sprites/
      player/                       # player_glove_*.png
      opponents/
        tofu/                       # opponent_tofu_*.png
        minty/                      # opponent_minty_*.png
        sebastian/                  # opponent_sebastian_*.png
      ui/                           # hearts, combo, knockdown, prompts, boxes
      banners/                      # banner_*.png
      bg/                           # bg_ring.png
    audio/
      sfx/                          # placeholder dir
      music/                        # placeholder dir
  data/
    dialogue/
      tofu.tres
      minty.tres
      sebastian.tres
    difficulty/
      tofu.tres
      minty.tres
      sebastian.tres
  scenes/
    title_screen.tscn
    level_select.tscn
    gameplay.tscn
    match_results.tscn
    ui/
      heart_row.tscn
      combo_meter.tscn
      knockdown_meter.tscn
      match_timer.tscn
      riddle_box.tscn
      answer_card.tscn
      announcement_banner.tscn
      wasd_prompt.tscn
    actors/
      player_gloves.tscn
      opponent.tscn
  scripts/
    autoload/
      globals.gd
      save_data.gd
      audio_bus.gd
      scene_router.gd
    game/
      simon_sequence.gd
      combo_state.gd
      match_clock.gd
      hearts.gd
      knockdowns.gd
      dialogue_deck.gd
      dialogue_prompt.gd
      dialogue_answer.gd
      difficulty_config.gd
      outcome.gd
    ui/
      heart_row.gd
      combo_meter.gd
      ...
    actors/
      player_gloves.gd
      opponent.gd
  tests/
    unit/
      test_simon_sequence.gd
      test_combo_state.gd
      test_match_clock.gd
      test_hearts.gd
      test_knockdowns.gd
      test_dialogue_deck.gd
      test_difficulty_config.gd
```

---

## Milestone 0: Project Scaffolding and GUT Setup

**Goal:** Stand up GUT so unit tests can be written, configure project resolution, and produce a green sanity test.

**Manual test for this milestone:**
- Run the game (F5 in Godot). It opens a window at 1280×720 with a blank scene — no errors in the console.
- Open the GUT panel (Project → Tools → GUT or bottom dock). Click "Run All". One test passes green.

### Task 0.1: Configure project settings

**Files:**
- Modify: `project.godot`

- [ ] **Step 1: Update `project.godot` to set base resolution, stretch mode, and window default**

Open `project.godot` and ensure these sections exist (merge with existing entries):

```ini
[application]

config/name="LoveAndBoxing"
config/features=PackedStringArray("4.6", "GL Compatibility")
config/icon="res://icon.svg"
run/main_scene="res://scenes/title_screen.tscn"

[display]

window/size/viewport_width=1920
window/size/viewport_height=1080
window/size/window_width_override=1280
window/size/window_height_override=720
window/size/resizable=true
window/stretch/mode="canvas_items"
window/stretch/aspect="keep"

[input]

ui_left={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":74,"physical_keycode":0,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
ui_right={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":76,"physical_keycode":0,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
```

Note: We're configuring input actions through the editor in Step 2 — the snippet above is illustrative. Use the editor for actual mapping.

- [ ] **Step 2: Add Input Actions via the Godot editor**

In Project Settings → Input Map, add these actions and bindings:
- `attack_head` → W
- `attack_left` → A
- `attack_body` → S
- `attack_right` → D
- `menu_up` → I (also Up arrow)
- `menu_left` → J (also Left arrow)
- `menu_right` → L (also Right arrow)
- `menu_confirm` → K (also Enter)

These actions are referenced throughout the plan. Note: `attack_left` = left hook (A key), `attack_right` = right hook (D key), `attack_head` = head defense (W key), `attack_body` = body defense (S key).

- [ ] **Step 3: Commit**

```bash
git add project.godot
git commit -m "chore: configure 1920x1080 base resolution and input map"
```

### Task 0.2: Install GUT

**Files:**
- Create: `addons/gut/` (downloaded plugin tree)
- Modify: `project.godot` (enable plugin)

- [ ] **Step 1: Install GUT via AssetLib**

Open Godot editor → AssetLib tab → search "GUT" → install "Gut - Godot Unit Test" by Bitwes (version 9.x, Godot 4 branch).

If AssetLib is unavailable, manually clone (note: GUT renamed the `godot_4` branch; use the `v9.6.0` tag for GUT 9.x):
```bash
git clone --depth=1 --branch v9.6.0 https://github.com/bitwes/Gut.git /tmp/gut
cp -r /tmp/gut/addons/gut /Users/nicholasmejia/godot/love-and-boxing/addons/gut
```

- [ ] **Step 2: Enable GUT in Project Settings → Plugins**

In the Godot editor: Project → Project Settings → Plugins tab → check the box next to "Gut".

- [ ] **Step 3: Verify the GUT bottom panel appears**

Restart the editor if needed. A "GUT" tab should appear in the bottom dock.

- [ ] **Step 4: Commit**

```bash
git add addons/gut project.godot
git commit -m "chore: install GUT 9.x unit testing framework"
```

### Task 0.3: First sanity test

**Files:**
- Create: `tests/unit/test_sanity.gd`

- [ ] **Step 1: Write the sanity test**

Create `tests/unit/test_sanity.gd`:

```gdscript
extends GutTest

func test_sanity():
    assert_eq(1 + 1, 2, "Math still works")
```

- [ ] **Step 2: Run the test from the GUT panel**

In the GUT bottom panel, set the test directory to `res://tests` and click "Run All". Verify `test_sanity` passes green.

- [ ] **Step 3: Verify GUT CLI works (optional but recommended)**

From the project root in a terminal:
```bash
godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit
```
Expected: GUT prints `1/1 passed` and exits with code 0. (Note: GUT does NOT auto-recurse into subdirectories; point `-gdir` at the leaf directory containing tests, or use `-ginclude_subdirs`.)

- [ ] **Step 4: Commit**

```bash
git add tests/
git commit -m "test: add sanity test confirming GUT is wired up"
```

### Task 0.4: Empty Title scene as main scene

**Files:**
- Create: `scenes/title_screen.tscn`
- Create: `scripts/title_screen.gd`

- [ ] **Step 1: Create `scripts/title_screen.gd`**

```gdscript
extends Control

func _ready() -> void:
    print("Title screen loaded")
```

- [ ] **Step 2: Create `scenes/title_screen.tscn`**

In the editor: New Scene → Control as root → name it "TitleScreen" → attach `scripts/title_screen.gd`. Set the Control to full-rect (Layout → Anchor Preset → Full Rect). Save to `res://scenes/title_screen.tscn`.

- [ ] **Step 3: Run the project (F5) and confirm**

The window opens at 1280×720, blank, with "Title screen loaded" in the console. No errors.

- [ ] **Step 4: Commit**

```bash
git add scenes/title_screen.tscn scripts/title_screen.gd
git commit -m "feat: add empty title screen as main scene entry point"
```

---

## Milestone 1: Core Pure-Logic Game Systems (TDD)

**Goal:** Implement and unit-test every pure-logic class the gameplay depends on. No scenes, no visuals — just classes and tests. Establishes the discipline of TDD before any UI work touches game rules.

**Manual test for this milestone:**
- Open the GUT panel, run all tests. All tests pass green. Test count is approximately 40+.

### Task 1.1: `Outcome` enum

**Files:**
- Create: `scripts/game/outcome.gd`

- [ ] **Step 1: Create the Outcome enum**

```gdscript
class_name Outcome
extends RefCounted

enum Type {
    WRONG = 0,
    NEUTRAL = 1,
    RIGHT = 2,
}
```

No test needed (pure enum).

- [ ] **Step 2: Commit**

```bash
git add scripts/game/outcome.gd
git commit -m "feat: add Outcome enum for riddle answer classification"
```

### Task 1.2: `Hearts` with cap at 5 (TDD)

**Files:**
- Create: `tests/unit/test_hearts.gd`
- Create: `scripts/game/hearts.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_hearts.gd`:

```gdscript
extends GutTest

func test_hearts_start_at_five():
    var h := Hearts.new()
    assert_eq(h.current(), 5)

func test_damage_subtracts_one():
    var h := Hearts.new()
    h.take_damage()
    assert_eq(h.current(), 4)

func test_damage_never_below_zero():
    var h := Hearts.new()
    for i in range(10):
        h.take_damage()
    assert_eq(h.current(), 0)

func test_heal_adds_one():
    var h := Hearts.new()
    h.take_damage()
    h.take_damage()
    h.heal()
    assert_eq(h.current(), 4)

func test_heal_caps_at_five():
    var h := Hearts.new()
    h.heal()
    assert_eq(h.current(), 5, "Heal at full health should stay at 5")

func test_is_empty():
    var h := Hearts.new()
    assert_false(h.is_empty())
    for i in range(5):
        h.take_damage()
    assert_true(h.is_empty())
```

- [ ] **Step 2: Run tests, confirm failure**

In GUT panel, run `test_hearts.gd`. Expected: 6 failures, all complaining "Hearts is not defined" or similar.

- [ ] **Step 3: Implement Hearts**

Create `scripts/game/hearts.gd`:

```gdscript
class_name Hearts
extends RefCounted

const MAX_HEARTS := 5

var _current: int = MAX_HEARTS

func current() -> int:
    return _current

func take_damage() -> void:
    _current = max(0, _current - 1)

func heal() -> void:
    _current = min(MAX_HEARTS, _current + 1)

func is_empty() -> bool:
    return _current <= 0
```

- [ ] **Step 4: Run tests, confirm pass**

All 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add tests/unit/test_hearts.gd scripts/game/hearts.gd
git commit -m "feat: add Hearts with cap at 5 and floor at 0"
```

### Task 1.3: `Knockdowns` with floor at 0 (TDD)

**Files:**
- Create: `tests/unit/test_knockdowns.gd`
- Create: `scripts/game/knockdowns.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
extends GutTest

func test_starts_at_zero():
    var k := Knockdowns.new()
    assert_eq(k.count(), 0)

func test_increment():
    var k := Knockdowns.new()
    k.increment()
    assert_eq(k.count(), 1)

func test_round_end_decrement():
    var k := Knockdowns.new()
    k.increment()
    k.increment()
    k.apply_round_end_decrement()
    assert_eq(k.count(), 1)

func test_round_end_floor_at_zero():
    var k := Knockdowns.new()
    k.apply_round_end_decrement()
    assert_eq(k.count(), 0, "Decrement at zero stays at zero")

func test_is_knockout_at_three():
    var k := Knockdowns.new()
    k.increment()
    k.increment()
    assert_false(k.is_knockout())
    k.increment()
    assert_true(k.is_knockout())
```

- [ ] **Step 2: Run tests, confirm failure**
- [ ] **Step 3: Implement Knockdowns**

```gdscript
class_name Knockdowns
extends RefCounted

const KO_THRESHOLD := 3

var _count: int = 0

func count() -> int:
    return _count

func increment() -> void:
    _count += 1

func apply_round_end_decrement() -> void:
    _count = max(0, _count - 1)

func is_knockout() -> bool:
    return _count >= KO_THRESHOLD
```

- [ ] **Step 4: Run tests, confirm pass**
- [ ] **Step 5: Commit**

```bash
git add tests/unit/test_knockdowns.gd scripts/game/knockdowns.gd
git commit -m "feat: add Knockdowns counter with round-end decrement and KO threshold"
```

### Task 1.4: `ComboState` x1 → x2 → x3 → knockdown (TDD)

**Files:**
- Create: `tests/unit/test_combo_state.gd`
- Create: `scripts/game/combo_state.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
extends GutTest

func test_starts_at_x1():
    var c := ComboState.new()
    assert_eq(c.level(), 1)

func test_input_count_equals_level():
    var c := ComboState.new()
    assert_eq(c.input_count(), 1)
    c.on_attack_success()
    assert_eq(c.input_count(), 2)

func test_advance_through_levels():
    var c := ComboState.new()
    c.on_attack_success()
    assert_eq(c.level(), 2)
    c.on_attack_success()
    assert_eq(c.level(), 3)

func test_attack_at_x3_signals_knockdown():
    var c := ComboState.new()
    c.on_attack_success()
    c.on_attack_success()
    assert_true(c.is_at_knockdown_threshold())

func test_knockdown_resets_to_x1():
    var c := ComboState.new()
    c.on_attack_success()
    c.on_attack_success()
    c.on_knockdown_completed()
    assert_eq(c.level(), 1)

func test_damage_resets_to_x1():
    var c := ComboState.new()
    c.on_attack_success()
    c.on_damage_taken()
    assert_eq(c.level(), 1)

func test_attack_failure_does_not_reset():
    var c := ComboState.new()
    c.on_attack_success()
    c.on_attack_failure()
    assert_eq(c.level(), 2, "Failed attack must preserve combo")
```

- [ ] **Step 2: Run tests, confirm failure**
- [ ] **Step 3: Implement ComboState**

```gdscript
class_name ComboState
extends RefCounted

const MIN_LEVEL := 1
const KNOCKDOWN_LEVEL := 3

var _level: int = MIN_LEVEL

func level() -> int:
    return _level

func input_count() -> int:
    return _level

func is_at_knockdown_threshold() -> bool:
    return _level >= KNOCKDOWN_LEVEL

func on_attack_success() -> void:
    if _level < KNOCKDOWN_LEVEL:
        _level += 1

func on_attack_failure() -> void:
    pass  # Intentional no-op; failed attacks preserve combo.

func on_damage_taken() -> void:
    _level = MIN_LEVEL

func on_knockdown_completed() -> void:
    _level = MIN_LEVEL
```

- [ ] **Step 4: Run tests, confirm pass**
- [ ] **Step 5: Commit**

```bash
git add tests/unit/test_combo_state.gd scripts/game/combo_state.gd
git commit -m "feat: add ComboState with x1→x3 progression and damage reset"
```

### Task 1.5: `SimonSequence` classic accumulation (TDD)

**Files:**
- Create: `tests/unit/test_simon_sequence.gd`
- Create: `scripts/game/simon_sequence.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
extends GutTest

const Dir := preload("res://scripts/game/simon_sequence.gd").Direction

func _seeded() -> SimonSequence:
    var seq := SimonSequence.new()
    seq.seed_rng(42)
    return seq

func test_starts_empty_then_advance_to_length_one():
    var seq := _seeded()
    assert_eq(seq.length(), 0)
    seq.extend()
    assert_eq(seq.length(), 1)

func test_extend_accumulates_preserving_prefix():
    var seq := _seeded()
    seq.extend()
    var first := seq.steps()[0]
    seq.extend()
    assert_eq(seq.length(), 2)
    assert_eq(seq.steps()[0], first, "Prefix preserved on accumulation")

func test_validate_step_at_index():
    var seq := _seeded()
    seq.extend()
    var step := seq.steps()[0]
    assert_true(seq.validate_at(0, step))
    assert_false(seq.validate_at(0, _wrong_direction(step)))

func test_reset_clears_chain():
    var seq := _seeded()
    seq.extend()
    seq.extend()
    seq.reset()
    assert_eq(seq.length(), 0)

func test_direction_set_is_complete():
    assert_eq(SimonSequence.ALL_DIRECTIONS.size(), 4)

func _wrong_direction(step: int) -> int:
    for d in SimonSequence.ALL_DIRECTIONS:
        if d != step:
            return d
    return step
```

- [ ] **Step 2: Run tests, confirm failure**
- [ ] **Step 3: Implement SimonSequence**

```gdscript
class_name SimonSequence
extends RefCounted

enum Direction {
    HEAD = 0,    # W
    LEFT = 1,    # A (left hook)
    BODY = 2,    # S
    RIGHT = 3,   # D (right hook)
}

const ALL_DIRECTIONS: Array[int] = [
    Direction.HEAD,
    Direction.LEFT,
    Direction.BODY,
    Direction.RIGHT,
]

var _steps: Array[int] = []
var _rng := RandomNumberGenerator.new()

func _init() -> void:
    _rng.randomize()

func seed_rng(seed_value: int) -> void:
    _rng.seed = seed_value

func length() -> int:
    return _steps.size()

func steps() -> Array[int]:
    return _steps.duplicate()

func extend() -> void:
    var next := ALL_DIRECTIONS[_rng.randi() % ALL_DIRECTIONS.size()]
    _steps.append(next)

func validate_at(index: int, direction: int) -> bool:
    if index < 0 or index >= _steps.size():
        return false
    return _steps[index] == direction

func reset() -> void:
    _steps.clear()
```

- [ ] **Step 4: Run tests, confirm pass**
- [ ] **Step 5: Commit**

```bash
git add tests/unit/test_simon_sequence.gd scripts/game/simon_sequence.gd
git commit -m "feat: add SimonSequence with classic accumulation and seedable RNG"
```

### Task 1.6: `MatchClock` with pause/resume (TDD)

**Files:**
- Create: `tests/unit/test_match_clock.gd`
- Create: `scripts/game/match_clock.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
extends GutTest

func test_starts_at_full_round():
    var c := MatchClock.new()
    assert_eq(c.seconds_remaining(), 300.0)
    assert_eq(c.current_round(), 1)

func test_tick_decrements_when_running():
    var c := MatchClock.new()
    c.start()
    c.tick(1.5)
    assert_almost_eq(c.seconds_remaining(), 298.5, 0.001)

func test_pause_freezes_clock():
    var c := MatchClock.new()
    c.start()
    c.pause()
    c.tick(5.0)
    assert_eq(c.seconds_remaining(), 300.0)

func test_resume_unfreezes_clock():
    var c := MatchClock.new()
    c.start()
    c.pause()
    c.tick(5.0)
    c.resume()
    c.tick(1.0)
    assert_almost_eq(c.seconds_remaining(), 299.0, 0.001)

func test_round_over_when_zero():
    var c := MatchClock.new()
    c.start()
    c.tick(300.0)
    assert_true(c.is_round_over())

func test_advance_round_resets_clock():
    var c := MatchClock.new()
    c.start()
    c.tick(300.0)
    c.advance_to_next_round()
    assert_eq(c.current_round(), 2)
    assert_eq(c.seconds_remaining(), 300.0)

func test_no_third_round():
    var c := MatchClock.new()
    c.start()
    c.tick(300.0)
    c.advance_to_next_round()
    c.tick(300.0)
    assert_true(c.is_match_over())
```

- [ ] **Step 2: Run tests, confirm failure**
- [ ] **Step 3: Implement MatchClock**

```gdscript
class_name MatchClock
extends RefCounted

const ROUND_DURATION_SECONDS := 300.0
const TOTAL_ROUNDS := 2

var _seconds_remaining: float = ROUND_DURATION_SECONDS
var _current_round: int = 1
var _running: bool = false
var _match_over: bool = false

func start() -> void:
    _running = true

func pause() -> void:
    _running = false

func resume() -> void:
    _running = true

func tick(delta: float) -> void:
    if not _running or _match_over:
        return
    _seconds_remaining = max(0.0, _seconds_remaining - delta)

func seconds_remaining() -> float:
    return _seconds_remaining

func current_round() -> int:
    return _current_round

func is_round_over() -> bool:
    return _seconds_remaining <= 0.0

func is_match_over() -> bool:
    return _match_over or (is_round_over() and _current_round >= TOTAL_ROUNDS)

func advance_to_next_round() -> void:
    if _current_round >= TOTAL_ROUNDS:
        _match_over = true
        return
    _current_round += 1
    _seconds_remaining = ROUND_DURATION_SECONDS
```

- [ ] **Step 4: Run tests, confirm pass**
- [ ] **Step 5: Commit**

```bash
git add tests/unit/test_match_clock.gd scripts/game/match_clock.gd
git commit -m "feat: add MatchClock with two-round structure and pause/resume"
```

### Task 1.7: `DialogueAnswer` and `DialoguePrompt` Resources (TDD-lite)

**Files:**
- Create: `scripts/game/dialogue_answer.gd`
- Create: `scripts/game/dialogue_prompt.gd`
- Create: `tests/unit/test_dialogue_prompt.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
extends GutTest

func test_prompt_holds_three_answers():
    var p := DialoguePrompt.new()
    var a1 := DialogueAnswer.new()
    a1.outcome = Outcome.Type.WRONG
    a1.text = "wrong"
    var a2 := DialogueAnswer.new()
    a2.outcome = Outcome.Type.NEUTRAL
    a2.text = "neutral"
    var a3 := DialogueAnswer.new()
    a3.outcome = Outcome.Type.RIGHT
    a3.text = "right"
    p.answers = [a1, a2, a3]
    assert_eq(p.answers.size(), 3)
    assert_eq(p.answers[2].outcome, Outcome.Type.RIGHT)

func test_prompt_body_is_text_or_image():
    var p := DialoguePrompt.new()
    p.body_text = "Hello"
    assert_true(p.has_text_body())
    assert_false(p.has_image_body())

func test_prompt_with_image_body():
    var p := DialoguePrompt.new()
    p.body_image = PlaceholderTexture2D.new()
    assert_true(p.has_image_body())
    assert_false(p.has_text_body())
```

- [ ] **Step 2: Run tests, confirm failure**
- [ ] **Step 3: Implement DialogueAnswer**

```gdscript
class_name DialogueAnswer
extends Resource

@export var text: String = ""
@export var image: Texture2D
@export var outcome: int = Outcome.Type.NEUTRAL

func has_text() -> bool:
    return text != ""

func has_image() -> bool:
    return image != null
```

- [ ] **Step 4: Implement DialoguePrompt**

```gdscript
class_name DialoguePrompt
extends Resource

@export var body_text: String = ""
@export var body_image: Texture2D
@export var answers: Array[DialogueAnswer] = []

func has_text_body() -> bool:
    return body_text != ""

func has_image_body() -> bool:
    return body_image != null
```

- [ ] **Step 5: Run tests, confirm pass**
- [ ] **Step 6: Commit**

```bash
git add scripts/game/dialogue_answer.gd scripts/game/dialogue_prompt.gd tests/unit/test_dialogue_prompt.gd
git commit -m "feat: add DialoguePrompt and DialogueAnswer resources supporting text+image"
```

### Task 1.8: `DialogueDeck` shuffle-without-replacement (TDD)

**Files:**
- Create: `tests/unit/test_dialogue_deck.gd`
- Create: `scripts/game/dialogue_deck.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
extends GutTest

func _make_prompt(label: String) -> DialoguePrompt:
    var p := DialoguePrompt.new()
    p.body_text = label
    return p

func _make_prompts(count: int) -> Array[DialoguePrompt]:
    var arr: Array[DialoguePrompt] = []
    for i in count:
        arr.append(_make_prompt("p%d" % i))
    return arr

func test_draws_each_prompt_once_before_repeating():
    var deck := DialogueDeck.new()
    deck.seed_rng(7)
    deck.load_prompts(_make_prompts(4))
    var drawn: Array[String] = []
    for i in 4:
        drawn.append(deck.draw().body_text)
    drawn.sort()
    assert_eq(drawn, ["p0", "p1", "p2", "p3"])

func test_reshuffles_after_exhaustion():
    var deck := DialogueDeck.new()
    deck.seed_rng(7)
    deck.load_prompts(_make_prompts(2))
    deck.draw()
    deck.draw()
    var fifth := deck.draw()
    assert_not_null(fifth, "Deck must reshuffle after exhausting")

func test_reset_reshuffles_full_deck():
    var deck := DialogueDeck.new()
    deck.seed_rng(7)
    deck.load_prompts(_make_prompts(3))
    deck.draw()
    deck.reset()
    var drawn: Array[String] = []
    for i in 3:
        drawn.append(deck.draw().body_text)
    drawn.sort()
    assert_eq(drawn, ["p0", "p1", "p2"], "Reset restores all prompts")
```

- [ ] **Step 2: Run tests, confirm failure**
- [ ] **Step 3: Implement DialogueDeck**

```gdscript
class_name DialogueDeck
extends RefCounted

var _source: Array[DialoguePrompt] = []
var _remaining: Array[DialoguePrompt] = []
var _rng := RandomNumberGenerator.new()

func _init() -> void:
    _rng.randomize()

func seed_rng(seed_value: int) -> void:
    _rng.seed = seed_value

func load_prompts(prompts: Array[DialoguePrompt]) -> void:
    _source = prompts.duplicate()
    _refill()

func draw() -> DialoguePrompt:
    if _remaining.is_empty():
        _refill()
    if _remaining.is_empty():
        return null
    var idx := _rng.randi() % _remaining.size()
    return _remaining.pop_at(idx)

func reset() -> void:
    _refill()

func _refill() -> void:
    _remaining = _source.duplicate()
```

- [ ] **Step 4: Run tests, confirm pass**
- [ ] **Step 5: Commit**

```bash
git add tests/unit/test_dialogue_deck.gd scripts/game/dialogue_deck.gd
git commit -m "feat: add DialogueDeck with shuffle-without-replacement and reset"
```

### Task 1.9: `DifficultyConfig` Resource (TDD-lite)

**Files:**
- Create: `scripts/game/difficulty_config.gd`
- Create: `tests/unit/test_difficulty_config.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
extends GutTest

func test_difficulty_config_holds_pacing_values():
    var d := DifficultyConfig.new()
    d.show_phase_step_seconds = 0.6
    d.repeat_phase_window_seconds = 2.5
    d.opponent_slug = "minty"
    assert_almost_eq(d.show_phase_step_seconds, 0.6, 0.001)
    assert_almost_eq(d.repeat_phase_window_seconds, 2.5, 0.001)
    assert_eq(d.opponent_slug, "minty")
```

- [ ] **Step 2: Implement DifficultyConfig**

```gdscript
class_name DifficultyConfig
extends Resource

@export var opponent_slug: String = ""
@export var tier: int = 1
@export var show_phase_step_seconds: float = 0.8
@export var repeat_phase_window_seconds: float = 3.0
@export var dialogue_deck_path: String = ""
```

- [ ] **Step 3: Run tests, confirm pass**
- [ ] **Step 4: Commit**

```bash
git add scripts/game/difficulty_config.gd tests/unit/test_difficulty_config.gd
git commit -m "feat: add DifficultyConfig resource for per-opponent pacing"
```

### Manual Test for Milestone 1

- Open the GUT panel, click "Run All".
- Expected: 40+ tests all green. No errors in the output panel.

---

## Milestone 2: Autoload Singletons and Scene Router

**Goal:** Wire the four autoload singletons and create stub scenes for every top-level navigation target. Player can walk through Title → LevelSelect → Gameplay → MatchResults → LevelSelect without errors. No gameplay logic yet.

**Manual test for this milestone:**
- Launch the game.
- Title screen shows four labeled buttons (Start, Options, Credits, Quit).
- Press K (or click) on Start → LevelSelect appears.
- LevelSelect shows three labeled tier cards. Press K on any → Gameplay stub appears with a "Back to Results" button.
- Pressing K → MatchResults appears with "Return to Level Select" button.
- Pressing K → back to LevelSelect.
- Options and Credits buttons show a "Coming Soon" label briefly.
- Quit from title exits the game.

### Task 2.1: `Globals` autoload

**Files:**
- Create: `scripts/autoload/globals.gd`
- Modify: `project.godot`

- [ ] **Step 1: Create the Globals singleton**

```gdscript
extends Node

var selected_difficulty: DifficultyConfig

func clear_selection() -> void:
    selected_difficulty = null
```

- [ ] **Step 2: Register as autoload**

In Project Settings → Autoload, add `scripts/autoload/globals.gd` with node name `Globals`.

- [ ] **Step 3: Commit**

```bash
git add scripts/autoload/globals.gd project.godot
git commit -m "feat: add Globals autoload for cross-scene state"
```

### Task 2.2: `SaveData` autoload (TDD-lite where possible)

**Files:**
- Create: `scripts/autoload/save_data.gd`
- Create: `tests/unit/test_save_data.gd`
- Modify: `project.godot`

- [ ] **Step 1: Write the failing test**

```gdscript
extends GutTest

const SaveDataClass := preload("res://scripts/autoload/save_data.gd")

func before_each():
    SaveDataClass.TEST_PATH = "user://test_progress.cfg"
    var f := FileAccess.open(SaveDataClass.TEST_PATH, FileAccess.WRITE)
    if f:
        f.close()
    DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveDataClass.TEST_PATH))

func test_default_unlocked_tier_is_one():
    var sd := SaveDataClass.new()
    sd.use_test_path()
    assert_eq(sd.unlocked_tier(), 1)

func test_unlock_persists():
    var sd := SaveDataClass.new()
    sd.use_test_path()
    sd.unlock_tier(2)
    var sd2 := SaveDataClass.new()
    sd2.use_test_path()
    assert_eq(sd2.unlocked_tier(), 2)

func test_unlock_never_regresses():
    var sd := SaveDataClass.new()
    sd.use_test_path()
    sd.unlock_tier(3)
    sd.unlock_tier(1)
    assert_eq(sd.unlocked_tier(), 3, "Unlocking lower tier must not regress")
```

- [ ] **Step 2: Run tests, confirm failure**
- [ ] **Step 3: Implement SaveData**

```gdscript
extends Node

const DEFAULT_PATH := "user://progress.cfg"
static var TEST_PATH := ""

var _path: String = DEFAULT_PATH
var _config := ConfigFile.new()

func _ready() -> void:
    _load()

func use_test_path() -> void:
    _path = TEST_PATH
    _config = ConfigFile.new()
    _load()

func unlocked_tier() -> int:
    return _config.get_value("progress", "unlocked_tier", 1)

func unlock_tier(tier: int) -> void:
    var current := unlocked_tier()
    if tier <= current:
        return
    _config.set_value("progress", "unlocked_tier", tier)
    _config.save(_path)

func _load() -> void:
    var err := _config.load(_path)
    if err != OK:
        _config.set_value("progress", "unlocked_tier", 1)
```

- [ ] **Step 4: Register as autoload**

In Project Settings → Autoload, add `scripts/autoload/save_data.gd` with node name `SaveData`.

- [ ] **Step 5: Run tests, confirm pass**
- [ ] **Step 6: Commit**

```bash
git add scripts/autoload/save_data.gd tests/unit/test_save_data.gd project.godot
git commit -m "feat: add SaveData autoload backed by user://progress.cfg"
```

### Task 2.3: `AudioBus` autoload (stub)

**Files:**
- Create: `scripts/autoload/audio_bus.gd`
- Modify: `project.godot`

- [ ] **Step 1: Implement the stub**

```gdscript
extends Node

# First-pass implementation: log the SFX call but don't play anything.
# Real audio is wired in a later milestone.

func play_sfx(name: String) -> void:
    print("[AudioBus] play_sfx: %s" % name)

func play_music(name: String) -> void:
    print("[AudioBus] play_music: %s" % name)

func stop_music() -> void:
    print("[AudioBus] stop_music")
```

- [ ] **Step 2: Register as autoload**

Autoload `scripts/autoload/audio_bus.gd` as `AudioBus`.

- [ ] **Step 3: Commit**

```bash
git add scripts/autoload/audio_bus.gd project.godot
git commit -m "feat: add AudioBus autoload stub for deferred audio integration"
```

### Task 2.4: `SceneRouter` autoload

**Files:**
- Create: `scripts/autoload/scene_router.gd`
- Modify: `project.godot`

- [ ] **Step 1: Implement SceneRouter**

```gdscript
extends Node

const TITLE := "res://scenes/title_screen.tscn"
const LEVEL_SELECT := "res://scenes/level_select.tscn"
const GAMEPLAY := "res://scenes/gameplay.tscn"
const MATCH_RESULTS := "res://scenes/match_results.tscn"

func goto_title() -> void:
    get_tree().change_scene_to_file(TITLE)

func goto_level_select() -> void:
    get_tree().change_scene_to_file(LEVEL_SELECT)

func goto_gameplay() -> void:
    get_tree().change_scene_to_file(GAMEPLAY)

func goto_match_results() -> void:
    get_tree().change_scene_to_file(MATCH_RESULTS)

func quit_game() -> void:
    get_tree().quit()
```

- [ ] **Step 2: Register as autoload**

Autoload `scripts/autoload/scene_router.gd` as `SceneRouter`.

- [ ] **Step 3: Commit**

```bash
git add scripts/autoload/scene_router.gd project.godot
git commit -m "feat: add SceneRouter autoload centralizing scene transitions"
```

### Task 2.5: Title Screen with menu buttons

**Files:**
- Modify: `scenes/title_screen.tscn`
- Modify: `scripts/title_screen.gd`

- [ ] **Step 1: Update `scripts/title_screen.gd`**

```gdscript
extends Control

@onready var _buttons: Array[Button] = [
    $VBoxContainer/StartButton,
    $VBoxContainer/OptionsButton,
    $VBoxContainer/CreditsButton,
    $VBoxContainer/QuitButton,
]
@onready var _coming_soon: Label = $ComingSoonLabel

var _focus_index: int = 0

func _ready() -> void:
    _coming_soon.visible = false
    _update_focus()
    $VBoxContainer/StartButton.pressed.connect(SceneRouter.goto_level_select)
    $VBoxContainer/OptionsButton.pressed.connect(_show_coming_soon)
    $VBoxContainer/CreditsButton.pressed.connect(_show_coming_soon)
    $VBoxContainer/QuitButton.pressed.connect(SceneRouter.quit_game)

func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed("menu_up"):
        _focus_index = (_focus_index - 1 + _buttons.size()) % _buttons.size()
        _update_focus()
    elif event.is_action_pressed("menu_confirm"):
        _buttons[_focus_index].pressed.emit()

func _update_focus() -> void:
    _buttons[_focus_index].grab_focus()

func _show_coming_soon() -> void:
    _coming_soon.visible = true
    await get_tree().create_timer(1.0).timeout
    _coming_soon.visible = false
```

- [ ] **Step 2: Build the scene tree**

In the editor, open `scenes/title_screen.tscn`. Add this tree:
- Control (root, full rect) `TitleScreen`
  - Label `TitleLabel` — text "LOVE AND BOXING", centered top
  - VBoxContainer `VBoxContainer` — centered
    - Button `StartButton` — text "Start"
    - Button `OptionsButton` — text "Options"
    - Button `CreditsButton` — text "Credits"
    - Button `QuitButton` — text "Quit"
  - Label `ComingSoonLabel` — text "Coming Soon", below the VBox, hidden by default

- [ ] **Step 3: Run the game**

Press F5. Title shows. Click Start → no error (LevelSelect doesn't exist yet, console will show a missing-scene error, that's expected). Press Quit → game exits.

- [ ] **Step 4: Commit**

```bash
git add scenes/title_screen.tscn scripts/title_screen.gd
git commit -m "feat: add Title screen with menu navigation"
```

### Task 2.6: Level Select stub

**Files:**
- Create: `scenes/level_select.tscn`
- Create: `scripts/level_select.gd`

- [ ] **Step 1: Implement the script**

```gdscript
extends Control

@onready var _cards: Array[Button] = [
    $HBoxContainer/TofuCard,
    $HBoxContainer/MintyCard,
    $HBoxContainer/SebastianCard,
]

var _focus_index: int = 0

func _ready() -> void:
    _cards[0].pressed.connect(func(): _select_tier(1))
    _cards[1].pressed.connect(func(): _select_tier(2))
    _cards[2].pressed.connect(func(): _select_tier(3))
    _update_focus()

func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed("menu_left"):
        _focus_index = (_focus_index - 1 + _cards.size()) % _cards.size()
        _update_focus()
    elif event.is_action_pressed("menu_right"):
        _focus_index = (_focus_index + 1) % _cards.size()
        _update_focus()
    elif event.is_action_pressed("menu_confirm"):
        _cards[_focus_index].pressed.emit()

func _update_focus() -> void:
    _cards[_focus_index].grab_focus()

func _select_tier(tier: int) -> void:
    SceneRouter.goto_gameplay()  # No difficulty wiring yet; just navigates.
```

- [ ] **Step 2: Build the scene tree**

- Control (root, full rect) `LevelSelect`
  - Label `Title` — text "Select Opponent", top
  - HBoxContainer `HBoxContainer` — centered
    - Button `TofuCard` — text "Tofu (Easy)", min size 300×400
    - Button `MintyCard` — text "Minty (Medium)", min size 300×400
    - Button `SebastianCard` — text "Sebastian (Hard)", min size 300×400

Attach `scripts/level_select.gd`.

- [ ] **Step 3: Run the game, walk Title → LevelSelect**

Verify navigation works. Tofu/Minty/Sebastian buttons all attempt to go to Gameplay (missing scene error expected for now).

- [ ] **Step 4: Commit**

```bash
git add scenes/level_select.tscn scripts/level_select.gd
git commit -m "feat: add LevelSelect stub with three tier cards"
```

### Task 2.7: Gameplay stub

**Files:**
- Create: `scenes/gameplay.tscn`
- Create: `scripts/gameplay.gd`

- [ ] **Step 1: Implement the stub script**

```gdscript
extends Control

func _ready() -> void:
    $CenterContainer/EndButton.pressed.connect(SceneRouter.goto_match_results)

func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed("menu_confirm"):
        SceneRouter.goto_match_results()
```

- [ ] **Step 2: Build the scene tree**

- Control (root, full rect) `Gameplay`
  - Label `Header` — text "Gameplay Stub", top
  - CenterContainer `CenterContainer` — fills rect
    - Button `EndButton` — text "End Match (K)"

Attach `scripts/gameplay.gd`.

- [ ] **Step 3: Run the full flow**

Title → Start → LevelSelect → Tofu → Gameplay → End Match → MatchResults (missing scene expected).

- [ ] **Step 4: Commit**

```bash
git add scenes/gameplay.tscn scripts/gameplay.gd
git commit -m "feat: add Gameplay stub scene"
```

### Task 2.8: Match Results stub

**Files:**
- Create: `scenes/match_results.tscn`
- Create: `scripts/match_results.gd`

- [ ] **Step 1: Implement the script**

```gdscript
extends Control

func _ready() -> void:
    $CenterContainer/VBox/ReturnButton.pressed.connect(SceneRouter.goto_level_select)

func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed("menu_confirm"):
        SceneRouter.goto_level_select()
```

- [ ] **Step 2: Build the scene tree**

- Control (root, full rect) `MatchResults`
  - CenterContainer `CenterContainer`
    - VBoxContainer `VBox`
      - Label `Outcome` — text "Match Complete"
      - Button `ReturnButton` — text "Return to Level Select (K)"

Attach `scripts/match_results.gd`.

- [ ] **Step 3: Run full flow end-to-end**

Title → Start → LevelSelect → Tofu → Gameplay → End Match → MatchResults → Return → LevelSelect → … loop works.

- [ ] **Step 4: Commit**

```bash
git add scenes/match_results.tscn scripts/match_results.gd
git commit -m "feat: add MatchResults stub closing the navigation loop"
```

### Manual Test for Milestone 2

- Run the game.
- Walk every navigation path: Title → Start/Options/Credits/Quit.
- LevelSelect → each of Tofu/Minty/Sebastian → Gameplay → MatchResults → back to LevelSelect.
- Confirm IJKL + arrows + mouse all work.
- Confirm Options and Credits show "Coming Soon" then auto-hide.
- Confirm Quit from Title exits the game.

---

## Milestone 3: Save System Integration with Level Select

**Goal:** Wire `SaveData` into `LevelSelect` so locked tiers cannot be selected. Add a developer wipe shortcut so testing is easy.

**Manual test for this milestone:**
- First run: Tofu is unlocked, Minty and Sebastian are locked (visually distinct, e.g. greyed out with a padlock label).
- Press K on Tofu, then on MatchResults press F10 to grant "won" outcome for the current tier. Tier 2 unlocks.
- Restart the game. Tier 2 is still unlocked.
- Press F12 anywhere on LevelSelect to wipe progress. Restart. Only Tier 1 is unlocked.

### Task 3.1: Locked-state visuals on `LevelSelect`

**Files:**
- Modify: `scripts/level_select.gd`
- Modify: `scenes/level_select.tscn`

- [ ] **Step 1: Add a `_locked` flag and visual treatment**

Update `scripts/level_select.gd`:

```gdscript
extends Control

@onready var _cards: Array[Button] = [
    $HBoxContainer/TofuCard,
    $HBoxContainer/MintyCard,
    $HBoxContainer/SebastianCard,
]

var _focus_index: int = 0

func _ready() -> void:
    _apply_lock_states()
    _cards[0].pressed.connect(func(): _select_tier(1))
    _cards[1].pressed.connect(func(): _select_tier(2))
    _cards[2].pressed.connect(func(): _select_tier(3))
    _update_focus()

func _apply_lock_states() -> void:
    var unlocked := SaveData.unlocked_tier()
    for i in _cards.size():
        var tier := i + 1
        var card := _cards[i]
        var locked := tier > unlocked
        card.disabled = locked
        card.modulate = Color(0.4, 0.4, 0.4) if locked else Color.WHITE
        if locked:
            card.text = card.text.replace(" (Easy)", "").replace(" (Medium)", "").replace(" (Hard)", "")
            card.text = "[LOCKED]\n" + card.text

func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed("menu_left"):
        _focus_index = (_focus_index - 1 + _cards.size()) % _cards.size()
        _update_focus()
    elif event.is_action_pressed("menu_right"):
        _focus_index = (_focus_index + 1) % _cards.size()
        _update_focus()
    elif event.is_action_pressed("menu_confirm"):
        var tier := _focus_index + 1
        if tier <= SaveData.unlocked_tier():
            _cards[_focus_index].pressed.emit()
    elif event is InputEventKey and event.pressed and event.keycode == KEY_F12:
        _wipe_progress()

func _update_focus() -> void:
    _cards[_focus_index].grab_focus()

func _select_tier(tier: int) -> void:
    SceneRouter.goto_gameplay()

func _wipe_progress() -> void:
    var path := "user://progress.cfg"
    if FileAccess.file_exists(path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    print("[LevelSelect] Progress wiped. Restart for changes to apply.")
```

- [ ] **Step 2: Run, verify Tofu unlocked + others locked**

Verify visually that Tofu is highlighted normally and Minty/Sebastian appear greyed with "[LOCKED]" prefix.

- [ ] **Step 3: Commit**

```bash
git add scripts/level_select.gd
git commit -m "feat: show locked tier state and add F12 progress wipe"
```

### Task 3.2: Award unlock on match win (placeholder)

**Files:**
- Modify: `scripts/match_results.gd`
- Modify: `scripts/gameplay.gd`
- Modify: `scripts/autoload/globals.gd`

- [ ] **Step 1: Add a `last_match_outcome` field to Globals**

Update `scripts/autoload/globals.gd`:

```gdscript
extends Node

enum MatchOutcome { WIN, LOSE, DRAW }

var selected_difficulty: DifficultyConfig
var last_match_outcome: int = MatchOutcome.DRAW
var last_played_tier: int = 1

func clear_selection() -> void:
    selected_difficulty = null
```

- [ ] **Step 2: Set outcome from Gameplay stub**

Update `scripts/gameplay.gd` to set tier + outcome before routing. Since difficulty wiring lands later, hardcode the tier for now via a simple counter:

```gdscript
extends Control

func _ready() -> void:
    Globals.last_played_tier = 1  # Will be replaced by Globals.selected_difficulty.tier later
    Globals.last_match_outcome = Globals.MatchOutcome.WIN
    $CenterContainer/EndButton.pressed.connect(SceneRouter.goto_match_results)

func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed("menu_confirm"):
        SceneRouter.goto_match_results()
```

- [ ] **Step 3: Award unlock in MatchResults**

Update `scripts/match_results.gd`:

```gdscript
extends Control

@onready var _outcome_label: Label = $CenterContainer/VBox/Outcome
@onready var _unlock_label: Label = $CenterContainer/VBox/UnlockLabel

func _ready() -> void:
    _outcome_label.text = _outcome_text()
    _unlock_label.visible = false
    if Globals.last_match_outcome == Globals.MatchOutcome.WIN:
        var next_tier := Globals.last_played_tier + 1
        if next_tier <= 3 and next_tier > SaveData.unlocked_tier():
            SaveData.unlock_tier(next_tier)
            _unlock_label.text = "Unlocked tier %d!" % next_tier
            _unlock_label.visible = true
    $CenterContainer/VBox/ReturnButton.pressed.connect(SceneRouter.goto_level_select)

func _outcome_text() -> String:
    match Globals.last_match_outcome:
        Globals.MatchOutcome.WIN: return "You Win!"
        Globals.MatchOutcome.LOSE: return "You Lose!"
        _: return "Draw!"

func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed("menu_confirm"):
        SceneRouter.goto_level_select()
```

- [ ] **Step 4: Add `UnlockLabel` to the scene**

In the editor, edit `scenes/match_results.tscn`:
- Under `CenterContainer/VBox`, insert a Label called `UnlockLabel` above `ReturnButton`, default text "".

- [ ] **Step 5: Run, verify unlock flow**

Title → Start → Tofu → Gameplay → End Match → see "You Win!" + "Unlocked tier 2!" → Return → LevelSelect now shows Minty unlocked. Restart game, Minty still unlocked.

- [ ] **Step 6: Commit**

```bash
git add scripts/match_results.gd scripts/gameplay.gd scripts/autoload/globals.gd scenes/match_results.tscn
git commit -m "feat: award tier unlock on match win and surface unlock badge"
```

### Manual Test for Milestone 3

- Wipe progress (delete `~/.local/share/godot/app_userdata/LoveAndBoxing/progress.cfg` on Linux, equivalent on Mac/Windows). Run.
- Confirm Tofu only; pick Tofu; finish; see "Unlocked tier 2!"; return; Minty available.
- Restart; Minty still available.
- Press F12 on LevelSelect; restart; back to Tofu only.

---

## Milestone 4: Static Gameplay HUD Shell

**Goal:** Build every HUD region as a separate scene with static placeholder values. The Gameplay scene composes them. No gameplay logic. Visual layout matches the spec.

**Manual test for this milestone:**
- Enter Gameplay. See:
  - 5 hearts top-left.
  - "x1" combo below hearts.
  - "0" knockdown icon top-right.
  - "5:00" timer top-center.
  - A dialogue box centered with placeholder text "[riddle goes here]" and three answer cards below it, labeled "wrong / neutral / right".
- Press K to end the stub match.

### Task 4.1: HeartRow scene

**Files:**
- Create: `scripts/ui/heart_row.gd`
- Create: `scenes/ui/heart_row.tscn`

- [ ] **Step 1: Create the script**

```gdscript
class_name HeartRow
extends HBoxContainer

const MAX_HEARTS := 5

@onready var _slots: Array[TextureRect] = []

func _ready() -> void:
    _slots.clear()
    for i in MAX_HEARTS:
        var t := TextureRect.new()
        t.custom_minimum_size = Vector2(48, 48)
        t.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
        add_child(t)
        _slots.append(t)
    set_hearts(MAX_HEARTS)

func set_hearts(count: int) -> void:
    for i in _slots.size():
        # When real art lands, swap the modulate trick for actual textures.
        _slots[i].modulate = Color(1, 0.2, 0.3) if i < count else Color(0.2, 0.2, 0.2)
        _slots[i].texture = _placeholder_texture()

func _placeholder_texture() -> Texture2D:
    var img := Image.create(48, 48, false, Image.FORMAT_RGBA8)
    img.fill(Color.WHITE)
    return ImageTexture.create_from_image(img)
```

- [ ] **Step 2: Create the scene**

`scenes/ui/heart_row.tscn`: HBoxContainer root, attach the script.

- [ ] **Step 3: Commit**

```bash
git add scripts/ui/heart_row.gd scenes/ui/heart_row.tscn
git commit -m "feat: add HeartRow HUD component with placeholder fills"
```

### Task 4.2: ComboMeter scene

**Files:**
- Create: `scripts/ui/combo_meter.gd`
- Create: `scenes/ui/combo_meter.tscn`

- [ ] **Step 1: Create the script**

```gdscript
class_name ComboMeter
extends Control

@onready var _label: Label = $Label

func _ready() -> void:
    set_level(1)

func set_level(level: int) -> void:
    _label.text = "x%d" % level
```

- [ ] **Step 2: Create the scene**

`scenes/ui/combo_meter.tscn`: Control root with a Label child named "Label", text "x1", large font. Attach the script.

- [ ] **Step 3: Commit**

```bash
git add scripts/ui/combo_meter.gd scenes/ui/combo_meter.tscn
git commit -m "feat: add ComboMeter HUD component"
```

### Task 4.3: KnockdownMeter scene

**Files:**
- Create: `scripts/ui/knockdown_meter.gd`
- Create: `scenes/ui/knockdown_meter.tscn`

- [ ] **Step 1: Create the script**

```gdscript
class_name KnockdownMeter
extends Control

@onready var _label: Label = $Label

func _ready() -> void:
    set_count(0)

func set_count(count: int) -> void:
    _label.text = "KD: %d" % count
```

- [ ] **Step 2: Create the scene**

`scenes/ui/knockdown_meter.tscn`: Control root with a Label child named "Label", text "KD: 0".

- [ ] **Step 3: Commit**

```bash
git add scripts/ui/knockdown_meter.gd scenes/ui/knockdown_meter.tscn
git commit -m "feat: add KnockdownMeter HUD component"
```

### Task 4.4: MatchTimer scene

**Files:**
- Create: `scripts/ui/match_timer.gd`
- Create: `scenes/ui/match_timer.tscn`

- [ ] **Step 1: Create the script**

```gdscript
class_name MatchTimerView
extends Control

@onready var _label: Label = $Label

func _ready() -> void:
    set_seconds(300.0)

func set_seconds(seconds: float) -> void:
    var s := int(ceil(seconds))
    var m := s / 60
    var r := s % 60
    _label.text = "%d:%02d" % [m, r]
```

- [ ] **Step 2: Create the scene**

`scenes/ui/match_timer.tscn`: Control root, Label "Label" text "5:00", large font.

- [ ] **Step 3: Commit**

```bash
git add scripts/ui/match_timer.gd scenes/ui/match_timer.tscn
git commit -m "feat: add MatchTimerView HUD component"
```

### Task 4.5: RiddleBox and AnswerCard scenes

**Files:**
- Create: `scripts/ui/answer_card.gd`
- Create: `scenes/ui/answer_card.tscn`
- Create: `scripts/ui/riddle_box.gd`
- Create: `scenes/ui/riddle_box.tscn`

- [ ] **Step 1: Implement AnswerCard**

```gdscript
class_name AnswerCard
extends PanelContainer

@onready var _text: RichTextLabel = $Stack/Text
@onready var _image: TextureRect = $Stack/Image
@onready var _highlight: ColorRect = $Highlight

var _outcome: int = Outcome.Type.NEUTRAL

func display(answer: DialogueAnswer) -> void:
    _outcome = answer.outcome
    if answer.has_image():
        _image.texture = answer.image
        _image.visible = true
        _text.visible = false
    else:
        _text.text = answer.text
        _text.visible = true
        _image.visible = false

func set_highlighted(highlighted: bool) -> void:
    _highlight.visible = highlighted

func outcome() -> int:
    return _outcome
```

- [ ] **Step 2: Build AnswerCard scene**

`scenes/ui/answer_card.tscn`:
- PanelContainer (root) `AnswerCard`, min size 280×140
  - ColorRect `Highlight` — full rect, color yellow with 0.3 alpha, hidden by default
  - VBoxContainer `Stack`
    - RichTextLabel `Text` — fit_content, autowrap
    - TextureRect `Image` — expand_mode FIT_WIDTH_PROPORTIONAL, hidden by default

- [ ] **Step 3: Implement RiddleBox**

```gdscript
class_name RiddleBox
extends PanelContainer

signal answer_submitted(outcome: int)

@onready var _body_text: RichTextLabel = $Layout/Body/Text
@onready var _body_image: TextureRect = $Layout/Body/Image
@onready var _cards: Array[AnswerCard] = [
    $Layout/Answers/Left,
    $Layout/Answers/Middle,
    $Layout/Answers/Right,
]

var _highlight_index: int = 1  # I = middle by default
var _typewriter_speed: float = 30.0
var _typing: bool = false

func display(prompt: DialoguePrompt) -> void:
    if prompt.has_image_body():
        _body_image.texture = prompt.body_image
        _body_image.visible = true
        _body_text.visible = false
    else:
        _body_text.visible = true
        _body_image.visible = false
        _start_typewriter(prompt.body_text)
    for i in _cards.size():
        if i < prompt.answers.size():
            _cards[i].display(prompt.answers[i])
    _highlight_index = 1
    _refresh_highlight()

func _start_typewriter(text: String) -> void:
    _typing = true
    _body_text.text = ""
    var idx := 0
    while idx < text.length() and _typing:
        _body_text.text += text[idx]
        AudioBus.play_sfx("babble")
        idx += 1
        await get_tree().create_timer(1.0 / _typewriter_speed).timeout
    _typing = false

func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed("menu_left"):
        _highlight_index = 0
        _refresh_highlight()
    elif event.is_action_pressed("menu_up"):
        _highlight_index = 1
        _refresh_highlight()
    elif event.is_action_pressed("menu_right"):
        _highlight_index = 2
        _refresh_highlight()
    elif event.is_action_pressed("menu_confirm"):
        answer_submitted.emit(_cards[_highlight_index].outcome())

func _refresh_highlight() -> void:
    for i in _cards.size():
        _cards[i].set_highlighted(i == _highlight_index)
```

- [ ] **Step 4: Build RiddleBox scene**

`scenes/ui/riddle_box.tscn`:
- PanelContainer (root) `RiddleBox`, min size 1000×300
  - VBoxContainer `Layout`
    - PanelContainer `Body`, min size 1000×150
      - RichTextLabel `Text` (autowrap)
      - TextureRect `Image` (hidden by default)
    - HBoxContainer `Answers`
      - AnswerCard (instance) `Left`
      - AnswerCard (instance) `Middle`
      - AnswerCard (instance) `Right`

Attach scripts. Save.

- [ ] **Step 5: Commit**

```bash
git add scripts/ui/answer_card.gd scenes/ui/answer_card.tscn scripts/ui/riddle_box.gd scenes/ui/riddle_box.tscn
git commit -m "feat: add RiddleBox and AnswerCard with text+image content support"
```

### Task 4.6: Compose HUD on Gameplay scene

**Files:**
- Modify: `scenes/gameplay.tscn`
- Modify: `scripts/gameplay.gd`

- [ ] **Step 1: Add HUD instances to Gameplay scene**

In the editor, open `scenes/gameplay.tscn`. Build a layout:
- Control (root) `Gameplay`
  - HeartRow (instance) — anchored top-left, offset (24, 24)
  - ComboMeter (instance) — anchored top-left, offset (24, 100)
  - KnockdownMeter (instance) — anchored top-right, offset (-200, 24)
  - MatchTimerView (instance) — anchored top-center
  - RiddleBox (instance) — anchored center
  - Button `EndButton` — anchored bottom-right, "End Match (K)"

- [ ] **Step 2: Update Gameplay script to display a placeholder prompt**

```gdscript
extends Control

@onready var _riddle: RiddleBox = $RiddleBox

func _ready() -> void:
    Globals.last_played_tier = 1
    Globals.last_match_outcome = Globals.MatchOutcome.WIN
    $EndButton.pressed.connect(SceneRouter.goto_match_results)
    _show_placeholder_prompt()

func _show_placeholder_prompt() -> void:
    var prompt := DialoguePrompt.new()
    prompt.body_text = "[riddle goes here]"
    prompt.answers = [_a("wrong", Outcome.Type.WRONG), _a("neutral", Outcome.Type.NEUTRAL), _a("right", Outcome.Type.RIGHT)]
    _riddle.display(prompt)

func _a(text: String, outcome: int) -> DialogueAnswer:
    var a := DialogueAnswer.new()
    a.text = text
    a.outcome = outcome
    return a
```

Remove the existing End-match-on-K shortcut from `_unhandled_input` (the RiddleBox now consumes K).

- [ ] **Step 3: Run, verify the HUD**

Title → Start → Tofu → see full HUD: hearts, combo "x1", KD "0", timer "5:00", riddle box with placeholder text, three answer cards labeled "wrong/neutral/right". Press J/I/L to switch highlight. Press K — RiddleBox emits a signal we'll wire next milestone; for now end the match by clicking the End Match button.

- [ ] **Step 4: Commit**

```bash
git add scenes/gameplay.tscn scripts/gameplay.gd
git commit -m "feat: compose HUD on Gameplay scene with placeholder riddle"
```

### Manual Test for Milestone 4

- Enter Gameplay; visually confirm all 6 HUD regions are present at correct positions.
- RiddleBox shows placeholder text typed letter-by-letter.
- IJL switches the highlighted answer; the highlighted card has a yellow tint.

---

## Milestone 5: Match Clock and Round Transitions

**Goal:** Wire the `MatchClock` into the live `MatchTimerView`. When Round 1 hits 0:00, play "Round Over!" → "Ready?" → "Fight!" banners and reset to Round 2. End of Round 2 transitions to MatchResults with "Draw!".

**Manual test for this milestone:**
- Enter Gameplay. Timer counts down from 5:00.
- Console-shortcut F8 to fast-forward 280 seconds. Timer hits 0:00. "Round Over!" banner shows for ~3s. "Ready?" for ~1s. "Fight!" for ~1s. Round 2 begins at 5:00.
- F8 again. Round 2 ends. MatchResults shows "Draw!".

### Task 5.1: AnnouncementBanner scene

**Files:**
- Create: `scripts/ui/announcement_banner.gd`
- Create: `scenes/ui/announcement_banner.tscn`

- [ ] **Step 1: Implement the script**

```gdscript
class_name AnnouncementBanner
extends Control

@onready var _label: Label = $CenterContainer/Label

func _ready() -> void:
    visible = false

func show_message(message: String, duration_seconds: float) -> void:
    _label.text = message
    visible = true
    await get_tree().create_timer(duration_seconds).timeout
    visible = false
```

- [ ] **Step 2: Build the scene**

`scenes/ui/announcement_banner.tscn`:
- Control (root, full rect) `AnnouncementBanner`, mouse_filter = IGNORE
  - ColorRect `Backdrop` — full rect, black, alpha 0.4
  - CenterContainer `CenterContainer`
    - Label `Label` — text "", huge font (96pt)

- [ ] **Step 3: Commit**

```bash
git add scripts/ui/announcement_banner.gd scenes/ui/announcement_banner.tscn
git commit -m "feat: add AnnouncementBanner overlay component"
```

### Task 5.2: Wire MatchClock into Gameplay

**Files:**
- Modify: `scripts/gameplay.gd`
- Modify: `scenes/gameplay.tscn`

- [ ] **Step 1: Add AnnouncementBanner instance to Gameplay scene**

In editor, add AnnouncementBanner instance to `scenes/gameplay.tscn` as last child so it z-orders above everything.

- [ ] **Step 2: Wire clock + transitions into Gameplay script**

```gdscript
extends Control

@onready var _riddle: RiddleBox = $RiddleBox
@onready var _timer_view: MatchTimerView = $MatchTimerView
@onready var _banner: AnnouncementBanner = $AnnouncementBanner

var _clock := MatchClock.new()
var _transitioning: bool = false

func _ready() -> void:
    Globals.last_played_tier = 1
    Globals.last_match_outcome = Globals.MatchOutcome.DRAW
    $EndButton.pressed.connect(SceneRouter.goto_match_results)
    _show_placeholder_prompt()
    _start_round_one()

func _start_round_one() -> void:
    await _play_ready_fight()
    _clock.start()

func _process(delta: float) -> void:
    if _transitioning:
        return
    _clock.tick(delta)
    _timer_view.set_seconds(_clock.seconds_remaining())
    if _clock.is_round_over():
        _handle_round_end()
    if Input.is_action_just_pressed("ui_select") or Input.is_key_pressed(KEY_F8):
        _clock.tick(280.0)  # Debug fast-forward

func _handle_round_end() -> void:
    _transitioning = true
    _clock.pause()
    if _clock.current_round() >= MatchClock.TOTAL_ROUNDS:
        await _banner.show_message("Round Over!", 3.0)
        Globals.last_match_outcome = Globals.MatchOutcome.DRAW
        SceneRouter.goto_match_results()
        return
    await _banner.show_message("Round Over!", 3.0)
    _clock.advance_to_next_round()
    await _play_ready_fight()
    _clock.start()
    _transitioning = false

func _play_ready_fight() -> void:
    await _banner.show_message("Ready?", 1.0)
    await _banner.show_message("Fight!", 1.0)

func _show_placeholder_prompt() -> void:
    var prompt := DialoguePrompt.new()
    prompt.body_text = "[riddle goes here]"
    prompt.answers = [_a("wrong", Outcome.Type.WRONG), _a("neutral", Outcome.Type.NEUTRAL), _a("right", Outcome.Type.RIGHT)]
    _riddle.display(prompt)

func _a(text: String, outcome: int) -> DialogueAnswer:
    var a := DialogueAnswer.new()
    a.text = text
    a.outcome = outcome
    return a
```

- [ ] **Step 3: Add F8 fast-forward (proper input event)**

Refine the F8 handler to use `_unhandled_input` rather than polling in `_process` (cleaner):

Replace the `_process` body and add:

```gdscript
func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and event.keycode == KEY_F8:
        _clock.tick(280.0)
```

And remove the `Input.is_key_pressed(KEY_F8)` line from `_process`.

- [ ] **Step 4: Run and verify**

Open Gameplay. Watch the timer count down from 5:00 in real time. Press F8 — timer jumps to ~0:20, then runs to 0:00, then "Round Over!" → "Ready?" → "Fight!" banners play in order, Round 2 starts at 5:00. F8 again — same flow, ends with MatchResults showing "Draw!".

- [ ] **Step 5: Commit**

```bash
git add scripts/gameplay.gd scenes/gameplay.tscn
git commit -m "feat: drive Gameplay via MatchClock with round transitions and Draw outcome"
```

### Manual Test for Milestone 5

- Enter Gameplay, watch full timer countdown OR F8-fast-forward both rounds. Confirm:
  - Timer ticks every second.
  - Round 1 → "Round Over!" → "Ready?" → "Fight!" → Round 2.
  - Round 2 → "Round Over!" → MatchResults shows "Draw!".

---

## Milestone 6: Player Gloves and Opponent Rig (Idle State Only)

**Goal:** Compose the visual frame of the boxing scene. Player gloves in corners, opponent body + arms in center. All in idle state. Placeholder colored rectangles where art isn't ready.

**Manual test for this milestone:**
- Enter Gameplay; see boxing ring background (placeholder color), opponent rig centered, player gloves bottom-left and bottom-right.
- Resize the window — everything scales proportionally with the canvas.

### Task 6.1: PlayerGloves scene

**Files:**
- Create: `scripts/actors/player_gloves.gd`
- Create: `scenes/actors/player_gloves.tscn`

- [ ] **Step 1: Implement the script**

```gdscript
class_name PlayerGloves
extends Node2D

enum Side { LEFT, RIGHT }
enum State { IDLE, BLOCK, PUNCH }

@onready var _left: Sprite2D = $LeftGlove
@onready var _right: Sprite2D = $RightGlove

const _STATE_PREFIX := {
    State.IDLE: "idle",
    State.BLOCK: "block",
    State.PUNCH: "punch",
}

func _ready() -> void:
    set_state(Side.LEFT, State.IDLE)
    set_state(Side.RIGHT, State.IDLE)

func set_state(side: int, state: int) -> void:
    var sprite := _left if side == Side.LEFT else _right
    var side_token := "left" if side == Side.LEFT else "right"
    var path := "res://assets/sprites/player/player_glove_%s_%s.png" % [side_token, _STATE_PREFIX[state]]
    if ResourceLoader.exists(path):
        sprite.texture = load(path)
    else:
        sprite.texture = _placeholder()

func _placeholder() -> Texture2D:
    var img := Image.create(160, 160, false, Image.FORMAT_RGBA8)
    img.fill(Color(0.8, 0.6, 0.5))
    return ImageTexture.create_from_image(img)
```

- [ ] **Step 2: Build the scene**

`scenes/actors/player_gloves.tscn`:
- Node2D (root) `PlayerGloves`
  - Sprite2D `LeftGlove` — position (160, 920)
  - Sprite2D `RightGlove` — position (1760, 920)

- [ ] **Step 3: Commit**

```bash
git add scripts/actors/player_gloves.gd scenes/actors/player_gloves.tscn
git commit -m "feat: add PlayerGloves with idle/block/punch states and placeholder art"
```

### Task 6.2: Opponent scene (single-sprite swap)

> **Important architectural note (2026-05-17):** The opponent uses a **single body sprite** that gets swapped per action. There is no separate arm rig. Some directions are rendered by setting `flip_h = true` on the sprite (the canonical art is drawn for the gorilla's left side; mirroring covers the right side). See `CONTEXT.md` → "Mirroring Rules" for the authoritative mapping.

**Files:**
- Create: `scripts/actors/opponent.gd`
- Create: `scenes/actors/opponent.tscn`

- [ ] **Step 1: Implement the script**

```gdscript
class_name Opponent
extends Node2D

enum Action {
    IDLE,           # default + guard stance
    GUARD_DOWN,     # arms lowered after positive riddle
    KNOCKED_DOWN,   # KO'd
    TALKING,        # optional dialogue overlay
    SWING_HIGH,     # opponent telegraphs head punch (W defense)
    SWING_MID,      # opponent telegraphs body punch (S defense)
    SWING_LOW,      # opponent telegraphs hook punch (A or D defense)
    HIT_HIGH,       # player W-attack lands
    HIT_LOW,        # player A/S/D attack lands
}

enum Direction {
    LEFT,           # canonical sprite (designed for left-side action)
    RIGHT,          # flip_h = true (used for D-direction inputs)
}

const _ACTION_TOKEN := {
    Action.IDLE: "idle",
    Action.GUARD_DOWN: "guard_down",
    Action.KNOCKED_DOWN: "knocked_down",
    Action.TALKING: "talking",
    Action.SWING_HIGH: "swing_high",
    Action.SWING_MID: "swing_mid",
    Action.SWING_LOW: "swing_low",
    Action.HIT_HIGH: "hit_high",
    Action.HIT_LOW: "hit_low",
}

@onready var _sprite: Sprite2D = $Body

var _slug: String = "tofu"

func configure(opponent_slug: String) -> void:
    _slug = opponent_slug
    set_action(Action.IDLE)

func set_action(action: int, direction: int = Direction.LEFT) -> void:
    _sprite.texture = _load_texture(action)
    _sprite.flip_h = (direction == Direction.RIGHT)

func _load_texture(action: int) -> Texture2D:
    var token: String = _ACTION_TOKEN[action]
    var path := "res://assets/sprites/opponents/%s/opponent_%s_body_%s.png" % [_slug, _slug, token]
    if ResourceLoader.exists(path):
        return load(path)
    return _placeholder()

func _placeholder() -> Texture2D:
    var img := Image.create(360, 540, false, Image.FORMAT_RGBA8)
    img.fill(Color(0.3, 0.4, 0.7))
    return ImageTexture.create_from_image(img)
```

- [ ] **Step 2: Build the scene**

`scenes/actors/opponent.tscn`:
- Node2D (root) `Opponent`, position roughly centered horizontally (e.g. `(960, 400)`)
  - Sprite2D `Body` — centered at the Node2D's origin

That's the entire scene tree. No arm nodes.

- [ ] **Step 3: Commit**

```bash
git add scripts/actors/opponent.gd scenes/actors/opponent.tscn
git commit -m "feat: add Opponent single-sprite rig with action and direction setters"
```

### Direction Mapping (used by later milestones)

When later milestones need to drive opponent animation from a WASD direction, use this mapping. The `Opponent` script doesn't bundle this helper — callers (Gameplay) provide it because they own the WASD-to-Opponent-action policy.

```gdscript
# In gameplay.gd (will be added in M7/M10), helper:

func _opponent_defense_pose(wasd: int) -> Array:
    # Returns [Opponent.Action, Opponent.Direction]
    match wasd:
        SimonSequence.Direction.HEAD:  return [Opponent.Action.SWING_HIGH, Opponent.Direction.LEFT]
        SimonSequence.Direction.BODY:  return [Opponent.Action.SWING_MID, Opponent.Direction.LEFT]
        SimonSequence.Direction.LEFT:  return [Opponent.Action.SWING_LOW, Opponent.Direction.LEFT]
        SimonSequence.Direction.RIGHT: return [Opponent.Action.SWING_LOW, Opponent.Direction.RIGHT]
    return [Opponent.Action.IDLE, Opponent.Direction.LEFT]

func _opponent_hit_pose(wasd: int) -> Array:
    match wasd:
        SimonSequence.Direction.HEAD:  return [Opponent.Action.HIT_HIGH, Opponent.Direction.LEFT]
        SimonSequence.Direction.BODY:  return [Opponent.Action.HIT_LOW, Opponent.Direction.LEFT]
        SimonSequence.Direction.LEFT:  return [Opponent.Action.HIT_LOW, Opponent.Direction.LEFT]
        SimonSequence.Direction.RIGHT: return [Opponent.Action.HIT_LOW, Opponent.Direction.RIGHT]
    return [Opponent.Action.IDLE, Opponent.Direction.LEFT]
```

### Migration note for later milestones (M7, M10, M14)

The plan's later milestones were originally written against the old 3-part-rig API (`set_body`, `set_arm`, `BodyState`, `ArmSide`, `ArmState`). When implementing those milestones, translate as follows — the new API is the source of truth.

| Old call | New call |
|---|---|
| `_opponent.set_body(Opponent.BodyState.IDLE)` | `_opponent.set_action(Opponent.Action.IDLE)` |
| `_opponent.set_body(Opponent.BodyState.GUARD_DOWN)` | `_opponent.set_action(Opponent.Action.GUARD_DOWN)` |
| `_opponent.set_body(Opponent.BodyState.KNOCKED_DOWN)` | `_opponent.set_action(Opponent.Action.KNOCKED_DOWN)` |
| `_opponent.set_body(Opponent.BodyState.HURT)` | `_opponent.set_action(Opponent.Action.HIT_HIGH)` if W-attack, else `Action.HIT_LOW` (with `Direction.RIGHT` only for D-attack) |
| `_opponent.set_body(Opponent.BodyState.TALKING)` | `_opponent.set_action(Opponent.Action.TALKING)` |
| `_opponent.set_arm(side, ArmState.GUARD)` | no-op — `Action.IDLE` already represents the guard stance |
| `_opponent.set_arm(side, ArmState.DOWN)` | no-op — `Action.GUARD_DOWN` already represents both arms lowered |
| `_opponent.set_arm(side, ArmState.PUNCH_HEAD)` (M7 defense show) | `_opponent.set_action(Opponent.Action.SWING_HIGH)` |
| `_opponent.set_arm(side, ArmState.PUNCH_BODY)` | `_opponent.set_action(Opponent.Action.SWING_MID)` |
| `_opponent.set_arm(LEFT, ArmState.PUNCH_HOOK)` (A defense) | `_opponent.set_action(Opponent.Action.SWING_LOW, Opponent.Direction.LEFT)` |
| `_opponent.set_arm(RIGHT, ArmState.PUNCH_HOOK)` (D defense) | `_opponent.set_action(Opponent.Action.SWING_LOW, Opponent.Direction.RIGHT)` |

Anywhere the original plan called `set_arm` twice in a row (e.g. resetting both arms to GUARD), collapse to a single `set_action(Action.IDLE)` — the new sprite covers both arms in one frame.

### Task 6.3: Add background and actors to Gameplay

**Files:**
- Modify: `scenes/gameplay.tscn`
- Modify: `scripts/gameplay.gd`

- [ ] **Step 1: Add scene-tree changes**

In the editor, edit `scenes/gameplay.tscn`. Insert beneath the root, before the HUD nodes:
- ColorRect `Background` — full rect, color (0.15, 0.1, 0.1) — will be replaced by `bg_ring.png` later
- Opponent (instance) `Opponent`
- PlayerGloves (instance) `PlayerGloves`

The HUD and AnnouncementBanner nodes should remain on top (higher in tree order).

- [ ] **Step 2: Configure opponent on `_ready`**

Update `scripts/gameplay.gd`:

```gdscript
@onready var _opponent: Opponent = $Opponent

func _ready() -> void:
    Globals.last_played_tier = 1
    Globals.last_match_outcome = Globals.MatchOutcome.DRAW
    _opponent.configure("tofu")
    $EndButton.pressed.connect(SceneRouter.goto_match_results)
    _show_placeholder_prompt()
    _start_round_one()
```

- [ ] **Step 3: Run, confirm visuals**

Enter Gameplay. See dark red background, the Tofu idle body sprite centered (or a blue placeholder rectangle if the art isn't on disk), two glove sprites (or tan placeholders) in the bottom corners, full HUD on top. No arms — the opponent is a single body sprite.

- [ ] **Step 4: Commit**

```bash
git add scenes/gameplay.tscn scripts/gameplay.gd
git commit -m "feat: compose background, opponent, and player gloves on Gameplay"
```

### Manual Test for Milestone 6

- Enter Gameplay. Visually confirm: background, single opponent body sprite centered, player gloves in corners, HUD on top.
- Resize the window. Confirm everything scales (no UI elements clip or distort).

---

## Cross-Cutting Thread: Riddle Encounter Visibility

> **Added 2026-05-17** after a `/grill-with-docs` session decided the riddle should appear/disappear in discrete encounter windows rather than being visible for the entire match. See `CONTEXT.md` → "Riddle Encounter" / "Riddle Gap" / "Gap Timing Rules" for the authoritative model.

This thread is *not* a standalone milestone. The work is distributed across M7, M8, M9, M10, and M14 because each piece depends on the event source for its gap trigger being wired first. The full encounter-visibility surface is only complete once all five milestones land.

### Pacing constants (introduce in M7)

When the first encounter-visibility task lands in M7, also create a single source-of-truth file for the timing numbers so later milestones reference the same constants:

```gdscript
# scripts/match_pacing.gd
class_name MatchPacing

# Riddle gap durations, in seconds. See CONTEXT.md → "Riddle Gap".
const FRESH_START_GAP := 3.0
const FRESH_START_DEAD_AIR := 1.0   # Front portion of FRESH_START_GAP with Simon defense paused
const BREATHER_GAP := 4.0

# Knockdown pause, in seconds. See CONTEXT.md → "Match" + "Knockdown".
const KNOCKDOWN_PAUSE := 5.0
```

Subsequent milestones import these constants by name; no other file should hardcode `3.0`, `4.0`, etc.

### Per-milestone sub-tasks (cross-references)

| Milestone | Encounter-visibility sub-task |
|---|---|
| **M7** | Hide riddle during all banner sequences (Ready/Fight + Round Over). Implement Fresh-Start Gap at Round 1 start and Round 2 start (3s gap, with the first 1s being dead air where Simon defense is paused and the opponent stays in `Action.IDLE`). Add the `MatchPacing` constants script. After the gap completes, the existing `_show_placeholder_prompt()` runs and the riddle snaps in. |
| **M8** | When the player takes Simon damage during Repeat Phase: snap-hide the riddle and start a 4s Breather Gap. Simon defense continues (the new shorter sequence's show phase begins immediately during the gap). The riddle reappears after 4s with the *next* prompt from the deck (or with the same prompt if M9 hasn't landed yet). New Simon damage events during the gap *reset* the 4s timer (rule (v)). |
| **M9** | When the player K-presses an answer: snap-hide the riddle. `wrong` → 4s Breather Gap (snap-clear leftover Simon visuals + opponent punch animation coinciding with the heart drop); `neutral` → 1.5s "Try again!" banner + same-length Simon replay (same prompt, answer cards reshuffle); `right` → Attack Phase entry (M10 handles gap on exit). New events during the 4s reset the timer. |
| **M10** | On attack-phase entry: confirm the riddle is hidden (it was hidden at K-press in M9, but assert/guard against re-show). On attack-phase exit (non-knockdown): start a 4s Breather Gap, snap-show next prompt after. On attack-phase exit *with* knockdown: pause the match clock for `KNOCKDOWN_PAUSE` seconds, play the Knock Down banner / knocked_down sprite, then resume the clock and start a Fresh-Start Gap (3s, with 1s dead air) before snapping the next riddle in. |
| **M14** | Polish pass — verify all five encounter-visibility transitions feel right under real play. If a fade animation is decided on (vs the snap default), wire it here. Verify `body_talking` cue is NOT wired (per the (B)-encounter framing reversibility plan; only add it later if we commit to (B) for good). |

### Implementation notes shared across milestones

- **State machine:** Gameplay needs a single source of truth for "is a riddle visible right now?" — recommend a small enum like `RiddleVisibility { ENCOUNTER, FRESH_START_GAP, BREATHER_GAP }` and a single `Timer` node that fires the next show. Avoid distributed timers across multiple controllers.
- **Encounter end is event-driven, not time-driven.** An encounter does not end on its own timer — it ends only when an event fires (K-press, Simon damage, attack-phase entry, round end). Gaps end on a timer; encounters end on events.
- **The 1s dead air** is special: only Fresh-Start Gaps have it, and only the first second. During dead air, the opponent must be in `Action.IDLE` and no WASD prompts may flash. After dead air ends inside the Fresh-Start Gap, Simon's show phase can begin even though the riddle is still hidden (2 more seconds).
- **`_show_placeholder_prompt()` in `scripts/gameplay.gd:69`** currently runs in `_ready` and stays visible the whole match. M7 should defer that call until after the first Fresh-Start Gap completes.
- **Round transition banners.** M5 already hides the riddle on `_handle_round_end` (line 45) and re-shows it after the next Ready/Fight (line 57). M7 should refine this so the re-show is *gated by the Fresh-Start Gap* — the riddle does not reappear immediately after the Fight! banner; it waits 3s.

---

## Milestone 7: Defense Simon Show Phase (No Player Input)

**Goal:** The Opponent telegraphs punches by flashing WASD prompts over their body in a Simon sequence. The sequence grows over time on a loop. No player interaction yet.

**Manual test for this milestone:**
- Enter Gameplay. After "Fight!", watch the opponent flash a 1-input prompt (e.g. W over their head). After ~2 seconds, the chain extends and they flash a 2-input sequence (W then A). Then 3, 4, etc. Opponent's arms also animate in sync with each prompt.

### Task 7.1: WasdPrompt scene

**Files:**
- Create: `scripts/ui/wasd_prompt.gd`
- Create: `scenes/ui/wasd_prompt.tscn`

- [ ] **Step 1: Implement the script**

```gdscript
class_name WasdPrompt
extends Control

@onready var _label: Label = $Label
@onready var _bg: ColorRect = $Background

func show_direction(direction: int) -> void:
    var token := _token_for(direction)
    _label.text = token.to_upper()
    var path := "res://assets/sprites/ui/prompt_%s.png" % token
    if ResourceLoader.exists(path):
        var tex := load(path)
        $Image.texture = tex
        $Image.visible = true
        _label.visible = false
        _bg.visible = false
    else:
        $Image.visible = false
        _label.visible = true
        _bg.visible = true
    visible = true

func hide_prompt() -> void:
    visible = false

func _token_for(direction: int) -> String:
    match direction:
        SimonSequence.Direction.HEAD: return "w"
        SimonSequence.Direction.LEFT: return "a"
        SimonSequence.Direction.BODY: return "s"
        SimonSequence.Direction.RIGHT: return "d"
    return ""
```

- [ ] **Step 2: Build the scene**

`scenes/ui/wasd_prompt.tscn`:
- Control (root) `WasdPrompt`, min size 120×120
  - ColorRect `Background` — full rect, color yellow, alpha 0.7
  - Label `Label` — center, huge font
  - TextureRect `Image` — full rect, hidden

- [ ] **Step 3: Commit**

```bash
git add scripts/ui/wasd_prompt.gd scenes/ui/wasd_prompt.tscn
git commit -m "feat: add WasdPrompt component (image with text fallback)"
```

### Task 7.2: WasdPromptLayer manages 4 prompts positioned on the opponent

**Files:**
- Create: `scripts/ui/wasd_prompt_layer.gd`
- Create: `scenes/ui/wasd_prompt_layer.tscn`

- [ ] **Step 1: Implement the script**

```gdscript
class_name WasdPromptLayer
extends Control

@onready var _prompts: Dictionary = {
    SimonSequence.Direction.HEAD: $Head,
    SimonSequence.Direction.LEFT: $Left,
    SimonSequence.Direction.BODY: $Body,
    SimonSequence.Direction.RIGHT: $Right,
}

func _ready() -> void:
    hide_all()

func flash(direction: int, duration_seconds: float) -> void:
    var prompt: WasdPrompt = _prompts[direction]
    prompt.show_direction(direction)
    await get_tree().create_timer(duration_seconds).timeout
    prompt.hide_prompt()

func hide_all() -> void:
    for p in _prompts.values():
        p.hide_prompt()
```

- [ ] **Step 2: Build the scene**

`scenes/ui/wasd_prompt_layer.tscn`:
- Control (root) `WasdPromptLayer`, full rect, mouse_filter = IGNORE
  - WasdPrompt (instance) `Head` — position relative to opponent's head (centered around x=960, y=200)
  - WasdPrompt (instance) `Left` — position (760, 400)
  - WasdPrompt (instance) `Body` — position (960, 400)
  - WasdPrompt (instance) `Right` — position (1160, 400)

- [ ] **Step 3: Commit**

```bash
git add scripts/ui/wasd_prompt_layer.gd scenes/ui/wasd_prompt_layer.tscn
git commit -m "feat: add WasdPromptLayer placing prompts over opponent body"
```

### Task 7.3: DefensePhase controller — show phase loop

**Files:**
- Create: `scripts/game/defense_phase.gd`
- Modify: `scenes/gameplay.tscn`
- Modify: `scripts/gameplay.gd`

- [ ] **Step 1: Add the controller**

```gdscript
class_name DefensePhase
extends Node

signal show_started(steps: Array)
signal show_completed
signal step_flashed(direction: int)

@export var step_seconds: float = 0.8
@export var gap_seconds: float = 0.25
@export var interlude_seconds: float = 0.6

var _sequence: SimonSequence = SimonSequence.new()
var _running: bool = false

func start() -> void:
    _sequence.reset()
    _running = true
    _next_round()

func stop() -> void:
    _running = false

func current_steps() -> Array:
    return _sequence.steps()

func _next_round() -> void:
    if not _running:
        return
    _sequence.extend()
    await get_tree().create_timer(interlude_seconds).timeout
    show_started.emit(_sequence.steps())
    for step in _sequence.steps():
        if not _running:
            return
        step_flashed.emit(step)
        await get_tree().create_timer(step_seconds).timeout
        if not _running:
            return
        await get_tree().create_timer(gap_seconds).timeout
    show_completed.emit()
    if _running:
        _next_round()  # First-pass loop: skip repeat phase, just keep showing.
```

- [ ] **Step 2: Add WasdPromptLayer to Gameplay**

In the editor, add a WasdPromptLayer instance to `scenes/gameplay.tscn` above the HUD nodes (so it z-orders below the AnnouncementBanner but above the actors).

- [ ] **Step 3: Wire DefensePhase in Gameplay**

```gdscript
@onready var _prompts: WasdPromptLayer = $WasdPromptLayer

var _defense := DefensePhase.new()

func _ready() -> void:
    Globals.last_played_tier = 1
    Globals.last_match_outcome = Globals.MatchOutcome.DRAW
    _opponent.configure("tofu")
    add_child(_defense)
    _defense.step_flashed.connect(_on_step_flashed)
    $EndButton.pressed.connect(SceneRouter.goto_match_results)
    _show_placeholder_prompt()
    _start_round_one()

func _start_round_one() -> void:
    await _play_ready_fight()
    _clock.start()
    _defense.start()

func _on_step_flashed(direction: int) -> void:
    _prompts.flash(direction, _defense.step_seconds)
    _animate_opponent_punch(direction)

func _animate_opponent_punch(direction: int) -> void:
    match direction:
        SimonSequence.Direction.HEAD:
            _opponent.set_arm(Opponent.ArmSide.RIGHT, Opponent.ArmState.PUNCH_HEAD)
        SimonSequence.Direction.BODY:
            _opponent.set_arm(Opponent.ArmSide.RIGHT, Opponent.ArmState.PUNCH_BODY)
        SimonSequence.Direction.LEFT:
            _opponent.set_arm(Opponent.ArmSide.LEFT, Opponent.ArmState.PUNCH_HOOK)
        SimonSequence.Direction.RIGHT:
            _opponent.set_arm(Opponent.ArmSide.RIGHT, Opponent.ArmState.PUNCH_HOOK)
    await get_tree().create_timer(_defense.step_seconds).timeout
    _opponent.set_arm(Opponent.ArmSide.LEFT, Opponent.ArmState.GUARD)
    _opponent.set_arm(Opponent.ArmSide.RIGHT, Opponent.ArmState.GUARD)
```

Also extend `_handle_round_end()` to call `_defense.stop()` before the banner.

- [ ] **Step 4: Run, observe show phase**

After "Fight!", watch the opponent flash 1 prompt → pause → flash 2 prompts → pause → flash 3 → etc. Arms animate in sync. Chain grows indefinitely. F8 still fast-forwards rounds.

- [ ] **Step 5: Commit**

```bash
git add scripts/game/defense_phase.gd scripts/gameplay.gd scenes/gameplay.tscn
git commit -m "feat: add DefensePhase show-phase loop with arm animation sync"
```

### Manual Test for Milestone 7

- After "Fight!", watch the opponent's show phase. Confirm:
  - Chain starts at length 1 and grows by 1 each cycle.
  - WASD prompts appear at the correct positions (W over head, A left, S body, D right).
  - Opponent arm animates in time with each prompt.
  - Loop continues until round end.

---

## Milestone 8: Defense Simon Repeat Phase and Damage

**Goal:** After the show phase, the player must reproduce the sequence with WASD. Wrong key or 3s timeout = punch lands, lose a heart, chain resets. Hearts at 0 ends match with "You Lose!".

**Manual test for this milestone:**
- After "Fight!", show phase plays. The player can then enter the sequence. Correct sequence → next show. Wrong key → screen visibly registers a hit (placeholder for FX), heart row drops by 1, chain restarts at length 1.
- After 5 mistakes the match ends with "You Lose!" and MatchResults shows the same.

### Task 8.1: Extend DefensePhase with repeat phase + signals

**Files:**
- Modify: `scripts/game/defense_phase.gd`
- Create/modify: `tests/unit/test_defense_phase.gd` (lightweight — signal-driven)

- [ ] **Step 1: Write tests for the signal contract**

```gdscript
extends GutTest

func test_correct_input_emits_step_blocked():
    var d := DefensePhase.new()
    d.step_seconds = 0.01
    d.gap_seconds = 0.01
    d.interlude_seconds = 0.01
    add_child_autoqfree(d)
    var seen := false
    d.step_blocked.connect(func(_idx): seen = true)
    # Force a known sequence
    d._sequence.seed_rng(1)
    d._sequence.reset()
    d._sequence.extend()
    var step: int = d._sequence.steps()[0]
    d.begin_repeat_phase()
    d.player_input(step)
    assert_true(seen)

func test_wrong_input_emits_damage_taken():
    var d := DefensePhase.new()
    add_child_autoqfree(d)
    var emitted := false
    d.damage_taken.connect(func(): emitted = true)
    d._sequence.seed_rng(1)
    d._sequence.extend()
    var step: int = d._sequence.steps()[0]
    var wrong := SimonSequence.Direction.HEAD
    if step == SimonSequence.Direction.HEAD:
        wrong = SimonSequence.Direction.BODY
    d.begin_repeat_phase()
    d.player_input(wrong)
    assert_true(emitted)
```

- [ ] **Step 2: Refactor `DefensePhase`**

```gdscript
class_name DefensePhase
extends Node

signal show_started(steps: Array)
signal show_completed
signal step_flashed(direction: int)
signal repeat_started
signal step_blocked(index: int)
signal sequence_completed
signal damage_taken

@export var step_seconds: float = 0.8
@export var gap_seconds: float = 0.25
@export var interlude_seconds: float = 0.6
@export var input_window_seconds: float = 3.0

var _sequence: SimonSequence = SimonSequence.new()
var _running: bool = false
var _expected_index: int = 0
var _repeat_active: bool = false
var _timeout_timer: Timer

func _ready() -> void:
    _timeout_timer = Timer.new()
    _timeout_timer.one_shot = true
    _timeout_timer.timeout.connect(_on_input_timeout)
    add_child(_timeout_timer)

func start() -> void:
    _sequence.reset()
    _running = true
    _begin_next_round()

func stop() -> void:
    _running = false
    _repeat_active = false
    _timeout_timer.stop()

func begin_repeat_phase() -> void:
    _expected_index = 0
    _repeat_active = true
    repeat_started.emit()
    _timeout_timer.start(input_window_seconds)

func player_input(direction: int) -> void:
    if not _repeat_active:
        return
    if _sequence.validate_at(_expected_index, direction):
        step_blocked.emit(_expected_index)
        _expected_index += 1
        if _expected_index >= _sequence.length():
            _repeat_active = false
            _timeout_timer.stop()
            sequence_completed.emit()
            if _running:
                _begin_next_round()
        else:
            _timeout_timer.start(input_window_seconds)
    else:
        _fail_with_damage()

func _on_input_timeout() -> void:
    if _repeat_active:
        _fail_with_damage()

func _fail_with_damage() -> void:
    _repeat_active = false
    _timeout_timer.stop()
    damage_taken.emit()
    _sequence.reset()
    if _running:
        _begin_next_round()

func _begin_next_round() -> void:
    if not _running:
        return
    _sequence.extend()
    await get_tree().create_timer(interlude_seconds).timeout
    show_started.emit(_sequence.steps())
    for step in _sequence.steps():
        if not _running:
            return
        step_flashed.emit(step)
        await get_tree().create_timer(step_seconds).timeout
        if not _running:
            return
        await get_tree().create_timer(gap_seconds).timeout
    show_completed.emit()
    if _running:
        begin_repeat_phase()

func current_sequence() -> SimonSequence:
    return _sequence
```

- [ ] **Step 3: Run tests, fix until green**
- [ ] **Step 4: Commit**

```bash
git add scripts/game/defense_phase.gd tests/unit/test_defense_phase.gd
git commit -m "feat: add DefensePhase repeat phase with timeout and damage signals"
```

### Task 8.2: Wire repeat phase into Gameplay

**Files:**
- Modify: `scripts/gameplay.gd`

- [ ] **Step 1: Add Hearts state and wire signals**

```gdscript
var _hearts := Hearts.new()

func _ready() -> void:
    Globals.last_played_tier = 1
    Globals.last_match_outcome = Globals.MatchOutcome.DRAW
    _opponent.configure("tofu")
    add_child(_defense)
    _defense.step_flashed.connect(_on_step_flashed)
    _defense.step_blocked.connect(_on_step_blocked)
    _defense.damage_taken.connect(_on_damage_taken)
    $EndButton.pressed.connect(SceneRouter.goto_match_results)
    _show_placeholder_prompt()
    _refresh_heart_row()
    _start_round_one()

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and event.keycode == KEY_F8:
        _clock.tick(280.0)
        return
    if event.is_action_pressed("attack_head"):
        _defense.player_input(SimonSequence.Direction.HEAD)
    elif event.is_action_pressed("attack_left"):
        _defense.player_input(SimonSequence.Direction.LEFT)
    elif event.is_action_pressed("attack_body"):
        _defense.player_input(SimonSequence.Direction.BODY)
    elif event.is_action_pressed("attack_right"):
        _defense.player_input(SimonSequence.Direction.RIGHT)

func _on_step_blocked(index: int) -> void:
    AudioBus.play_sfx("block")
    # Animate player glove into block pose
    var direction: int = _defense.current_sequence().steps()[index]
    var side := PlayerGloves.Side.LEFT if direction in [SimonSequence.Direction.LEFT, SimonSequence.Direction.BODY] else PlayerGloves.Side.RIGHT
    $PlayerGloves.set_state(side, PlayerGloves.State.BLOCK)
    await get_tree().create_timer(0.15).timeout
    $PlayerGloves.set_state(side, PlayerGloves.State.IDLE)

func _on_damage_taken() -> void:
    _hearts.take_damage()
    AudioBus.play_sfx("hurt")
    _refresh_heart_row()
    _opponent.set_body(Opponent.BodyState.IDLE)  # Reset
    if _hearts.is_empty():
        _end_match_loss()

func _refresh_heart_row() -> void:
    $HeartRow.set_hearts(_hearts.current())

func _end_match_loss() -> void:
    _transitioning = true
    _clock.pause()
    _defense.stop()
    await _banner.show_message("You Lose!", 3.0)
    Globals.last_match_outcome = Globals.MatchOutcome.LOSE
    SceneRouter.goto_match_results()
```

- [ ] **Step 2: Run and play**

Enter Gameplay. After Fight!, show phase plays. Try to repeat sequence:
- Correct → glove animates, chain grows.
- Wrong / timeout → heart row drops, chain resets.
- 5 wrong → "You Lose!" banner → MatchResults shows "You Lose!".

- [ ] **Step 3: Commit**

```bash
git add scripts/gameplay.gd
git commit -m "feat: wire WASD input to defense repeat phase and heart damage"
```

### Manual Test for Milestone 8

- Play defense alone: deliberately block correctly several rounds, watch chain grow.
- Deliberately fail: confirm heart loss, chain reset.
- Deliberately fail 5 times: confirm "You Lose!" and MatchResults.

---

## Milestone 9: Dialogue and Riddles

**Goal:** RiddleBox is fed by a `DialogueDeck`. Player answers via IJKL. `WRONG` deals damage and resets defense chain. `NEUTRAL` advances to next prompt. `RIGHT` triggers a placeholder "would-be-attack-phase" event (next milestone wires the attack proper). Placeholder dialogue deck per opponent contains 5 prompts.

**Manual test for this milestone:**
- Enter Gameplay. Riddle box shows real (placeholder-text) prompt. Press J/I/L to highlight an answer card.
- Submit "wrong" → see heart drop, defense chain resets, new prompt appears.
- Submit "neutral" → new prompt appears, no other effect.
- Submit "right" → "Attack window!" banner flashes for 1s and new prompt appears (full attack mechanics next milestone).

### Task 9.1: Placeholder dialogue resources

**Files:**
- Create: `data/dialogue/tofu.tres` (and similar for minty/sebastian)
- Create: `scripts/game/dialogue_set.gd` — wraps a deck for serialization

- [ ] **Step 1: Create a DialogueSet resource type**

```gdscript
class_name DialogueSet
extends Resource

@export var prompts: Array[DialoguePrompt] = []
```

- [ ] **Step 2: Author placeholder data for Tofu**

In the editor: New Resource → DialogueSet. For `tofu.tres`, add 5 DialoguePrompt entries. Each has:
- `body_text` = "Placeholder dialogue line {N}." (substitute 1..5)
- 3 DialogueAnswer entries with `text = "wrong"/"neutral"/"right"` and matching outcome.

Save as `data/dialogue/tofu.tres`. Duplicate for `minty.tres` and `sebastian.tres` (same placeholder content for now — the user authors real dialogue separately).

- [ ] **Step 3: Commit**

```bash
git add scripts/game/dialogue_set.gd data/dialogue/
git commit -m "feat: add DialogueSet resource and placeholder data for all opponents"
```

### Task 9.2: Wire DialogueDeck into Gameplay

**Files:**
- Modify: `scripts/gameplay.gd`

- [ ] **Step 1: Load and feed deck**

```gdscript
var _deck := DialogueDeck.new()
var _current_prompt: DialoguePrompt

func _ready() -> void:
    Globals.last_played_tier = 1
    Globals.last_match_outcome = Globals.MatchOutcome.DRAW
    _opponent.configure("tofu")
    add_child(_defense)
    _defense.step_flashed.connect(_on_step_flashed)
    _defense.step_blocked.connect(_on_step_blocked)
    _defense.damage_taken.connect(_on_damage_taken)
    var dialogue_set: DialogueSet = load("res://data/dialogue/tofu.tres")
    _deck.load_prompts(dialogue_set.prompts)
    _riddle.answer_submitted.connect(_on_answer_submitted)
    $EndButton.pressed.connect(SceneRouter.goto_match_results)
    _refresh_heart_row()
    _show_next_prompt()
    _start_round_one()

func _show_next_prompt() -> void:
    _current_prompt = _deck.draw()
    if _current_prompt:
        _riddle.display(_current_prompt)

func _on_answer_submitted(outcome: int) -> void:
    match outcome:
        Outcome.Type.WRONG:
            _take_riddle_damage()
        Outcome.Type.NEUTRAL:
            _show_next_prompt_after_beat()
        Outcome.Type.RIGHT:
            _trigger_attack_window_placeholder()

func _take_riddle_damage() -> void:
    _defense.stop()
    _on_damage_taken()
    _show_next_prompt_after_beat()
    if not _hearts.is_empty():
        _defense.start()

func _show_next_prompt_after_beat() -> void:
    await get_tree().create_timer(0.5).timeout
    _show_next_prompt()

func _trigger_attack_window_placeholder() -> void:
    await _banner.show_message("Attack Window!", 1.0)
    _show_next_prompt()
```

- [ ] **Step 2: Reset deck on round transition**

Inside `_handle_round_end()`, after `_clock.advance_to_next_round()`, add:
```gdscript
_deck.reset()
_show_next_prompt()
```

- [ ] **Step 3: Run and verify**

Each outcome behaves as designed.

- [ ] **Step 4: Commit**

```bash
git add scripts/gameplay.gd
git commit -m "feat: wire DialogueDeck and RiddleBox outcomes into gameplay"
```

### Manual Test for Milestone 9

- Submit each outcome at least once: verify damage on wrong, no effect on neutral, "Attack Window!" placeholder on right.
- Continue playing until deck is exhausted (5 prompts). Confirm deck reshuffles (real prompts reappear).
- Trigger round end (F8). Confirm deck resets and a fresh prompt appears in Round 2.

---

## Milestone 10: Attack Phase

**Goal:** A `RIGHT` answer enters an Attack Phase: opponent goes guard_down, defense stops, an attack Simon sequence plays (show + repeat). Successful completion advances combo. Failure returns to defense with combo preserved. Reaching x3 + successful attack = Knockdown sequence.

**Manual test for this milestone:**
- Submit "right" answer. Opponent goes guard_down. WASD prompts flash an attack sequence (1 step at combo x1). Repeat correctly → combo becomes x2, return to defense. Next "right" → 2-step sequence, complete → x3, return to defense. Next "right" → 3-step sequence, complete → Knockdown banner, knockdown meter increments to 1, opponent shown knocked_down for 5s, then resumes. Combo resets to x1, defense Simon chain resets to length 1.
- Repeat until 3 knockdowns → "Knock Out!" → "You Win!".

### Task 10.1: AttackPhase controller (TDD where feasible)

**Files:**
- Create: `scripts/game/attack_phase.gd`
- Create: `tests/unit/test_attack_phase.gd`

- [ ] **Step 1: Write tests**

```gdscript
extends GutTest

func test_attack_phase_uses_combo_input_count():
    var a := AttackPhase.new()
    a.step_seconds = 0.01
    a.gap_seconds = 0.01
    a.input_window_seconds = 10.0
    add_child_autoqfree(a)
    a.begin(2)
    assert_eq(a.expected_inputs(), 2)

func test_complete_sequence_emits_success():
    var a := AttackPhase.new()
    a.step_seconds = 0.001
    a.gap_seconds = 0.001
    a.input_window_seconds = 10.0
    add_child_autoqfree(a)
    var done := false
    a.attack_succeeded.connect(func(): done = true)
    a.begin(1)
    await get_tree().create_timer(0.1).timeout
    var step: int = a._sequence.steps()[0]
    a.player_input(step)
    assert_true(done)

func test_wrong_input_emits_failure():
    var a := AttackPhase.new()
    add_child_autoqfree(a)
    var failed := false
    a.attack_failed.connect(func(): failed = true)
    a.begin(1)
    await get_tree().create_timer(0.1).timeout
    var step: int = a._sequence.steps()[0]
    var wrong := SimonSequence.Direction.HEAD if step != SimonSequence.Direction.HEAD else SimonSequence.Direction.BODY
    a.player_input(wrong)
    assert_true(failed)
```

- [ ] **Step 2: Implement AttackPhase**

```gdscript
class_name AttackPhase
extends Node

signal show_started(steps: Array)
signal step_flashed(direction: int)
signal repeat_started
signal step_landed(index: int)
signal attack_succeeded
signal attack_failed

@export var step_seconds: float = 0.8
@export var gap_seconds: float = 0.25
@export var interlude_seconds: float = 0.5
@export var input_window_seconds: float = 3.0

var _sequence: SimonSequence = SimonSequence.new()
var _expected_index: int = 0
var _repeat_active: bool = false
var _timeout_timer: Timer
var _expected_count: int = 1

func _ready() -> void:
    _timeout_timer = Timer.new()
    _timeout_timer.one_shot = true
    _timeout_timer.timeout.connect(_on_input_timeout)
    add_child(_timeout_timer)

func begin(input_count: int) -> void:
    _expected_count = input_count
    _sequence.reset()
    for i in input_count:
        _sequence.extend()
    _show()

func expected_inputs() -> int:
    return _expected_count

func current_sequence() -> SimonSequence:
    return _sequence

func _show() -> void:
    await get_tree().create_timer(interlude_seconds).timeout
    show_started.emit(_sequence.steps())
    for step in _sequence.steps():
        step_flashed.emit(step)
        await get_tree().create_timer(step_seconds).timeout
        await get_tree().create_timer(gap_seconds).timeout
    _begin_repeat()

func _begin_repeat() -> void:
    _expected_index = 0
    _repeat_active = true
    repeat_started.emit()
    _timeout_timer.start(input_window_seconds)

func player_input(direction: int) -> void:
    if not _repeat_active:
        return
    if _sequence.validate_at(_expected_index, direction):
        step_landed.emit(_expected_index)
        _expected_index += 1
        if _expected_index >= _sequence.length():
            _repeat_active = false
            _timeout_timer.stop()
            attack_succeeded.emit()
        else:
            _timeout_timer.start(input_window_seconds)
    else:
        _fail()

func _on_input_timeout() -> void:
    if _repeat_active:
        _fail()

func _fail() -> void:
    _repeat_active = false
    _timeout_timer.stop()
    attack_failed.emit()
```

- [ ] **Step 3: Run tests, fix until green**
- [ ] **Step 4: Commit**

```bash
git add scripts/game/attack_phase.gd tests/unit/test_attack_phase.gd
git commit -m "feat: add AttackPhase controller with success/failure signals"
```

### Task 10.2: Wire AttackPhase into Gameplay

**Files:**
- Modify: `scripts/gameplay.gd`
- Modify: `scripts/match_pacing.gd`

> **Stale-API gotchas this section already accounts for** (do not re-introduce):
> - `Opponent.BodyState` / `Opponent.set_body(…)` are retired — use `Opponent.Action` / `Opponent.set_action(action, direction = LEFT)`. The migration table earlier in this plan is the source of truth.
> - The M9 polish pass inlined the WRONG and NEUTRAL outcome branches directly into `_on_answer_submitted`. `_take_riddle_damage()` and `_show_next_prompt_after_beat()` do **not** exist. Splice the new RIGHT branch into the existing match statement — do not rewrite the function.
> - `_show_next_prompt()` already sets `_current_prompt` (M9). Don't re-introduce a local-only version.
> - Bare timing literals (`0.1`, `2.0`, `3.0`, `5.0`) are forbidden — every pause is a named `MatchPacing` constant or a local `const _*_SECONDS`, matching the M8/M9 convention (`_BLOCK_FLASH_SECONDS`, `_DAMAGE_HIT_SECONDS`, `MatchPacing.READY_BANNER`, etc.).
> - Attack-phase exit routes through the existing gap helpers. Non-knockdown exit → `_begin_breather_gap()` (4s, riddle hidden, defense already running). Knockdown exit, after the clock resumes → `_begin_fresh_start_gap()` (CONTEXT.md: "immediately after a knockdown's clock pause ends" is one of the three Fresh-Start Gap triggers).
> - Three-part arm rig is gone. Anything that wanted "arms down" is now part of `Action.GUARD_DOWN`. Do not call `set_arm(…)`.

- [ ] **Step 0: Add MatchPacing constants for the attack/knockdown beat**

Append to `scripts/match_pacing.gd`:

```gdscript
# Attack phase and knockdown timings, in seconds. See CONTEXT.md → "Attack Phase" + "Knockdown".
const KNOCK_DOWN_BANNER := 2.0
const KNOCK_OUT_BANNER := 2.0
const YOU_WIN_BANNER := 2.0
```

`MatchPacing.KNOCKDOWN_PAUSE` (5.0) already exists and remains the total clock-pause duration during a knockdown.

- [ ] **Step 1: Wire the attack-phase state into `scripts/gameplay.gd`**

Add module-level fields next to `_clock`, `_hearts`, `_defense`:

```gdscript
var _combo := ComboState.new()
var _knockdowns := Knockdowns.new()
var _attack: AttackPhase
var _in_attack: bool = false
```

Add `@onready` references for the meters (the scene already has `$ComboMeter` and `$KnockdownMeter` from Task 6.3):

```gdscript
@onready var _combo_meter: ComboMeter = $ComboMeter
@onready var _knockdown_meter: KnockdownMeter = $KnockdownMeter
```

Add a punch-flash constant next to `_BLOCK_FLASH_SECONDS` (mirror the block timing for a matched feel):

```gdscript
const _PUNCH_FLASH_SECONDS := 0.15
```

In `_ready()`, after the existing `_defense` wiring, before `_start_round_one()`:

```gdscript
_attack = AttackPhase.new()
add_child(_attack)
_attack.step_flashed.connect(_on_attack_step_flashed)
_attack.step_landed.connect(_on_attack_step_landed)
_attack.attack_succeeded.connect(_on_attack_succeeded)
_attack.attack_failed.connect(_on_attack_failed)
_refresh_combo_meter()
_refresh_knockdown_meter()
```

Helpers:

```gdscript
func _refresh_combo_meter() -> void:
    _combo_meter.set_level(_combo.level())

func _refresh_knockdown_meter() -> void:
    _knockdown_meter.set_count(_knockdowns.count())

func _glove_side_for(direction: int) -> int:
    # D-hook lands with the right glove; everything else uses the left glove,
    # matching the block-side convention in _on_step_blocked.
    return PlayerGloves.Side.RIGHT if direction == SimonSequence.Direction.RIGHT else PlayerGloves.Side.LEFT
```

Attack-phase entry/exit:

```gdscript
func _trigger_attack_phase() -> void:
    _in_attack = true
    _defense.stop()
    _snap_clear_simon_visuals()
    _opponent.set_action(Opponent.Action.GUARD_DOWN, Opponent.Direction.LEFT)
    _attack.begin(_combo.input_count())

func _on_attack_step_flashed(direction: int) -> void:
    _prompts.flash(direction, _attack.step_seconds)

func _on_attack_step_landed(index: int) -> void:
    AudioBus.play_sfx("punch")
    var direction: int = _attack.current_sequence().steps()[index]
    var side: int = _glove_side_for(direction)
    _prompts.flash_success(direction, _PUNCH_FLASH_SECONDS)
    _gloves.set_state(side, PlayerGloves.State.PUNCH)
    await get_tree().create_timer(_PUNCH_FLASH_SECONDS).timeout
    _gloves.set_state(side, PlayerGloves.State.IDLE)

func _on_attack_succeeded() -> void:
    if _combo.is_at_knockdown_threshold():
        await _play_knockdown_sequence()
    else:
        _combo.on_attack_success()
        _refresh_combo_meter()
        _return_to_defense_after_attack()

func _on_attack_failed() -> void:
    # CONTEXT.md → "Combo": failed attack inputs do not reset combo. We just
    # return to defense.
    _return_to_defense_after_attack()

func _return_to_defense_after_attack() -> void:
    _in_attack = false
    _opponent_idle()
    # Phase transition resets the Simon chain to length 1 (CONTEXT.md → Simon
    # Sequence). stop+start clears any in-flight show generation and reseeds.
    _defense.stop()
    _defense.start()
    _begin_breather_gap()  # 4s, riddle hidden, snap-show next prompt on exit

func _play_knockdown_sequence() -> void:
    _in_attack = false
    _clock.pause()
    _knockdowns.increment()
    _refresh_knockdown_meter()
    _opponent.set_action(Opponent.Action.KNOCKED_DOWN, Opponent.Direction.LEFT)
    await _banner.show_message("Knock Down!", MatchPacing.KNOCK_DOWN_BANNER)
    # KNOCKDOWN_PAUSE is the total clock-pause duration; the banner ate part of
    # it, hold the remainder before resuming the clock.
    var remainder := MatchPacing.KNOCKDOWN_PAUSE - MatchPacing.KNOCK_DOWN_BANNER
    if remainder > 0.0:
        await get_tree().create_timer(remainder).timeout
    if _knockdowns.is_knockout():
        await _banner.show_message("Knock Out!", MatchPacing.KNOCK_OUT_BANNER)
        await _banner.show_message("You Win!", MatchPacing.YOU_WIN_BANNER)
        Globals.last_match_outcome = Globals.MatchOutcome.WIN
        SceneRouter.goto_match_results()
        return
    _combo.on_knockdown_completed()
    _refresh_combo_meter()
    _opponent_idle()
    _clock.resume()
    # CONTEXT.md → Fresh-Start Gap is the post-knockdown entry, not Breather Gap.
    # Defense restarts inside _begin_fresh_start_gap() after the 1s dead-air front.
    _defense.stop()
    _begin_fresh_start_gap()
```

Splice the RIGHT branch into the existing `_on_answer_submitted` — replace the placeholder block only, keep the WRONG and NEUTRAL branches as they are:

```gdscript
        Outcome.Type.RIGHT:
            _trigger_attack_phase()
```

(The prelude that flips `_visibility` to `BREATHER_GAP` and hides the riddle stays; entering attack phase keeps the K-press gate satisfied for the duration of the attack.)

Extend `_unhandled_input` so WASD routes to AttackPhase during attack — keep the existing F8 and `menu_confirm` paths intact:

```gdscript
func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and event.keycode == KEY_F8:
        _clock.tick(280.0)
        return
    if _awaiting_continue and event.is_action_pressed("menu_confirm"):
        _awaiting_continue = false
        _continue_pressed.emit()
        return
    if _transitioning:
        return
    var direction := -1
    if event.is_action_pressed("attack_head"):
        direction = SimonSequence.Direction.HEAD
    elif event.is_action_pressed("attack_left"):
        direction = SimonSequence.Direction.LEFT
    elif event.is_action_pressed("attack_body"):
        direction = SimonSequence.Direction.BODY
    elif event.is_action_pressed("attack_right"):
        direction = SimonSequence.Direction.RIGHT
    if direction == -1:
        return
    if _in_attack:
        _attack.player_input(direction)
    else:
        _defense.player_input(direction)
```

- [ ] **Step 2: Run and verify**

Submit "right" → opponent guard down → 1-step flash → repeat correctly → 4s Breather Gap → next prompt, combo x2. Repeat → x3, 3-step sequence on next "right". Complete x3 attack → Knockdown banner, 5s clock-pause total, opponent knocked-down sprite, Fresh-Start Gap on resume. Three knockdowns → "Knock Out!" → "You Win!" → MatchResults. Deliberately fail an attack repeat → return to defense with combo preserved + 4s Breather Gap.

- [ ] **Step 3: Commit**

```bash
git add scripts/gameplay.gd scripts/match_pacing.gd
git commit -m "feat: wire AttackPhase with combo progression, knockdowns, and KO win"
```

### Manual Test for Milestone 10

- Achieve a knockout: submit "right" repeatedly, complete each attack sequence (1, 2, 3 inputs).
- Confirm Knockdown banner, 5s pause, combo reset to x1, defense Simon resets to length 1.
- Confirm 3rd KD → Knock Out! → You Win! → MatchResults shows "You Win!" and unlocks next tier.
- Deliberately fail an attack: confirm return to defense with combo preserved.

---

## Milestone 11: Round 1 → Round 2 Transition State Reset

**Goal:** When Round 1 ends without a KO, the transition correctly resets state: +1 heart (cap 5), -1 KD (floor 0), Simon to length 1, combo to x1, dialogue deck resets, opponent to idle.

**Manual test for this milestone:**
- Take 2 hearts of damage, get 1 knockdown. F8 to end Round 1.
- After "Round Over!" → "Ready?" → "Fight!", verify hearts = 4 (3 remaining + 1 heal), KD = 0, combo = x1, Simon chain starts fresh at length 1.
- F8 to end Round 2 without 3rd KD → MatchResults "Draw!".

### Task 11.1: Apply round-end resets in Gameplay

**Files:**
- Modify: `scripts/gameplay.gd`

- [ ] **Step 1: Extend `_handle_round_end()`**

```gdscript
func _handle_round_end() -> void:
    _transitioning = true
    _clock.pause()
    _defense.stop()
    if _clock.current_round() >= MatchClock.TOTAL_ROUNDS:
        await _banner.show_message("Round Over!", 3.0)
        Globals.last_match_outcome = Globals.MatchOutcome.DRAW
        SceneRouter.goto_match_results()
        return
    await _banner.show_message("Round Over!", 3.0)
    _apply_round_end_state_reset()
    _clock.advance_to_next_round()
    await _play_ready_fight()
    _clock.start()
    _defense.start()
    _transitioning = false

func _apply_round_end_state_reset() -> void:
    _hearts.heal()
    _knockdowns.apply_round_end_decrement()
    _combo.on_knockdown_completed()  # resets to x1
    _deck.reset()
    _refresh_heart_row()
    _refresh_knockdown_meter()
    _refresh_combo_meter()
    _opponent.set_body(Opponent.BodyState.IDLE)
    _show_next_prompt()
```

- [ ] **Step 2: Run and verify**

Take some hits in round 1, F8 to end. Confirm heart +1 (capped at 5), KD -1 (floor 0), combo x1, fresh prompt, fresh Simon.

- [ ] **Step 3: Commit**

```bash
git add scripts/gameplay.gd
git commit -m "feat: apply heart heal, KD decrement, combo and deck reset on round transition"
```

### Manual Test for Milestone 11

- Take 2 hits, 1 KD; end round 1 (F8). Verify hearts go from 3→4, KD from 1→0, combo to x1, fresh prompt.
- End round 2 without finishing: confirm "Draw!" result.
- Take 5 hits in round 2: confirm immediate "You Lose!" mid-round.

---

## Milestone 12: Damage Feedback FX

**Goal:** When the player takes damage (from failed defense or wrong riddle), the screen flashes red, then shakes, then briefly fades to a transparent black before recovering.

**Manual test for this milestone:**
- Deliberately take damage. Confirm:
  - Quick red flash overlay (~100ms).
  - Screen shake for ~200ms (small offset).
  - Fade-to-transparent-black overlay (~150ms in, ~150ms out).
  - Whole effect resolves within ~600ms.

### Task 12.1: DamageEffect overlay

**Files:**
- Create: `scripts/ui/damage_effect.gd`
- Create: `scenes/ui/damage_effect.tscn`

- [ ] **Step 1: Implement the script**

```gdscript
class_name DamageEffect
extends Control

@onready var _red: ColorRect = $RedFlash
@onready var _black: ColorRect = $BlackFade

func _ready() -> void:
    _red.modulate.a = 0.0
    _black.modulate.a = 0.0

func play() -> void:
    var tween := create_tween()
    tween.tween_property(_red, "modulate:a", 0.6, 0.05)
    tween.tween_property(_red, "modulate:a", 0.0, 0.10)
    tween.parallel().tween_property(_black, "modulate:a", 0.35, 0.15).set_delay(0.1)
    tween.tween_property(_black, "modulate:a", 0.0, 0.15)
    _shake()

func _shake() -> void:
    var parent := get_parent()
    if parent == null:
        return
    var original := parent.position if parent is Node2D else Vector2.ZERO
    var tween := create_tween()
    for i in 8:
        var offset := Vector2(randf_range(-12, 12), randf_range(-12, 12))
        if parent is Node2D:
            tween.tween_property(parent, "position", original + offset, 0.025)
        else:
            tween.tween_callback(func(): pass)
    if parent is Node2D:
        tween.tween_property(parent, "position", original, 0.025)
```

- [ ] **Step 2: Build the scene**

`scenes/ui/damage_effect.tscn`:
- Control (root, full rect) `DamageEffect`, mouse_filter = IGNORE
  - ColorRect `RedFlash` — full rect, color red, modulate alpha 0
  - ColorRect `BlackFade` — full rect, color black, modulate alpha 0

- [ ] **Step 3: Commit**

```bash
git add scripts/ui/damage_effect.gd scenes/ui/damage_effect.tscn
git commit -m "feat: add DamageEffect overlay with red flash, shake, and black fade"
```

### Task 12.2: Wire DamageEffect into Gameplay

**Files:**
- Modify: `scenes/gameplay.tscn`
- Modify: `scripts/gameplay.gd`

- [ ] **Step 1: Add DamageEffect instance to Gameplay scene**

Place as last child (top z-order), below AnnouncementBanner.

- [ ] **Step 2: Trigger on damage**

Update `_on_damage_taken`:

```gdscript
func _on_damage_taken() -> void:
    _hearts.take_damage()
    _combo.on_damage_taken()
    _refresh_combo_meter()
    AudioBus.play_sfx("hurt")
    _refresh_heart_row()
    $DamageEffect.play()
    if _hearts.is_empty():
        _end_match_loss()
```

- [ ] **Step 3: Run, verify visual feedback**
- [ ] **Step 4: Commit**

```bash
git add scenes/gameplay.tscn scripts/gameplay.gd
git commit -m "feat: trigger DamageEffect FX on every damage event"
```

### Manual Test for Milestone 12

- Deliberately fail several defense inputs and wrong riddle answers. Confirm red flash + shake + black fade for each.
- Confirm combo also resets on damage (visible in meter).

---

## Milestone 13: Difficulty Tiers and Opponent Wiring

**Goal:** Selecting a tier on LevelSelect picks the correct DifficultyConfig and dialogue set. The three tiers actually differ in pacing.

**Manual test for this milestone:**
- Play Tofu (Easy): slow show phase (0.8s/step), 3s window.
- Play Minty (Medium, after unlocking): faster show phase (0.55s/step), 2.5s window.
- Play Sebastian (Hard, after unlocking): fastest (0.35s/step), 2s window.
- Each opponent's dialogue placeholders shown correctly.

### Task 13.1: Author DifficultyConfig resources

**Files:**
- Create: `data/difficulty/tofu.tres`
- Create: `data/difficulty/minty.tres`
- Create: `data/difficulty/sebastian.tres`

- [ ] **Step 1: Author Tofu**

In editor: New Resource → DifficultyConfig.
- `opponent_slug` = "tofu"
- `tier` = 1
- `show_phase_step_seconds` = 0.8
- `repeat_phase_window_seconds` = 3.0
- `dialogue_deck_path` = "res://data/dialogue/tofu.tres"

Save to `data/difficulty/tofu.tres`.

- [ ] **Step 2: Author Minty**

- `opponent_slug` = "minty"
- `tier` = 2
- `show_phase_step_seconds` = 0.55
- `repeat_phase_window_seconds` = 2.5
- `dialogue_deck_path` = "res://data/dialogue/minty.tres"

- [ ] **Step 3: Author Sebastian**

- `opponent_slug` = "sebastian"
- `tier` = 3
- `show_phase_step_seconds` = 0.35
- `repeat_phase_window_seconds` = 2.0
- `dialogue_deck_path` = "res://data/dialogue/sebastian.tres"

- [ ] **Step 4: Commit**

```bash
git add data/difficulty/
git commit -m "feat: author DifficultyConfig resources for all three tiers"
```

### Task 13.2: LevelSelect sets `Globals.selected_difficulty`

**Files:**
- Modify: `scripts/level_select.gd`

- [ ] **Step 1: Update tier selection**

```gdscript
const TIER_CONFIGS := [
    "res://data/difficulty/tofu.tres",
    "res://data/difficulty/minty.tres",
    "res://data/difficulty/sebastian.tres",
]

func _select_tier(tier: int) -> void:
    var path: String = TIER_CONFIGS[tier - 1]
    Globals.selected_difficulty = load(path)
    Globals.last_played_tier = tier
    SceneRouter.goto_gameplay()
```

Remove the hardcoded `_select_tier` body that just called `goto_gameplay`.

- [ ] **Step 2: Commit**

```bash
git add scripts/level_select.gd
git commit -m "feat: pass selected DifficultyConfig from LevelSelect to Globals"
```

### Task 13.3: Gameplay consumes DifficultyConfig

**Files:**
- Modify: `scripts/gameplay.gd`

- [ ] **Step 1: Use the selected config**

Replace hardcoded `_opponent.configure("tofu")` and the hardcoded dialogue load with:

```gdscript
func _ready() -> void:
    var config: DifficultyConfig = Globals.selected_difficulty
    if config == null:
        config = load("res://data/difficulty/tofu.tres") as DifficultyConfig  # Fallback for direct testing
    Globals.last_played_tier = config.tier
    Globals.last_match_outcome = Globals.MatchOutcome.DRAW
    _opponent.configure(config.opponent_slug)
    _defense = DefensePhase.new()
    add_child(_defense)
    _defense.step_seconds = config.show_phase_step_seconds
    _defense.input_window_seconds = config.repeat_phase_window_seconds
    _attack = AttackPhase.new()
    add_child(_attack)
    _attack.step_seconds = config.show_phase_step_seconds
    _attack.input_window_seconds = config.repeat_phase_window_seconds

    _defense.step_flashed.connect(_on_step_flashed)
    _defense.step_blocked.connect(_on_step_blocked)
    _defense.damage_taken.connect(_on_damage_taken)
    _attack.step_flashed.connect(_on_attack_step_flashed)
    _attack.step_landed.connect(_on_attack_step_landed)
    _attack.attack_succeeded.connect(_on_attack_succeeded)
    _attack.attack_failed.connect(_on_attack_failed)

    var dialogue_set: DialogueSet = load(config.dialogue_deck_path)
    _deck.load_prompts(dialogue_set.prompts)
    _riddle.answer_submitted.connect(_on_answer_submitted)
    $EndButton.pressed.connect(SceneRouter.goto_match_results)
    _refresh_heart_row()
    _refresh_combo_meter()
    _refresh_knockdown_meter()
    _show_next_prompt()
    _start_round_one()
```

(Remove duplicate `var _defense := DefensePhase.new()` field initializer in favor of assigning in `_ready`.)

- [ ] **Step 2: Run and verify**

Wipe progress (F12 then restart). Play Tofu, confirm pacing feels slow. Win, unlock Minty, play; confirm distinctly faster. Win, unlock Sebastian; confirm fastest.

- [ ] **Step 3: Commit**

```bash
git add scripts/gameplay.gd
git commit -m "feat: configure Defense/Attack pacing from selected DifficultyConfig"
```

### Manual Test for Milestone 13

- Wipe progress; play each tier in sequence. Confirm pacing differences are noticeable.
- Confirm each tier's placeholder dialogue loads from the right file.

---

## Milestone 14: Announcement Banner Polish and Sprite State Coverage

**Goal:** Every banner from the spec list is wired and shows at the right moment. Every opponent body and arm state is exercised somewhere (idle, hurt, guard_down, knocked_down, plus arm guard/punches/down).

**Manual test for this milestone:**
- During a full match, confirm every banner appears at the appropriate moment:
  - Ready?, Fight! (round start)
  - Round Over! (round end)
  - Knock Down! (each KD)
  - Knock Out! (3rd KD)
  - You Win! (after KO)
  - You Lose! (5 hearts gone)
  - Draw! (end of round 2 no winner)
- Confirm opponent sprite state changes:
  - guard_down when player triggers right answer
  - hurt briefly when each attack input lands
  - knocked_down during KD interlude
  - arms set to `down` during guard_down
  - arms animate to punch_head / punch_body / punch_hook during defense show phase

### Task 14.1: Hurt sprite on attack lands

**Files:**
- Modify: `scripts/gameplay.gd`

- [ ] **Step 1: Add hurt flash on attack step**

```gdscript
func _on_attack_step_landed(_index: int) -> void:
    AudioBus.play_sfx("punch")
    $PlayerGloves.set_state(PlayerGloves.Side.RIGHT, PlayerGloves.State.PUNCH)
    _opponent.set_body(Opponent.BodyState.HURT)
    await get_tree().create_timer(0.1).timeout
    $PlayerGloves.set_state(PlayerGloves.Side.RIGHT, PlayerGloves.State.IDLE)
    _opponent.set_body(Opponent.BodyState.GUARD_DOWN)
```

- [ ] **Step 2: Commit**

```bash
git add scripts/gameplay.gd
git commit -m "feat: flash opponent hurt sprite on attack-step landings"
```

### Task 14.2: Arms down during guard_down — **retired by M6**

Retired by the M6 rig consolidation. `Opponent.Action.GUARD_DOWN` is now a single-sprite pose with both arms already lowered, and `Action.IDLE` is the guard stance — there is no separate `set_arm` to call. M10's `_trigger_attack_phase` already issues `set_action(Opponent.Action.GUARD_DOWN)` and `_return_to_defense_after_attack` already issues the equivalent `_opponent_idle()`.

- [ ] **Step 1: No code change needed — proceed.**

### Task 14.3: MatchResults shows the right banner

**Files:**
- Modify: `scripts/match_results.gd`

- [ ] **Step 1: Already wired in Task 3.2 — confirm coverage**

Run the game, lose; confirm "You Lose!" + outcome label match. Win; confirm "You Win!" + unlock badge. Draw; confirm "Draw!".

- [ ] **Step 2: No code change needed if already correct — proceed.**

### Manual Test for Milestone 14

- Run a full Win match end-to-end. Confirm Ready?, Fight!, Attack Window!, Knock Down! ×3, Knock Out!, You Win! banners.
- Run a Lose match. Confirm You Lose!.
- Run a Draw (F8 through both rounds without KO). Confirm Round Over! ×2 and Draw!.
- Verify all five opponent body states are exercised at appropriate moments.

---

## Milestone 15: Final Polish — Background and Visual Audit

**Goal:** Replace ColorRect background with `bg_ring.png` if available; do a visual pass; confirm full play loop and replayability.

**Manual test for this milestone:**
- Full play loop: Title → LevelSelect → Tofu → Win → unlock Minty → LevelSelect → Minty → Win → unlock Sebastian → LevelSelect → Sebastian → outcome.
- All HUD elements legible. All transitions smooth. No console errors.

### Task 15.1: Swap background to art if present

**Files:**
- Modify: `scenes/gameplay.tscn`
- Modify: `scripts/gameplay.gd`

- [ ] **Step 1: Add a TextureRect background that loads `bg_ring.png` if present**

In the editor: replace the `Background` ColorRect with a TextureRect named `Background`, full-rect, expand_mode = IGNORE_SIZE, stretch_mode = KEEP_ASPECT_COVERED.

In `_ready`:

```gdscript
var bg_path := "res://assets/sprites/bg/bg_ring.png"
if ResourceLoader.exists(bg_path):
    $Background.texture = load(bg_path)
```

- [ ] **Step 2: Commit**

```bash
git add scenes/gameplay.tscn scripts/gameplay.gd
git commit -m "feat: load bg_ring background art when present"
```

### Task 15.2: Final manual play-through

- [ ] **Step 1: Wipe progress**

Press F12 on LevelSelect (or delete `user://progress.cfg` directly), restart.

- [ ] **Step 2: Play all three tiers to completion**

Verify:
- All HUD reads correctly.
- All banners appear at the right times.
- Damage FX plays on every damage event.
- Pacing differs noticeably between tiers.
- Unlocks persist across restarts.
- F8 fast-forward and F12 wipe still work.

- [ ] **Step 3: Run full GUT suite**

```bash
godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit
```

All tests green.

- [ ] **Step 4: Commit (if any tweaks made during the play-through)**

---

## Final Manual Test (Milestone 15)

- Full beat-Tofu → beat-Minty → beat-Sebastian arc plays cleanly.
- Every banner shown.
- Every opponent state shown.
- All GUT tests green.

---

## Out of Scope (Deferred to Later Iterations)

These are deliberately not in this plan; the user has flagged them as lower priority or content the user will author themselves:

- **Real dialogue content per opponent.** Placeholders only; user authors the real text in `data/dialogue/*.tres`.
- **Real audio files.** AudioBus is stubbed; SFX/music files added later by dropping into `assets/audio/`.
- **Options screen** (volume, key rebinding).
- **Credits screen.**
- **Real art assets.** Placeholder colored rectangles used until `assets/sprites/*` files exist with the canonical names.
- **Fullscreen toggle / display options.**
- **Pause menu mid-match.**
- **Win/loss statistics persistence.**
- **More than one opponent per difficulty tier.**

## Asset Authoring Checklist (For Parallel Work)

While the implementation proceeds, art assets should be created with these exact filenames. Anything missing will fall back to a placeholder rectangle. See `CONTEXT.md` for the canonical taxonomy.

- [ ] `assets/sprites/player/player_glove_{left,right}_{idle,block,punch}.png` (6 files)
- [ ] `assets/sprites/opponents/tofu/opponent_tofu_body_{idle,hurt,guard_down,knocked_down,talking}.png` (5 files)
- [ ] `assets/sprites/opponents/tofu/opponent_tofu_arm_{left,right}_{guard,punch_head,punch_body,punch_hook,down}.png` (10 files)
- [ ] Same set for `minty` and `sebastian` (15 files × 2 = 30 files)
- [ ] `assets/sprites/ui/prompt_{w,a,s,d}.png` (4 files)
- [ ] `assets/sprites/ui/{heart_full,heart_empty,combo_x1,combo_x2,combo_x3,knockdown_icon,timer_bg,riddle_box,answer_box}.png` (9 files)
- [ ] `assets/sprites/banners/banner_{ready,fight,round_over,knock_down,knock_out,you_win,you_lose,draw}.png` (8 files)
- [ ] `assets/sprites/bg/bg_ring.png` (1 file)

**Total: 73 sprite assets.**
