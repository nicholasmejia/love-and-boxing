# Minty Riddles + Reaction State Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Reaction State to the riddle box so each picked answer is followed by the opponent's reaction line inside existing gameplay timing, and ship Minty's 9-prompt text dialogue deck. Tofu's image-only deck is unaffected.

**Architecture:** New `reaction_text` field on `DialogueAnswer`. RiddleBox grows a two-state machine (`NORMAL` / `REACTION`); `display(prompt)` enters NORMAL, `show_reaction(picked_index)` enters REACTION (with empty-fallback to hide). Gameplay drops the unconditional snap-hide on `answer_submitted`, drops the "Try again!" banner (replaced by a bare timer of the same duration), and on RIGHT path hides the riddle on first registered attack input via a new `AttackPhase.first_input_received` signal.

**Tech Stack:** Godot 4 / GDScript, GUT for tests, `.tres` resource files for content.

**Spec:** `docs/superpowers/specs/2026-05-21-minty-riddles-and-reactions-design.md`

**User-testable milestones:**
- End of **Task 2** — Minty match now uses Minty's text deck (text prompts visible; reactions not wired yet).
- End of **Task 5** — Full reaction beat playable: WRONG / NEUTRAL / RIGHT all display reactions; "Try again!" banner gone; first attack input on RIGHT hides the riddle.

---

### Task 1: DialogueAnswer — `reaction_text` field + `has_reaction()`

**Files:**
- Modify: `scripts/game/dialogue_answer.gd`
- Test: `tests/unit/test_dialogue_prompt.gd` (extend)

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/test_dialogue_prompt.gd`:

```gdscript
func test_answer_reaction_text_defaults_empty():
	var a := DialogueAnswer.new()
	assert_eq(a.reaction_text, "")
	assert_false(a.has_reaction())

func test_answer_has_reaction_when_set():
	var a := DialogueAnswer.new()
	a.reaction_text = "I knew it!"
	assert_true(a.has_reaction())
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=tests/unit/test_dialogue_prompt.gd -gexit`
Expected: FAIL — `has_reaction()` not defined / `reaction_text` not a property.

- [ ] **Step 3: Add the field and method to `scripts/game/dialogue_answer.gd`**

The full file should read:

```gdscript
class_name DialogueAnswer
extends Resource

@export var text: String = ""
@export var image: Texture2D
@export var outcome: int = Outcome.Type.NEUTRAL
@export var reaction_text: String = ""

func has_text() -> bool:
	return text != ""

func has_image() -> bool:
	return image != null

func has_reaction() -> bool:
	return reaction_text != ""
```

- [ ] **Step 4: Run tests to verify they pass**

Run the same GUT command.
Expected: all `test_dialogue_prompt.gd` tests PASS.

- [ ] **Step 5: Smoke-load an existing tofu prompt to verify back-compat**

Run: `godot --headless --check-only project.godot` (parse-only, validates resources load).
Expected: no errors. Tofu's existing `.tres` files load with `reaction_text = ""`.

- [ ] **Step 6: Commit**

```bash
git add scripts/game/dialogue_answer.gd tests/unit/test_dialogue_prompt.gd
git commit -m "$(cat <<'EOF'
feat(dialogue): add reaction_text to DialogueAnswer

Per-answer reaction line used by the upcoming Reaction State on the
riddle box. Tofu's existing .tres files default to empty and continue
to behave as before.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Minty content — 9 prompts + deck + wiring

**Files:**
- Create: `data/dialogue/minty/deck.tres`
- Create: `data/dialogue/minty/tier_0/flex_feint.tres`
- Create: `data/dialogue/minty/tier_0/dog_distraction.tres`
- Create: `data/dialogue/minty/tier_0/hungry_footwork.tres`
- Create: `data/dialogue/minty/tier_1/bug_in_the_ring.tres`
- Create: `data/dialogue/minty/tier_1/pink_gloves.tres`
- Create: `data/dialogue/minty/tier_1/sparring_date.tres`
- Create: `data/dialogue/minty/tier_2/bruise_compliment.tres`
- Create: `data/dialogue/minty/tier_2/dog_trap.tres`
- Create: `data/dialogue/minty/tier_2/strength_test.tres`
- Modify: `data/difficulty/minty.tres:11`
- Test: `tests/unit/test_dialogue_deck.gd` (extend with deck-shape smoke)

The `.tres` files follow the same pattern as `data/dialogue/tofu/tier_0/banana.tres` (3 sub-resource `DialogueAnswer`s, then the `DialoguePrompt` resource that references them), except (a) `body_image` is null, (b) `body_text` carries the JSON `clue`, and (c) each `DialogueAnswer` has `text` (player line) + `reaction_text` (opponent line) instead of `image`.

- [ ] **Step 1: Write the failing smoke test**

Append to `tests/unit/test_dialogue_deck.gd`:

```gdscript
func test_minty_deck_loads_with_three_prompts_per_tier_and_reactions():
	var deck := load("res://data/dialogue/minty/deck.tres") as DialogueDeckResource
	assert_not_null(deck, "minty deck failed to load")
	assert_eq(deck.tier_0.size(), 3)
	assert_eq(deck.tier_1.size(), 3)
	assert_eq(deck.tier_2.size(), 3)
	for tier in [deck.tier_0, deck.tier_1, deck.tier_2]:
		for prompt in tier:
			assert_eq(prompt.answers.size(), 3)
			assert_true(prompt.has_text_body(), "minty body should be text")
			for answer in prompt.answers:
				assert_ne(answer.text, "", "minty answer text must be set")
				assert_true(answer.has_reaction(), "minty answer reaction must be set")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=tests/unit/test_dialogue_deck.gd -gexit`
Expected: FAIL — `res://data/dialogue/minty/deck.tres` does not exist.

- [ ] **Step 3: Create the nine prompt `.tres` files**

Each file follows this template. Substitute `<CLUE>`, `<RIGHT_TEXT>`, `<RIGHT_REACTION>`, `<NEUTRAL_TEXT>`, `<NEUTRAL_REACTION>`, `<WRONG_TEXT>`, `<WRONG_REACTION>` from the JSON content below. `outcome` integers are fixed (RIGHT=2, NEUTRAL=1, WRONG=0).

```
[gd_resource type="Resource" script_class="DialoguePrompt" load_steps=3 format=3]

[ext_resource type="Script" path="res://scripts/game/dialogue_prompt.gd" id="1_prompt"]
[ext_resource type="Script" path="res://scripts/game/dialogue_answer.gd" id="2_answer"]

[sub_resource type="Resource" id="ans_right"]
script = ExtResource("2_answer")
text = "<RIGHT_TEXT>"
outcome = 2
reaction_text = "<RIGHT_REACTION>"

[sub_resource type="Resource" id="ans_neutral"]
script = ExtResource("2_answer")
text = "<NEUTRAL_TEXT>"
outcome = 1
reaction_text = "<NEUTRAL_REACTION>"

[sub_resource type="Resource" id="ans_wrong"]
script = ExtResource("2_answer")
text = "<WRONG_TEXT>"
outcome = 0
reaction_text = "<WRONG_REACTION>"

[resource]
script = ExtResource("1_prompt")
body_text = "<CLUE>"
answers = Array[Resource]([SubResource("ans_right"), SubResource("ans_neutral"), SubResource("ans_wrong")])
```

The nine substitutions (verbatim from the JSON the user supplied — quote characters inside text need to be escaped as `\"`):

**`data/dialogue/minty/tier_0/flex_feint.tres`** — Q1
- CLUE: `Minty hops in place, then throws a jab-cross-knee combo. \"Be honest! Do these arms say 'romantic heroine,' or do they say 'final boss who drinks protein out of a vase'?\"`
- RIGHT_TEXT: `Both. You look like you could crush a villain and still expect flowers after.`
- RIGHT_REACTION: `Flowers after violence…? Wait, that's cute. Stop being cute. Guard down! I mean—guard up!`
- NEUTRAL_TEXT: `They say you train really hard.`
- NEUTRAL_REACTION: `Accurate! Boring, but accurate!`
- WRONG_TEXT: `Mostly final boss, honestly.`
- WRONG_REACTION: `Final boss?! I'm at least a secret romantic mini-boss!`

**`data/dialogue/minty/tier_0/dog_distraction.tres`** — Q2
- CLUE: `Minty starts a spinning kick, then gasps at something behind you. \"A dog! No, focus! No, wait, what kind? This matters emotionally!\"`
- RIGHT_TEXT: `A happy little mutt with a stupid smile. Extremely pettable. Possibly your soulmate.`
- RIGHT_REACTION: `A stupid smile mutt?! My weakness! I'm compromised!`
- NEUTRAL_TEXT: `A dog is a dog. Dogs are good.`
- NEUTRAL_REACTION: `Correct category, weak poetry!`
- WRONG_TEXT: `A bloodhound. Big droopy face, red eyes, lots of mysterious swamp energy.`
- WRONG_REACTION: `Bloodhound?! Why would you put that image in my heart?!`

**`data/dialogue/minty/tier_0/hungry_footwork.tres`** — Q3
- CLUE: `Minty's stomach growls loud enough to interrupt her combo. She keeps punching anyway. \"Ignore that! My stomach is just also trying to win the match!\"`
- RIGHT_TEXT: `That wasn't a growl. That was your inner champion demanding noodles.`
- RIGHT_REACTION: `My inner champion does want noodles… wait, how did you know?!`
- NEUTRAL_TEXT: `You must be hungry after all this.`
- NEUTRAL_REACTION: `Obviously! These kicks are not powered by air!`
- WRONG_TEXT: `Maybe your stomach should throw in the towel.`
- WRONG_REACTION: `Nobody tells my stomach to quit except me!`

**`data/dialogue/minty/tier_1/bug_in_the_ring.tres`** — Q4
- CLUE: `A beetle crawls near the edge of the mat. Minty shrieks, then immediately throws a brutal elbow. \"Don't step on it! But also if it touches me, I will become a ghost!\"`
- RIGHT_TEXT: `I'll relocate the tiny criminal with a cup. You keep being brave from six feet away.`
- RIGHT_REACTION: `Tiny criminal! Yes! Humane justice! Oh no, that was charming!`
- NEUTRAL_TEXT: `I'll move it so you don't have to look at it.`
- NEUTRAL_REACTION: `Helpful. Not romantic. But helpful.`
- WRONG_TEXT: `I'll end its reign of terror permanently.`
- WRONG_REACTION: `No murder! He's disgusting, not evil!`

**`data/dialogue/minty/tier_1/pink_gloves.tres`** — Q5
- CLUE: `Minty flashes pink boxing gloves with tiny heart decals. \"Some fighters say these aren't intimidating. Which is rude, because I can absolutely rearrange teeth with a heart theme.\"`
- RIGHT_TEXT: `The hearts make it scarier. Getting lovingly demolished has layers.`
- RIGHT_REACTION: `Lovingly demolished?! That's my brand! I hate that you know my brand!`
- NEUTRAL_TEXT: `They're cute, but you still seem tough.`
- NEUTRAL_REACTION: `Seem tough? I am actively kicking you!`
- WRONG_TEXT: `They're cute, so people probably underestimate you.`
- WRONG_REACTION: `No! The hearts are not a disguise! They are part of the violence!`

**`data/dialogue/minty/tier_1/sparring_date.tres`** — Q6
- CLUE: `Minty grins and tightens her guard. \"Some girls like candlelit dinners. I like seeing if someone can survive three rounds and still compliment my hair.\"`
- RIGHT_TEXT: `Then I'll block what I can, compliment the hair honestly, and earn the dinner later.`
- RIGHT_REACTION: `Earn the dinner later?! Dangerous answer. Emotionally dangerous!`
- NEUTRAL_TEXT: `Your hair does look nice.`
- NEUTRAL_REACTION: `Good, yes, correct, but you are still being punched.`
- WRONG_TEXT: `I'd lose on purpose if it made the date go better.`
- WRONG_REACTION: `Lose on purpose? That is not romance, that is fraud with gloves!`

**`data/dialogue/minty/tier_2/bruise_compliment.tres`** — Q7
- CLUE: `Minty blocks your strike and laughs, but you notice a bruise on her shoulder. She catches you looking. \"Don't make that face. I know. Not very princessy, right?\"`
- RIGHT_TEXT: `Princesses can have battle damage. Yours just comes with better footwork.`
- RIGHT_REACTION: `Battle princess with footwork…? Oh no. That got through.`
- NEUTRAL_TEXT: `It doesn't look that bad.`
- NEUTRAL_REACTION: `That was medical, not romantic.`
- WRONG_TEXT: `Don't worry, I still think you look pretty.`
- WRONG_REACTION: `'Still'? STILL?! I heard that little word do a crime!`

**`data/dialogue/minty/tier_2/dog_trap.tres`** — Q8
- CLUE: `Minty wipes sweat from her brow. \"Okay, important compatibility test. If we got a dog, what kind are we emotionally prepared to co-parent?\"`
- RIGHT_TEXT: `A cheerful rescue mutt with one floppy ear and absolutely no haunted bloodhound energy.`
- RIGHT_REACTION: `No haunted bloodhound energy! You listened to my soul!`
- NEUTRAL_TEXT: `Any dog you like.`
- NEUTRAL_REACTION: `Sweet, but dangerously vague. What if someone brings a droopy swamp detective?`
- WRONG_TEXT: `A loyal bloodhound. Big soulful eyes, dramatic droopy face, very romantic.`
- WRONG_REACTION: `Why are you trying to curse our imaginary home?!`

**`data/dialogue/minty/tier_2/strength_test.tres`** — Q9
- CLUE: `Minty steps in close, guard high, cheeks pink from exertion. \"People say they like strong girls, but then they get weird when the strong girl is actually strong. So what happens if I knock you flat?\"`
- RIGHT_TEXT: `I get up, ask for pointers, and pretend my dignity didn't leave through the emergency exit.`
- RIGHT_REACTION: `Dignity emergency exit?! Hehe—wait, no, I laughed! Opening!`
- NEUTRAL_TEXT: `I'd be impressed you hit that hard.`
- NEUTRAL_REACTION: `Obviously I hit hard! Compliment received, connection pending!`
- WRONG_TEXT: `I'd tell you to go easy, since this is basically a date.`
- WRONG_REACTION: `Wrong! Date violence is still honest violence!`

- [ ] **Step 4: Create the deck `.tres`**

`data/dialogue/minty/deck.tres`:

```
[gd_resource type="Resource" script_class="DialogueDeckResource" load_steps=11 format=3 uid="uid://c1mintydeck"]

[ext_resource type="Script" path="res://scripts/game/dialogue_deck_resource.gd" id="1_deck"]
[ext_resource type="Resource" path="res://data/dialogue/minty/tier_0/flex_feint.tres" id="t0_flex"]
[ext_resource type="Resource" path="res://data/dialogue/minty/tier_0/dog_distraction.tres" id="t0_dog"]
[ext_resource type="Resource" path="res://data/dialogue/minty/tier_0/hungry_footwork.tres" id="t0_hungry"]
[ext_resource type="Resource" path="res://data/dialogue/minty/tier_1/bug_in_the_ring.tres" id="t1_bug"]
[ext_resource type="Resource" path="res://data/dialogue/minty/tier_1/pink_gloves.tres" id="t1_gloves"]
[ext_resource type="Resource" path="res://data/dialogue/minty/tier_1/sparring_date.tres" id="t1_date"]
[ext_resource type="Resource" path="res://data/dialogue/minty/tier_2/bruise_compliment.tres" id="t2_bruise"]
[ext_resource type="Resource" path="res://data/dialogue/minty/tier_2/dog_trap.tres" id="t2_dog"]
[ext_resource type="Resource" path="res://data/dialogue/minty/tier_2/strength_test.tres" id="t2_strength"]

[resource]
script = ExtResource("1_deck")
tier_0 = Array[Resource]([ExtResource("t0_flex"), ExtResource("t0_dog"), ExtResource("t0_hungry")])
tier_1 = Array[Resource]([ExtResource("t1_bug"), ExtResource("t1_gloves"), ExtResource("t1_date")])
tier_2 = Array[Resource]([ExtResource("t2_bruise"), ExtResource("t2_dog"), ExtResource("t2_strength")])
```

- [ ] **Step 5: Wire the deck into Minty's DifficultyConfig**

Modify `data/difficulty/minty.tres:11`. Change:

```
dialogue_deck_path = ""
```

to:

```
dialogue_deck_path = "res://data/dialogue/minty/deck.tres"
```

Leave all other lines (including `bgm_track_path`) untouched.

- [ ] **Step 6: Run the smoke test to verify it passes**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=tests/unit/test_dialogue_deck.gd -gexit`
Expected: `test_minty_deck_loads_with_three_prompts_per_tier_and_reactions` PASSES.

- [ ] **Step 7: Manual in-engine verification — Minty text prompts appear**

Run the game from the Godot editor (F5). At Level Select pick Minty. Start the match. Expected: text prompts (the JSON clues) appear in the riddle box; three text answer cards display. Pick any answer — current behavior holds (riddle snap-hides, gameplay proceeds normally). Reactions are NOT yet visible — that lands in Task 5.

- [ ] **Step 8: Commit**

```bash
git add data/dialogue/minty/ data/difficulty/minty.tres tests/unit/test_dialogue_deck.gd
git commit -m "$(cat <<'EOF'
feat(minty): author 9-prompt text dialogue deck and wire to minty.tres

Mirror of tofu's three-tier deck layout, populated from the JSON
content brief. Reactions are authored on every answer; the in-engine
reaction beat is not wired yet (lands with the RiddleBox state machine).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: RiddleBox state machine — `NORMAL` / `REACTION`

**Files:**
- Modify: `scripts/ui/riddle_box.gd`
- Test: `tests/unit/test_riddle_box.gd` (create)

- [ ] **Step 1: Write the failing tests**

Create `tests/unit/test_riddle_box.gd`:

```gdscript
extends GutTest

const RiddleBoxScene := preload("res://scenes/ui/riddle_box.tscn")

func _make_prompt(reactions: Array) -> DialoguePrompt:
	# reactions: 3-element array of String; pass "" for empty reaction.
	var p := DialoguePrompt.new()
	p.body_text = "body"
	var outcomes := [Outcome.Type.WRONG, Outcome.Type.NEUTRAL, Outcome.Type.RIGHT]
	for i in 3:
		var a := DialogueAnswer.new()
		a.text = "answer_%d" % i
		a.outcome = outcomes[i]
		a.reaction_text = reactions[i]
		p.answers.append(a)
	return p

func _mount() -> RiddleBox:
	var box: RiddleBox = RiddleBoxScene.instantiate()
	add_child_autoqfree(box)
	return box

func test_display_enters_normal_with_all_cards_visible():
	var box := _mount()
	box.display(_make_prompt(["r0", "r1", "r2"]))
	await get_tree().process_frame
	assert_eq(box.get_state(), RiddleBox.State.NORMAL)
	for card in box.get_cards():
		assert_true(card.visible)

func test_show_reaction_hides_unpicked_cards_and_swaps_body_text():
	var box := _mount()
	var prompt := _make_prompt(["r0", "r1", "r2"])
	box.display(prompt)
	await get_tree().process_frame
	box.show_reaction(1)
	await get_tree().process_frame
	assert_eq(box.get_state(), RiddleBox.State.REACTION)
	var cards := box.get_cards()
	assert_false(cards[0].visible)
	assert_true(cards[1].visible)
	assert_false(cards[2].visible)

func test_show_reaction_with_empty_reaction_hides_box():
	var box := _mount()
	var prompt := _make_prompt(["", "", ""])  # tofu-shaped: no reactions
	box.display(prompt)
	await get_tree().process_frame
	box.show_reaction(0)
	await get_tree().process_frame
	assert_false(box.visible)
	assert_eq(box.get_state(), RiddleBox.State.NORMAL)  # state unchanged

func test_redisplay_from_reaction_returns_to_normal_with_all_cards():
	var box := _mount()
	var prompt := _make_prompt(["r0", "r1", "r2"])
	box.display(prompt)
	await get_tree().process_frame
	box.show_reaction(2)
	await get_tree().process_frame
	box.display(prompt)
	await get_tree().process_frame
	assert_eq(box.get_state(), RiddleBox.State.NORMAL)
	for card in box.get_cards():
		assert_true(card.visible)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=tests/unit/test_riddle_box.gd -gexit`
Expected: FAIL — `RiddleBox.State` enum not defined, `get_state()` / `get_cards()` / `show_reaction()` not defined.

- [ ] **Step 3: Rewrite `scripts/ui/riddle_box.gd`**

The full file should read:

```gdscript
class_name RiddleBox
extends Control

signal answer_submitted(outcome: int)

enum State { NORMAL, REACTION }

@onready var _body_text: RichTextLabel = $Layout/Body/Text
@onready var _body_image: TextureRect = $Layout/Body/Image
@onready var _cards: Array[AnswerCard] = [
	$Layout/Answers/Left,
	$Layout/Answers/Middle,
	$Layout/Answers/Right,
]

var _highlight_index: int = 1  # I = middle by default
var _typewriter_speed: float = 30.0
var _typewriter_generation: int = 0
var _state: int = State.NORMAL
# Mirror of the picked answer per display, captured at confirm time so
# show_reaction() can read reaction_text without knowing the DialogueAnswer.
var _picked_answers: Array[DialogueAnswer] = []

func get_state() -> int:
	return _state

func get_cards() -> Array:
	return _cards

func display(prompt: DialoguePrompt) -> void:
	_state = State.NORMAL
	visible = true
	for card in _cards:
		card.visible = true
	if prompt.has_image_body():
		_body_image.texture = prompt.body_image
		_body_image.visible = true
		_body_text.visible = false
	else:
		_body_text.visible = true
		_body_image.visible = false
		_start_typewriter(prompt.body_text)
	# Answer cards are shuffled per display so position never reveals outcome.
	# Don't mutate prompt.answers — the deck reuses prompts across redraws.
	var shuffled := prompt.answers.duplicate()
	shuffled.shuffle()
	_picked_answers.clear()
	for i in _cards.size():
		if i < shuffled.size():
			_cards[i].display(shuffled[i])
			_picked_answers.append(shuffled[i])
	_highlight_index = 1
	_refresh_highlight()

func show_reaction(picked_index: int) -> void:
	if picked_index < 0 or picked_index >= _picked_answers.size():
		return
	var picked := _picked_answers[picked_index]
	if not picked.has_reaction():
		hide()
		return
	for i in _cards.size():
		_cards[i].visible = (i == picked_index)
	_body_image.visible = false
	_body_text.visible = true
	_start_typewriter(picked.reaction_text)
	_state = State.REACTION

func _start_typewriter(text: String) -> void:
	_typewriter_generation += 1
	var my_generation := _typewriter_generation
	_body_text.text = text
	_body_text.visible_characters = 0
	var total := text.length()
	while _body_text.visible_characters < total:
		if my_generation != _typewriter_generation:
			return
		_body_text.visible_characters += 1
		await get_tree().create_timer(1.0 / _typewriter_speed).timeout

func _unhandled_input(event: InputEvent) -> void:
	if _state == State.REACTION:
		return
	# menu_change_item fires only when highlight actually moves. Confirm carries
	# no SFX — the riddle outcome SFX (riddle_correct/_neutral/_wrong) is the
	# feedback for picking an answer.
	var new_index: int = _highlight_index
	if event.is_action_pressed("menu_left"):
		new_index = 0
	elif event.is_action_pressed("menu_up"):
		new_index = 1
	elif event.is_action_pressed("menu_right"):
		new_index = 2
	elif event.is_action_pressed("menu_confirm"):
		var picked_index := _highlight_index
		show_reaction(picked_index)
		answer_submitted.emit(_cards[picked_index].outcome())
		return
	if new_index != _highlight_index:
		_highlight_index = new_index
		_refresh_highlight()
		AudioBus.play_sfx("menu_change_item")

func _refresh_highlight() -> void:
	for i in _cards.size():
		_cards[i].set_highlighted(i == _highlight_index)
```

Key changes vs. current:
- New `State` enum, `_state` field, `_picked_answers` array.
- `display()` resets `_state = NORMAL`, sets `visible = true`, restores all cards' visibility, captures the post-shuffle answer array.
- New `show_reaction(picked_index)` method per the spec (empty-fallback hides the box, state stays NORMAL since REACTION was never entered).
- `_unhandled_input` early-returns on REACTION.
- `menu_confirm` branch now captures `_highlight_index`, calls `show_reaction(picked_index)` synchronously, then emits the existing `answer_submitted` signal.

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=tests/unit/test_riddle_box.gd -gexit`
Expected: all 4 tests PASS.

- [ ] **Step 5: Run the full test suite to check for regressions**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit`
Expected: all tests PASS. RiddleBox is referenced from gameplay-side flows that are still exercised by existing tests; nothing should break.

- [ ] **Step 6: Commit**

```bash
git add scripts/ui/riddle_box.gd tests/unit/test_riddle_box.gd
git commit -m "$(cat <<'EOF'
feat(riddle): add NORMAL/REACTION state machine to RiddleBox

display() enters NORMAL; new show_reaction(picked_index) hides the two
unpicked cards and typewrites the picked answer's reaction_text in the
body area. Empty reaction_text falls back to self.hide() so tofu's
image-only deck snap-hides as before. _unhandled_input ignores menu
actions while in REACTION. Confirm now calls show_reaction synchronously
before emitting answer_submitted; gameplay observes the transition done.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: AttackPhase — `first_input_received` signal

**Files:**
- Modify: `scripts/game/attack_phase.gd`
- Test: `tests/unit/test_attack_phase.gd` (extend)

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/test_attack_phase.gd`:

```gdscript
func test_first_input_received_emits_on_first_repeat_press():
	var a := AttackPhase.new()
	a.step_seconds = 0.001
	a.gap_seconds = 0.001
	a.interlude_seconds = 0.01
	a.input_window_seconds = 10.0
	add_child_autoqfree(a)
	var fired := {"count": 0}
	a.first_input_received.connect(func(): fired["count"] += 1)
	a._sequence.seed_rng(1)
	a.begin(2)
	await get_tree().create_timer(0.1).timeout
	a.player_input(a._sequence.steps()[0])
	a.player_input(a._sequence.steps()[1])
	assert_eq(fired["count"], 1, "first_input_received must fire exactly once")

func test_first_input_received_fires_on_wrong_direction_too():
	var a := AttackPhase.new()
	a.step_seconds = 0.001
	a.gap_seconds = 0.001
	a.interlude_seconds = 0.01
	a.input_window_seconds = 10.0
	add_child_autoqfree(a)
	var fired := {"emitted": false}
	a.first_input_received.connect(func(): fired["emitted"] = true)
	a._sequence.seed_rng(1)
	a.begin(1)
	await get_tree().create_timer(0.1).timeout
	# Send a deliberately wrong direction: the opposite of step[0].
	# Directions enum is in SimonSequence (UP=0,DOWN=1,LEFT=2,RIGHT=3 — read from
	# scripts/game/simon_sequence.gd). Sending step+1 mod 4 guarantees mismatch.
	var wrong: int = (a._sequence.steps()[0] + 1) % 4
	a.player_input(wrong)
	assert_true(fired["emitted"], "wrong-direction input must still fire first_input_received")

func test_first_input_received_does_not_fire_before_repeat_phase():
	var a := AttackPhase.new()
	a.step_seconds = 10.0  # long show phase, never reaches repeat
	a.gap_seconds = 0.01
	a.interlude_seconds = 0.01
	a.input_window_seconds = 10.0
	add_child_autoqfree(a)
	var fired := {"emitted": false}
	a.first_input_received.connect(func(): fired["emitted"] = true)
	a._sequence.seed_rng(1)
	a.begin(1)
	await get_tree().create_timer(0.05).timeout
	a.player_input(a._sequence.steps()[0])  # show phase still running; _repeat_active is false
	assert_false(fired["emitted"], "show-phase input must NOT fire first_input_received")

func test_first_input_received_resets_per_begin():
	var a := AttackPhase.new()
	a.step_seconds = 0.001
	a.gap_seconds = 0.001
	a.interlude_seconds = 0.01
	a.input_window_seconds = 10.0
	add_child_autoqfree(a)
	var fired := {"count": 0}
	a.first_input_received.connect(func(): fired["count"] += 1)
	a._sequence.seed_rng(1)
	a.begin(1)
	await get_tree().create_timer(0.1).timeout
	a.player_input(a._sequence.steps()[0])
	a.begin(1)
	await get_tree().create_timer(0.1).timeout
	a.player_input(a._sequence.steps()[0])
	assert_eq(fired["count"], 2, "first_input_received must fire once per begin()")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=tests/unit/test_attack_phase.gd -gexit`
Expected: FAIL — `first_input_received` signal not defined.

- [ ] **Step 3: Modify `scripts/game/attack_phase.gd`**

Three edits.

(a) Add the signal declaration. After the existing `signal attack_failed(expected_direction: int)` at line 9, add:

```gdscript
# Fires exactly once per begin() — on the first input that registers in the
# repeat phase. Gameplay uses this to hide the reaction-state riddle box on
# the RIGHT path. Show-phase keypresses and timeouts do NOT fire this signal.
signal first_input_received
```

(b) Add the tracking field next to the other state fields (around line 25):

```gdscript
var _first_input_emitted: bool = false
```

(c) Reset the field at the top of `begin()` and emit inside `player_input()` after the `_repeat_active` guard. The two affected functions become:

```gdscript
func begin(input_count: int) -> void:
	_expected_count = input_count
	_sequence.reset()
	for i in input_count:
		_sequence.extend()
	_first_input_emitted = false
	_generation += 1
	_show()
```

```gdscript
func player_input(direction: int) -> void:
	if not _repeat_active:
		return
	if not _first_input_emitted:
		_first_input_emitted = true
		first_input_received.emit()
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
```

`_on_input_timeout` and `_fail` are unchanged — timeouts do not fire `first_input_received`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=tests/unit/test_attack_phase.gd -gexit`
Expected: all 4 new tests PASS, all existing AttackPhase tests still PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/game/attack_phase.gd tests/unit/test_attack_phase.gd
git commit -m "$(cat <<'EOF'
feat(attack): add first_input_received signal

Fires once per begin() on the first registered input in the repeat
phase. Gameplay will use it on the RIGHT path to hide the reaction-
state riddle box when the player commits to attacking. Show-phase
keypresses (no-op'd by _repeat_active) and timeouts do not fire it.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Gameplay integration — wire the reaction beat into all three outcomes

**Files:**
- Modify: `scripts/gameplay.gd:508-579` (the answer-submission handler + attack-phase setup)
- Modify: `scripts/ui/announcement_banner.gd` (delete the now-unused `show_message`)

The change is a careful surgical edit of `_on_answer_submitted` plus an additional signal connection in `_trigger_attack_phase` (or in `_ready` if that's where signals are connected — verify location).

- [ ] **Step 1: Hook `first_input_received` to hide the riddle**

In `scripts/gameplay.gd`, the AttackPhase signal connections live at lines 84-89 inside `_ready`. After line 89 (`_attack.attack_failed.connect(_on_attack_failed)`), insert one new line:

```gdscript
	_attack.first_input_received.connect(_on_attack_first_input)
```

Then add the handler. Place it next to `_on_attack_failed` (currently around line 439) — same neighborhood as the other attack callbacks:

```gdscript
func _on_attack_first_input() -> void:
	# Reaction-state riddle visible from the RIGHT-answer beat is now interrupted —
	# the player has committed to the attack phase. Hide it for the rest of the
	# phase; the next _show_next_prompt() will rebuild in NORMAL.
	_riddle.hide()
```

(Leave the initial-state `_riddle.visible = false` at line 99 alone — that's the at-game-start hide before the first prompt, not the per-answer snap-hide.)

- [ ] **Step 2: Remove the unconditional snap-hide and rewrite the gate comment**

In `_on_answer_submitted` (currently at `scripts/gameplay.gd:513`), the existing prelude lines 508–523 read:

```gdscript
# Riddle answer submission (K-press on the highlighted answer card). RiddleBox
# emits answer_submitted whenever K fires while it's mounted — including while
# the box is hidden (gaps / round transitions). The visibility gate below is
# the single source of truth for "is the player actually answering a prompt
# right now".
func _on_answer_submitted(outcome: int) -> void:
	if _visibility != RiddleVisibility.ENCOUNTER:
		return
	# Snap the riddle hidden and flip visibility out of ENCOUNTER immediately so
	# any re-entrant K-press during the awaited banner below hits the gate above
	# and bails. _begin_breather_gap() will set this again (and bump
	# _gap_generation) — doing it here is just an early gate, not a behavior
	# change. RiddleBox._unhandled_input doesn't self-check `visible`, so without
	# this prelude a mashed K can re-enter this handler mid-banner.
	_visibility = RiddleVisibility.BREATHER_GAP
	_riddle.visible = false
```

Replace this block with:

```gdscript
# Riddle answer submission (K-press on the highlighted answer card). RiddleBox
# emits answer_submitted whenever K fires while it's mounted — including while
# the box is hidden (gaps / round transitions). The visibility gate below is
# the single source of truth for "is the player actually answering a prompt
# right now".
func _on_answer_submitted(outcome: int) -> void:
	if _visibility != RiddleVisibility.ENCOUNTER:
		return
	# Flip out of ENCOUNTER immediately so re-entrant K-presses bail at the
	# gate above. RiddleBox has already entered REACTION state synchronously
	# from its confirm branch (and ignores menu input there); this is the
	# belt-and-suspenders layer for the gameplay-side flow. The riddle node
	# itself stays visible — RiddleBox owns its own visibility through the
	# REACTION state and its fallback hide() for empty-reaction (tofu) prompts.
	_visibility = RiddleVisibility.BREATHER_GAP
```

The key delta: the `_riddle.visible = false` line is gone, and the comment now reflects the new contract.

- [ ] **Step 3: Replace the NEUTRAL "Try again!" banner with a bare timer**

In `_on_answer_submitted`, the NEUTRAL branch (currently around `scripts/gameplay.gd:558-575`) reads:

```gdscript
		Outcome.Type.NEUTRAL:
			# "Try again!" hint: snap-clear leftover Simon visuals, stop the
			# current chain, show the banner, then re-display the SAME prompt
			# (cards reshuffle on display) and replay the chain at its current
			# length from step 0.
			AudioBus.play_sfx("riddle_neutral")
			_snap_clear_simon_visuals()
			_defense.stop()

			var my_gen := _gap_generation
			await _banner.show_message("Try again!", MatchPacing.TRY_AGAIN_BANNER)
			if my_gen != _gap_generation:
				return  # round end / match loss invalidated this flow

			_riddle.display(_current_prompt)
			_riddle.visible = true
			_visibility = RiddleVisibility.ENCOUNTER
			_defense.replay()
```

Replace with:

```gdscript
		Outcome.Type.NEUTRAL:
			# Reaction-state replaces the old "Try again!" banner: the box already
			# entered REACTION synchronously from confirm, displaying the picked
			# answer's reaction line. Hold for TRY_AGAIN_BANNER seconds (same
			# pacing as before) so the reaction lands, then re-display the SAME
			# prompt — cards reshuffle, RiddleBox returns to NORMAL — and replay
			# the Simon chain at its current length from step 0.
			AudioBus.play_sfx("riddle_neutral")
			_snap_clear_simon_visuals()
			_defense.stop()

			var my_gen := _gap_generation
			await get_tree().create_timer(MatchPacing.TRY_AGAIN_BANNER).timeout
			if my_gen != _gap_generation:
				return  # round end / match loss invalidated this flow

			_riddle.display(_current_prompt)
			_visibility = RiddleVisibility.ENCOUNTER
			_defense.replay()
```

Two deltas: (a) `_banner.show_message("Try again!", …)` → `get_tree().create_timer(MatchPacing.TRY_AGAIN_BANNER).timeout`; (b) the `_riddle.visible = true` line is removed since `_riddle.display(...)` now sets `visible = true` itself.

WRONG and RIGHT branches require **no changes** — they already work correctly under the new RiddleBox state machine.

- [ ] **Step 4: Delete the now-unused `show_message` from `announcement_banner.gd`**

Verify there are no other callers:

```bash
grep -rn "show_message" /Users/nicholasmejia/godot/love-and-boxing/scripts/
```

Expected: only the comment on `match_pacing.gd:12` and the definition itself remain (no more `_banner.show_message(...)` calls in gameplay.gd).

Delete the function definition in `scripts/ui/announcement_banner.gd` (currently lines 77-83):

```gdscript
func show_message(message: String, duration_seconds: float) -> void:
	_image.visible = false
	_label.text = message
	_label.visible = true
	await _animate_in()
	await get_tree().create_timer(duration_seconds).timeout
	await _animate_out()
```

Also update the comment in `scripts/match_pacing.gd:12` — currently reads:

```gdscript
# Banner display durations, in seconds. AnnouncementBanner.show_message awaits these.
```

Change to:

```gdscript
# Banner display durations, in seconds. AnnouncementBanner.show_banner awaits these.
# (TRY_AGAIN_BANNER no longer drives a banner — it's the NEUTRAL reaction-state hold.)
```

Leave the constant `TRY_AGAIN_BANNER := 1.5` itself — it's the timer duration for the NEUTRAL reaction hold.

- [ ] **Step 5: Run the full test suite**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit`
Expected: all tests PASS.

- [ ] **Step 6: Manual in-engine verification — full reaction beat**

Open the project in the Godot editor and run (F5). At Level Select pick Minty.

For each outcome verify in turn:

**WRONG** — pick an answer Minty calls wrong. Expected: the riddle box stays visible; body text swaps to the WRONG `reaction_text`; only the picked card stays visible; opponent throws the punch you'd normally see; heart damage; ~4s breather; the next prompt appears (replacing the reaction).

**NEUTRAL** — pick a neutral answer. Expected: riddle box stays visible with the NEUTRAL `reaction_text` in the body; only the picked card visible; **no "Try again!" banner appears**; after ~1.5s the same prompt re-displays with reshuffled cards.

**RIGHT** — pick a correct answer. Expected: riddle box stays visible with the RIGHT `reaction_text` in the body; only the picked card visible; attack-show begins flashing WASD prompts; on the **first** W/A/S/D press (right OR wrong direction), the riddle box hides immediately; attack phase continues normally; if you time out without pressing anything, the riddle stays visible through `_return_to_defense` and is cleared by the next prompt.

**Tofu regression check** — restart, pick Tofu. Expected: each picked answer snap-hides the riddle box exactly as today. No reaction beat. Image prompts and image answers behave unchanged.

**No "Try again!" banner anywhere** in any Minty match — verify visually.

- [ ] **Step 7: Commit**

```bash
git add scripts/gameplay.gd scripts/ui/announcement_banner.gd scripts/match_pacing.gd
git commit -m "$(cat <<'EOF'
feat(gameplay): wire reaction beat into all three answer outcomes

Drop the unconditional _riddle.visible = false snap-hide from
_on_answer_submitted — RiddleBox owns visibility through its new
REACTION state. Replace the "Try again!" banner await on NEUTRAL with
a bare timer of the same duration; the picked answer's reaction line
is what the player reads during that beat. On RIGHT, the new
first_input_received signal hides the riddle the moment the player
commits to the attack phase. Tofu (empty reaction_text) routes through
RiddleBox.show_reaction's fallback to hide() and behaves exactly as
before. Remove the now-unused AnnouncementBanner.show_message helper.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Update CONTEXT.md

**Files:**
- Modify: `CONTEXT.md` (Riddle / Dialogue Prompt definition)

- [ ] **Step 1: Update the visibility contract on the Riddle / Dialogue Prompt line**

In `CONTEXT.md`, locate the line:

```
- **Riddle / Dialogue Prompt** — A piece of opponent content with a body (text or image) and three answers (each text or image). Visible during a Riddle Encounter; hidden during a Riddle Gap. Sits behind WASD prompts in z-order when visible. Answer cards are shuffled per display: each time `RiddleBox.display(prompt)` is called, the three answers are reshuffled before being placed into the left/middle/right slots.
```

Replace the sentence "Visible during a Riddle Encounter; hidden during a Riddle Gap." with:

```
Visible during a Riddle Encounter. During a Riddle Gap the box is hidden by default, or remains mounted in the **Reaction State** if the picked answer carried a non-empty `reaction_text`.
```

- [ ] **Step 2: Add a new bullet defining Reaction State**

Immediately after the Riddle / Dialogue Prompt bullet, add:

```
- **Reaction State** — Post-answer beat that runs inside the existing Riddle Gap. The body area renders the picked `DialogueAnswer.reaction_text` via the same typewriter used for prompt bodies; only the picked answer card remains visible in its shuffled slot; menu input (`menu_left` / `menu_up` / `menu_right` / `menu_confirm`) is ignored. Tofu's deck (image-only) skips Reaction State because its answers have empty `reaction_text` — RiddleBox falls back to `hide()` in that case. On the WRONG path, Reaction State persists through the breather gap until the next prompt loads. On the NEUTRAL path, it persists for `MatchPacing.TRY_AGAIN_BANNER` seconds (the "Try again!" banner is gone; the reaction line is what the player reads) until the same prompt re-displays. On the RIGHT path, it persists into the Attack Phase show/repeat until the first registered W/A/S/D press, which hides the riddle for the rest of the phase; an attack timeout leaves the reaction visible through `_return_to_defense` until the next prompt loads.
```

- [ ] **Step 3: Commit**

```bash
git add CONTEXT.md
git commit -m "$(cat <<'EOF'
docs(context): document the Reaction State on the riddle box

Update the visibility contract for the Riddle / Dialogue Prompt entry
and add a new bullet describing the Reaction State. Covers all three
outcome paths and the tofu (empty reaction_text) fallback.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Self-review checklist

- **Spec coverage** —
  - DialogueAnswer.reaction_text + has_reaction(): Task 1 ✓
  - RiddleBox NORMAL/REACTION state machine + show_reaction(): Task 3 ✓
  - Empty-reaction fallback to hide(): Task 3 ✓
  - Confirm calls show_reaction synchronously before emitting answer_submitted: Task 3 ✓
  - _unhandled_input REACTION early-return: Task 3 ✓
  - Drop _riddle.visible = false snap-hide: Task 5 ✓
  - Replace "Try again!" banner with bare timer: Task 5 ✓
  - AttackPhase.first_input_received signal: Task 4 ✓
  - Gameplay hooks first_input_received → _riddle.hide(): Task 5 ✓
  - Minty deck files + wiring: Task 2 ✓
  - CONTEXT.md updates: Task 6 ✓
  - Test coverage (DialogueAnswer, RiddleBox, AttackPhase signal, Minty deck smoke): all ✓
  - Manual in-engine verification per outcome + tofu regression: Task 5 step 7 ✓

- **Followups deferred** (from spec):
  - Sebastian deck — out of scope.
  - Reaction text length budget — out of scope, revisit if real-world authoring produces long reactions.
  - Reaction polish on RIGHT (slide-to-center, outcome tint) — out of scope.
