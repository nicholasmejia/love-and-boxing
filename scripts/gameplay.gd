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
@onready var _input_bar: InputTimerBar = $InputTimerBar
@onready var _combo_meter: ComboMeter = $ComboMeter
@onready var _knockdown_meter: KnockdownMeter = $KnockdownMeter
@onready var _damage_effect: DamageEffect = $DamageEffect

var _clock := MatchClock.new()
var _hearts := Hearts.new()
var _defense: DefensePhase
var _combo := ComboState.new()
var _knockdowns := Knockdowns.new()
var _attack: AttackPhase
var _in_attack: bool = false
var _deck := DialogueDeck.new()
var _transitioning: bool = false
var _awaiting_continue: bool = false
var _visibility: int = RiddleVisibility.FRESH_START_GAP
var _gap_generation: int = 0
var _current_prompt: DialoguePrompt

const _BLOCK_FLASH_SECONDS := 0.15
const _DAMAGE_HIT_SECONDS := 0.35
const _PUNCH_FLASH_SECONDS := 0.15
const _MISS_FLASH_SECONDS := 0.35

func _ready() -> void:
	var config: DifficultyConfig = Globals.selected_difficulty
	if config == null:
		config = load("res://data/difficulty/tofu.tres") as DifficultyConfig
	var bg_path := "res://assets/sprites/background.png"
	if ResourceLoader.exists(bg_path):
		$Background.texture = load(bg_path)
	_opponent.configure(config.opponent_slug)
	Globals.last_played_tier = config.tier
	Globals.last_match_outcome = Globals.MatchOutcome.DRAW
	$EndButton.pressed.connect(SceneRouter.goto_match_results)
	_defense = DefensePhase.new()
	add_child(_defense)
	_defense.step_seconds = config.show_phase_step_seconds
	_defense.input_window_seconds = config.repeat_phase_window_seconds
	_defense.step_flashed.connect(_on_step_flashed)
	_defense.step_blocked.connect(_on_step_blocked)
	_defense.damage_taken.connect(_on_damage_taken)
	_defense.repeat_started.connect(_on_repeat_started)
	_defense.sequence_completed.connect(_input_bar.cancel)
	_defense.show_started.connect(_on_show_started)
	_attack = AttackPhase.new()
	add_child(_attack)
	_attack.step_seconds = config.show_phase_step_seconds
	_attack.input_window_seconds = config.repeat_phase_window_seconds
	_attack.show_started.connect(_on_show_started)
	_attack.step_flashed.connect(_on_attack_step_flashed)
	_attack.repeat_started.connect(_on_attack_repeat_started)
	_attack.step_landed.connect(_on_attack_step_landed)
	_attack.attack_succeeded.connect(_on_attack_succeeded)
	_attack.attack_failed.connect(_on_attack_failed)
	var deck_path := config.dialogue_deck_path
	if deck_path == "" or not ResourceLoader.exists(deck_path):
		deck_path = "res://data/dialogue/tofu/deck.tres"
	var deck_res := load(deck_path) as DialogueDeckResource
	_deck.load_tier(0, deck_res.tier_0)
	_deck.load_tier(1, deck_res.tier_1)
	_deck.load_tier(2, deck_res.tier_2)
	_deck.set_active_tier(_knockdowns.count())
	_riddle.answer_submitted.connect(_on_answer_submitted)
	_riddle.visible = false
	_refresh_heart_row()
	_refresh_combo_meter()
	_refresh_knockdown_meter()
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

func _handle_round_end() -> void:
	if _in_attack:
		return  # let attack finish; round-end check re-fires after attack exit
	_transitioning = true
	_clock.pause()
	_defense.stop()
	_input_bar.cancel()
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
	_deck.reset()
	_hearts.heal()
	_knockdowns.apply_round_end_decrement()
	_deck.set_active_tier(_knockdowns.count())
	_combo.on_knockdown_completed()
	_refresh_heart_row()
	_refresh_knockdown_meter()
	_refresh_combo_meter()
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
	_show_next_prompt()
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
	_show_next_prompt()
	_riddle.visible = true

func _on_step_flashed(direction: int) -> void:
	# Show phase telegraphs via the WASD prompt only — the opponent stays in
	# IDLE until the player actually engages in the repeat phase.
	_prompts.flash(direction, _defense.step_seconds)

func _on_repeat_started() -> void:
	_input_bar.start(_defense.input_window_seconds)

func _on_show_started(_steps: Array) -> void:
	# Defensive: ensure no leftover bar from a prior phase.
	_input_bar.cancel()

func _on_step_blocked(index: int) -> void:
	AudioBus.play_sfx("block")
	var direction: int = _defense.current_sequence().steps()[index]
	var side: int = PlayerGloves.Side.RIGHT if direction == SimonSequence.Direction.RIGHT else PlayerGloves.Side.LEFT
	# Reset the input-window bar for the next keystroke. If this was the last
	# step, sequence_completed fires immediately after and cancels it (synchronous,
	# same frame — no flicker).
	_input_bar.start(_defense.input_window_seconds)
	# SUCCESS flash, opponent swing, and glove BLOCK pose all land on the same
	# frame so the block reads as a single beat.
	_prompts.flash_success(direction, _BLOCK_FLASH_SECONDS)
	_swing_opponent_for(direction)
	_gloves.set_state(side, PlayerGloves.State.BLOCK)
	await get_tree().create_timer(_BLOCK_FLASH_SECONDS).timeout
	_gloves.set_state(side, PlayerGloves.State.IDLE)
	_opponent_idle()

func _on_damage_taken(expected_direction: int) -> void:
	_input_bar.cancel()
	# FAIL flashes at the EXPECTED direction (the direction the opponent is
	# punching), not the wrong key the player pressed. This makes the timeout
	# and wrong-key cases identical visually and reads as "you needed to block
	# W, you didn't — here's W coming at you".
	_prompts.flash_fail(expected_direction, _DAMAGE_HIT_SECONDS)
	# Punch lands at the direction the player failed to block; gloves stay idle.
	_swing_opponent_for(expected_direction)
	_hearts.take_damage()
	AudioBus.play_sfx("hurt")
	_refresh_heart_row()
	_combo.on_damage_taken()
	_refresh_combo_meter()
	_damage_effect.play()
	if _hearts.is_empty():
		_end_match_loss()
		return
	_begin_breather_gap()
	# Hold the punch frame briefly so the hit reads, then recover to IDLE before
	# the new show phase's first step lands (interlude_seconds after the damage).
	await get_tree().create_timer(_DAMAGE_HIT_SECONDS).timeout
	_opponent_idle()

func _refresh_heart_row() -> void:
	_heart_row.set_hearts(_hearts.current())

func _end_match_loss() -> void:
	_transitioning = true
	_clock.pause()
	_defense.stop()
	_input_bar.cancel()
	_prompts.hide_all()
	_riddle.visible = false
	_gap_generation += 1  # invalidate any in-flight gap awaits
	await _banner.show_message("You Lose!", MatchPacing.ROUND_OVER_BANNER)
	Globals.last_match_outcome = Globals.MatchOutcome.LOSE
	SceneRouter.goto_match_results()

func _swing_opponent_for(direction: int) -> void:
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

func _hit_opponent_for(direction: int) -> void:
	var action_dir := Opponent.Direction.LEFT
	var action: int
	match direction:
		SimonSequence.Direction.HEAD:
			action = Opponent.Action.HIT_HIGH
		SimonSequence.Direction.BODY:
			action = Opponent.Action.HIT_LOW
		SimonSequence.Direction.LEFT:
			action = Opponent.Action.HIT_LOW
		SimonSequence.Direction.RIGHT:
			action = Opponent.Action.HIT_LOW
			action_dir = Opponent.Direction.RIGHT
		_:
			action = Opponent.Action.IDLE
	_opponent.set_action(action, action_dir)

func _opponent_idle() -> void:
	_opponent.set_action(Opponent.Action.IDLE, Opponent.Direction.LEFT)

func _show_next_prompt() -> void:
	_current_prompt = _deck.draw()
	assert(_current_prompt != null, "DialogueDeck.draw() returned null — deck not loaded?")
	_riddle.display(_current_prompt)

func _snap_clear_simon_visuals() -> void:
	_prompts.hide_all()
	_input_bar.cancel()
	_gloves.set_state(PlayerGloves.Side.LEFT, PlayerGloves.State.IDLE)
	_gloves.set_state(PlayerGloves.Side.RIGHT, PlayerGloves.State.IDLE)
	_opponent.set_action(Opponent.Action.IDLE, Opponent.Direction.LEFT)

func _refresh_combo_meter() -> void:
	_combo_meter.set_level(_combo.level())

func _refresh_knockdown_meter() -> void:
	_knockdown_meter.set_count(_knockdowns.count())

func _glove_side_for(direction: int) -> int:
	# D-hook lands with the right glove; everything else uses the left glove,
	# matching the block-side convention in _on_step_blocked.
	return PlayerGloves.Side.RIGHT if direction == SimonSequence.Direction.RIGHT else PlayerGloves.Side.LEFT

func _trigger_attack_phase() -> void:
	_in_attack = true
	_defense.stop()
	_snap_clear_simon_visuals()
	_opponent.set_action(Opponent.Action.GUARD_DOWN, Opponent.Direction.LEFT)
	_attack.begin(_combo.input_count())

func _on_attack_step_flashed(direction: int) -> void:
	_prompts.flash(direction, _attack.step_seconds)

func _on_attack_repeat_started() -> void:
	_input_bar.start(_attack.input_window_seconds)

func _on_attack_step_landed(index: int) -> void:
	AudioBus.play_sfx("punch")
	var direction: int = _attack.current_sequence().steps()[index]
	var side: int = _glove_side_for(direction)
	# Restart the input-window bar for the next attack keystroke. The final
	# step's attack_succeeded handler cancels it synchronously (same frame —
	# no flicker), matching the defense-side block flow.
	_input_bar.start(_attack.input_window_seconds)
	_prompts.flash_success(direction, _PUNCH_FLASH_SECONDS)
	_hit_opponent_for(direction)
	_gloves.set_state(side, PlayerGloves.State.PUNCH)
	# The 0.15s glove-IDLE reset can land during the Knock Down banner if this
	# was the x3 finisher step — visually benign (the glove is going to IDLE
	# regardless), but worth knowing the awaits overlap on that one frame.
	await get_tree().create_timer(_PUNCH_FLASH_SECONDS).timeout
	_gloves.set_state(side, PlayerGloves.State.IDLE)
	# Skip the GUARD_DOWN reset when attack has ended — _play_knockdown_sequence
	# has set KNOCKED_DOWN, or _return_to_defense has set IDLE; both flip _in_attack.
	if _in_attack:
		_opponent.set_action(Opponent.Action.GUARD_DOWN, Opponent.Direction.LEFT)

func _on_attack_succeeded() -> void:
	_input_bar.cancel()
	# Hold the final HIT sprite for the same dwell non-final steps get.
	# AttackPhase emits step_landed and attack_succeeded synchronously back-to-back
	# on the last input — without this await, KNOCKED_DOWN or IDLE would clobber
	# the HIT sprite within the same frame, before any render.
	await get_tree().create_timer(_PUNCH_FLASH_SECONDS).timeout
	if _combo.is_at_knockdown_threshold():
		await _play_knockdown_sequence()
	else:
		_combo.on_attack_success()
		_refresh_combo_meter()
		_return_to_defense()

func _on_attack_failed(expected_direction: int) -> void:
	# CONTEXT.md → "Combo": failed attack inputs do not reset combo. We just
	# flash the missed key (mirrors the defense-fail flash) and return to
	# defense. flash_fail shows the _fail.png variant at the EXPECTED direction
	# so the wrong-key and timeout cases read identically.
	_input_bar.cancel()
	_prompts.flash_fail(expected_direction, _MISS_FLASH_SECONDS)
	_return_to_defense()

func _return_to_defense() -> void:
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
	# Defensive snap-clear: the x3 finisher's flash_success and glove-PUNCH can
	# still be on screen as we land here. Matches the snap-clear pattern used
	# everywhere else a banner takes over the frame (round end, match loss,
	# attack-phase entry).
	_snap_clear_simon_visuals()
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
	_deck.set_active_tier(_knockdowns.count())
	_combo.on_knockdown_completed()
	_refresh_combo_meter()
	_opponent_idle()
	_clock.resume()
	# CONTEXT.md → Fresh-Start Gap is the post-knockdown entry, not Breather Gap.
	# Defense restarts inside _begin_fresh_start_gap() after the 1s dead-air front.
	_defense.stop()
	_begin_fresh_start_gap()

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
	match outcome:
		Outcome.Type.WRONG:
			# Snap-clear first so leftover Simon visuals don't co-exist with the
			# new opponent swing pose.
			_snap_clear_simon_visuals()

			assert(_defense.current_sequence().length() > 0, "WRONG submitted with empty Simon chain")
			var hit_direction: int = _defense.current_sequence().steps()[0]
			_swing_opponent_for(hit_direction)
			_hearts.take_damage()
			AudioBus.play_sfx("hurt")
			_refresh_heart_row()
			_combo.on_damage_taken()
			_refresh_combo_meter()
			_damage_effect.play()
			if _hearts.is_empty():
				_end_match_loss()
				return

			# Reset Simon chain (CONTEXT.md → Outcome: wrong resets chain).
			# stop() clears _running so any in-flight show-phase awaits bail
			# out; start() reseeds the sequence at length 1 and reschedules a
			# fresh show phase after interlude_seconds.
			_defense.stop()
			_defense.start()
			_begin_breather_gap()

			# Hold the punch frame briefly so the hit reads, then recover to IDLE.
			# Runs in parallel with the 4s gap (same pattern as _on_damage_taken).
			await get_tree().create_timer(_DAMAGE_HIT_SECONDS).timeout
			_opponent_idle()
		Outcome.Type.NEUTRAL:
			# "Try again!" hint: snap-clear leftover Simon visuals, stop the
			# current chain, show the banner, then re-display the SAME prompt
			# (cards reshuffle on display) and replay the chain at its current
			# length from step 0.
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
		Outcome.Type.RIGHT:
			_trigger_attack_phase()
