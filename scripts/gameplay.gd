extends Control

signal _continue_pressed

enum RiddleVisibility {
	ENCOUNTER,         # riddle box visible, player can answer
	FRESH_START_GAP,   # riddle hidden, dead-air-then-defense at round start
	BREATHER_GAP,      # riddle hidden, defense active after Simon damage
}

@onready var _riddle: RiddleBox = $RiddleBox
@onready var _timer_view: MatchTimerView = $MatchTimer
@onready var _banner: AnnouncementBanner = $AnnouncementBanner
@onready var _opponent: Opponent = $Opponent
@onready var _prompts: WasdPromptLayer = $WasdPromptLayer
@onready var _gloves: PlayerGloves = $PlayerGloves
@onready var _heart_row: HeartRow = $HeartRow

var _clock := MatchClock.new()
var _hearts := Hearts.new()
var _defense: DefensePhase
var _transitioning: bool = false
var _awaiting_continue: bool = false
var _visibility: int = RiddleVisibility.FRESH_START_GAP
var _gap_generation: int = 0

const _BLOCK_FLASH_SECONDS := 0.15

func _ready() -> void:
	_opponent.configure("tofu")
	Globals.last_played_tier = 1
	Globals.last_match_outcome = Globals.MatchOutcome.DRAW
	$EndButton.pressed.connect(SceneRouter.goto_match_results)
	_defense = DefensePhase.new()
	add_child(_defense)
	_defense.step_flashed.connect(_on_step_flashed)
	_defense.step_blocked.connect(_on_step_blocked)
	_defense.damage_taken.connect(_on_damage_taken)
	_riddle.visible = false
	_refresh_heart_row()
	_start_round_one()

func _start_round_one() -> void:
	await _play_ready_fight()
	_clock.start()
	_begin_fresh_start_gap()

func _process(delta: float) -> void:
	if _transitioning:
		return
	_clock.tick(delta)
	_timer_view.set_seconds(_clock.seconds_remaining())
	if _clock.is_round_over():
		_handle_round_end()

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
	if event.is_action_pressed("attack_head"):
		_defense.player_input(SimonSequence.Direction.HEAD)
	elif event.is_action_pressed("attack_left"):
		_defense.player_input(SimonSequence.Direction.LEFT)
	elif event.is_action_pressed("attack_body"):
		_defense.player_input(SimonSequence.Direction.BODY)
	elif event.is_action_pressed("attack_right"):
		_defense.player_input(SimonSequence.Direction.RIGHT)

func _handle_round_end() -> void:
	_transitioning = true
	_clock.pause()
	_defense.stop()
	_prompts.hide_all()
	_riddle.visible = false
	_visibility = RiddleVisibility.FRESH_START_GAP
	_gap_generation += 1  # invalidate any in-flight gap awaits
	if _clock.current_round() >= MatchClock.TOTAL_ROUNDS:
		await _banner.show_message("Round Over!", MatchPacing.ROUND_OVER_BANNER)
		Globals.last_match_outcome = Globals.MatchOutcome.DRAW
		SceneRouter.goto_match_results()
		return
	await _banner.show_message("Round Over!", MatchPacing.ROUND_OVER_BANNER)
	_banner.show_prompt("Press K to start Round %d" % (_clock.current_round() + 1))
	await _wait_for_continue()
	_banner.dismiss()
	_clock.advance_to_next_round()
	await _play_ready_fight()
	_clock.start()
	_transitioning = false
	_begin_fresh_start_gap()

func _wait_for_continue() -> void:
	_awaiting_continue = true
	await _continue_pressed

func _play_ready_fight() -> void:
	await _banner.show_message("Ready?", MatchPacing.READY_BANNER)
	await _banner.show_message("Fight!", MatchPacing.FIGHT_BANNER)

# Fresh-Start Gap (CONTEXT.md → Riddle Gap):
#   total: MatchPacing.FRESH_START_GAP seconds, riddle hidden throughout.
#   front MatchPacing.FRESH_START_DEAD_AIR seconds: dead air, opponent idle, defense paused.
#   remainder: defense show phase active, riddle still hidden.
#   at gap end: snap riddle in (encounter starts).
func _begin_fresh_start_gap() -> void:
	_visibility = RiddleVisibility.FRESH_START_GAP
	_gap_generation += 1
	var my_generation := _gap_generation
	_riddle.visible = false
	_prompts.hide_all()
	_opponent.set_action(Opponent.Action.IDLE, Opponent.Direction.LEFT)
	# Dead-air front segment: defense paused, opponent idle.
	await get_tree().create_timer(MatchPacing.FRESH_START_DEAD_AIR).timeout
	if my_generation != _gap_generation:
		return
	# Defense activates for the remainder of the gap, riddle still hidden.
	_defense.start()
	var remainder := MatchPacing.FRESH_START_GAP - MatchPacing.FRESH_START_DEAD_AIR
	await get_tree().create_timer(remainder).timeout
	if my_generation != _gap_generation:
		return
	_visibility = RiddleVisibility.ENCOUNTER
	_show_placeholder_prompt()
	_riddle.visible = true

# Breather Gap (CONTEXT.md → Riddle Gap / Riddle Encounter Visibility):
#   Triggered on Simon damage. MatchPacing.BREATHER_GAP seconds, riddle hidden.
#   Defense is NOT paused (DefensePhase already reset its sequence and is starting
#   a new shorter show phase). Clock is NOT paused.
#   Consecutive damage during the gap resets the timer via _gap_generation.
func _begin_breather_gap() -> void:
	_visibility = RiddleVisibility.BREATHER_GAP
	_gap_generation += 1
	var my_generation := _gap_generation
	_riddle.visible = false
	await get_tree().create_timer(MatchPacing.BREATHER_GAP).timeout
	if my_generation != _gap_generation:
		return
	_visibility = RiddleVisibility.ENCOUNTER
	_show_placeholder_prompt()
	_riddle.visible = true

func _on_step_flashed(direction: int) -> void:
	_prompts.flash(direction, _defense.step_seconds)
	_animate_opponent_punch(direction)

func _on_step_blocked(index: int) -> void:
	AudioBus.play_sfx("block")
	var direction: int = _defense.current_sequence().steps()[index]
	var side: int = PlayerGloves.Side.LEFT
	if direction == SimonSequence.Direction.RIGHT:
		side = PlayerGloves.Side.RIGHT
	# HEAD, BODY, LEFT all blocked by LEFT glove per plan rule.
	_gloves.set_state(side, PlayerGloves.State.BLOCK)
	await get_tree().create_timer(_BLOCK_FLASH_SECONDS).timeout
	_gloves.set_state(side, PlayerGloves.State.IDLE)

func _on_damage_taken() -> void:
	_hearts.take_damage()
	AudioBus.play_sfx("hurt")
	_refresh_heart_row()
	_opponent.set_action(Opponent.Action.IDLE, Opponent.Direction.LEFT)
	if _hearts.is_empty():
		_end_match_loss()
		return
	_begin_breather_gap()

func _refresh_heart_row() -> void:
	_heart_row.set_hearts(_hearts.current())

func _end_match_loss() -> void:
	_transitioning = true
	_clock.pause()
	_defense.stop()
	_prompts.hide_all()
	_riddle.visible = false
	_gap_generation += 1  # invalidate any in-flight gap awaits
	await _banner.show_message("You Lose!", MatchPacing.ROUND_OVER_BANNER)
	Globals.last_match_outcome = Globals.MatchOutcome.LOSE
	SceneRouter.goto_match_results()

func _animate_opponent_punch(direction: int) -> void:
	var action_dir := Opponent.Direction.LEFT
	var action: int
	match direction:
		SimonSequence.Direction.HEAD:
			action = Opponent.Action.SWING_HIGH
		SimonSequence.Direction.BODY:
			action = Opponent.Action.SWING_MID
		SimonSequence.Direction.LEFT:
			action = Opponent.Action.SWING_LOW
		SimonSequence.Direction.RIGHT:
			action = Opponent.Action.SWING_LOW
			action_dir = Opponent.Direction.RIGHT
		_:
			action = Opponent.Action.IDLE
	_opponent.set_action(action, action_dir)
	await get_tree().create_timer(_defense.step_seconds).timeout
	_opponent.set_action(Opponent.Action.IDLE, Opponent.Direction.LEFT)

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
