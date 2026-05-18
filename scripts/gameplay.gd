extends Control

signal _continue_pressed

@onready var _riddle: RiddleBox = $RiddleBox
@onready var _timer_view: MatchTimerView = $MatchTimer
@onready var _banner: AnnouncementBanner = $AnnouncementBanner
@onready var _opponent: Opponent = $Opponent

var _clock := MatchClock.new()
var _transitioning: bool = false
var _awaiting_continue: bool = false

func _ready() -> void:
	_opponent.configure("tofu")
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

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F8:
		_clock.tick(280.0)
		return
	if _awaiting_continue and event.is_action_pressed("menu_confirm"):
		_awaiting_continue = false
		_continue_pressed.emit()

func _handle_round_end() -> void:
	_transitioning = true
	_clock.pause()
	_riddle.visible = false
	if _clock.current_round() >= MatchClock.TOTAL_ROUNDS:
		await _banner.show_message("Round Over!", 3.0)
		Globals.last_match_outcome = Globals.MatchOutcome.DRAW
		SceneRouter.goto_match_results()
		return
	await _banner.show_message("Round Over!", 3.0)
	_banner.show_prompt("Press K to start Round %d" % (_clock.current_round() + 1))
	await _wait_for_continue()
	_banner.dismiss()
	_clock.advance_to_next_round()
	await _play_ready_fight()
	_riddle.visible = true
	_clock.start()
	_transitioning = false

func _wait_for_continue() -> void:
	_awaiting_continue = true
	await _continue_pressed

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
