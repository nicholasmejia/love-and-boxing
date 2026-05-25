extends Control

signal _continue_pressed

enum RiddleVisibility {
	ENCOUNTER,         # riddle box visible, player can answer
	FRESH_START_GAP,   # riddle hidden, dead-air-then-defense at round start
	BREATHER_GAP,      # riddle hidden, defense active after Simon damage
}

@onready var _riddle: RiddleBox = $RiddleBox
@onready var _carousel: AnswerCarousel = $AnswerCarousel
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
@onready var _pause_menu: PauseMenu = $PauseMenu

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
# Per-step generation counters for the block/punch display awaits. Each
# step_landed bumps its counter; a stale handler whose generation no longer
# matches returns without resetting visuals, so a faster next-step input owns
# cleanup instead of clobbering the in-flight tween.
var _defense_step_generation: int = 0
var _attack_step_generation: int = 0
var _current_prompt: DialoguePrompt
var _bgm_stream: AudioStream = null
var _bgm_track_id: String = ""
var _damage_multiplier: int = 1

const _BLOCK_FLASH_SECONDS := 0.30
const _DAMAGE_HIT_SECONDS := 0.35
const _PUNCH_FLASH_SECONDS := 0.30
const _MISS_FLASH_SECONDS := 0.35
const _BGM_END_FADE_SECONDS := 1.5

func _ready() -> void:
	AudioBus.stop_music()
	var config: DifficultyConfig = Globals.selected_difficulty
	if config == null:
		config = load("res://data/difficulty/tofu.tres") as DifficultyConfig
	if config.bgm_track_path != "" and ResourceLoader.exists(config.bgm_track_path):
		_bgm_stream = load(config.bgm_track_path) as AudioStream
		_bgm_track_id = config.opponent_slug
	var bg_path := "res://assets/sprites/background.png"
	if ResourceLoader.exists(bg_path):
		$Background.texture = load(bg_path)
	var profile_path := config.animation_profile_path
	if profile_path == "" or not ResourceLoader.exists(profile_path):
		profile_path = "res://data/opponent_animation/tofu.tres"
	var profile := load(profile_path) as OpponentAnimationProfile
	_opponent.configure(config.opponent_slug, profile)
	Globals.last_played_tier = config.tier
	Globals.last_match_outcome = Globals.MatchOutcome.DRAW
	$EndButton.pressed.connect(SceneRouter.goto_match_results)
	_defense = DefensePhase.new()
	add_child(_defense)
	_defense.step_seconds = config.show_phase_step_seconds
	_defense.input_window_seconds = config.repeat_phase_window_seconds
	_defense.sequence_growth = config.combo_input_step
	_combo.set_input_step(config.combo_input_step)
	_damage_multiplier = max(1, config.damage_multiplier)
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
	_attack.first_input_received.connect(_on_attack_first_input)
	var deck_path := config.dialogue_deck_path
	if deck_path == "" or not ResourceLoader.exists(deck_path):
		deck_path = "res://data/dialogue/tofu/deck.tres"
	var deck_res := load(deck_path) as DialogueDeckResource
	_deck.load_tier(0, deck_res.tier_0)
	_deck.load_tier(1, deck_res.tier_1)
	_deck.load_tier(2, deck_res.tier_2)
	_deck.set_active_tier(_knockdowns.count())
	_carousel.answer_submitted.connect(_on_answer_submitted)
	_carousel.answer_committed.connect(_on_answer_committed)
	_carousel.set_player_gloves(_gloves)
	# Opponent body global position varies as the opponent lunges/recoils, so
	# capture it lazily per flight via a callback that re-reads the position
	# at the moment the carousel needs it.
	# Body global position is around y=1220 (Opponent at y=400 + Body local y=820),
	# which sits in the lower-third of the screen (groin/waist on the on-screen
	# character art). Raise the target to ~y=470 — solidly on-chest — by
	# offsetting up by 750px.
	const CARD_TARGET_CHEST_OFFSET := Vector2(-100, -650)
	_carousel.set_opponent_target_callback(func(): return _opponent.get_node("Body").global_position + CARD_TARGET_CHEST_OFFSET)
	_carousel.card_struck_opponent.connect(_on_card_struck_opponent)
	# Forward the body-render-complete signal to the carousel's fade-in.
	_riddle.body_render_complete.connect(_carousel.start_fade_in)
	_riddle.visible = false
	_carousel.visible = false
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
	if event is InputEventKey and event.pressed and event.keycode == KEY_F9:
		_play_knockdown_sequence()
		return
	if event.is_action_pressed("ui_cancel"):
		_pause_menu.open()
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
	_carousel.visible = false
	_visibility = RiddleVisibility.FRESH_START_GAP
	_gap_generation += 1  # invalidate any in-flight gap awaits
	if _clock.current_round() >= MatchClock.TOTAL_ROUNDS:
		AudioBus.stop_music(_BGM_END_FADE_SECONDS)
		AudioBus.play_sfx("round_end")
		await _banner.show_banner("round_over", MatchPacing.ROUND_OVER_BANNER)
		await _banner.show_banner("draw", MatchPacing.DRAW_BANNER)
		Globals.last_match_outcome = Globals.MatchOutcome.DRAW
		SceneRouter.goto_match_results()
		return
	AudioBus.play_sfx("round_end")
	await _banner.show_banner("round_over", MatchPacing.ROUND_OVER_BANNER)
	_banner.show_prompt("Press K to start Round %d" % (_clock.current_round() + 1))
	await _wait_for_continue()
	await _banner.dismiss()
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
	# Settle beat before the Ready slide-in so the player's eye lands on the
	# empty match scene first instead of catching the banner already in motion.
	await get_tree().create_timer(MatchPacing.PRE_READY_DELAY, false).timeout
	await _banner.show_banner("ready", MatchPacing.READY_BANNER)
	# Opponent BGM starts in sync with the Fight banner. Round 2's call no-ops
	# against the Track ID that's already playing from Round 1.
	if _bgm_stream != null:
		AudioBus.play_music_stream(_bgm_stream, _bgm_track_id)
	AudioBus.play_sfx("round_start")
	await _banner.show_banner("fight", MatchPacing.FIGHT_BANNER)

# Fresh-Start Gap (CONTEXT.md → Riddle Gap + Riddle Render Gate):
#   MatchPacing.FRESH_START_SETTLE seconds with riddle hidden, opponent idle, defense paused.
#   Then the prompt loads and the Riddle Render Gate begins — typewriter (or instant
#   for image bodies) followed by MatchPacing.RIDDLE_READ_FLOOR seconds. DefensePhase
#   activates at the end of the gate, never earlier.
func _begin_fresh_start_gap() -> void:
	_visibility = RiddleVisibility.FRESH_START_GAP
	_gap_generation += 1
	var my_generation := _gap_generation
	# Preserve REACTION-state riddle (RIGHT-timeout path can route here via
	# _return_to_defense). Empty-reaction prompts (tofu) and pre-prompt
	# entries are already hidden by RiddleBox itself.
	if _riddle.get_state() != RiddleBox.State.REACTION:
		_riddle.visible = false
	# Keep the carousel container mounted while a per-outcome choreography is
	# in flight — the cards self-hide via tween callbacks, and hiding the
	# container now would cancel a still-rendering Card Toss / Card Rebound /
	# RIGHT flight. Display_prompt at gap-end resets all card state cleanly.
	if not _carousel.is_punching():
		_carousel.visible = false
	_prompts.hide_all()
	_opponent.set_action(Opponent.Action.IDLE, Opponent.Direction.LEFT)
	# Settle beat — opponent idle, riddle hidden, defense not yet active.
	await get_tree().create_timer(MatchPacing.FRESH_START_SETTLE, false).timeout
	if my_generation != _gap_generation:
		return
	# Open the encounter and run the render gate.
	_visibility = RiddleVisibility.ENCOUNTER
	_current_prompt = _deck.draw()
	assert(_current_prompt != null, "DialogueDeck.draw() returned null — deck not loaded?")
	_riddle.visible = true
	_carousel.visible = true
	_carousel.display_prompt(_current_prompt)
	await _riddle.display(_current_prompt)
	if my_generation != _gap_generation:
		return
	# Post-typewriter read floor — defense still paused so the player can read
	# the full prompt before being asked to block.
	await get_tree().create_timer(MatchPacing.RIDDLE_READ_FLOOR, false).timeout
	if my_generation != _gap_generation:
		return
	_defense.start()

# Breather Gap (CONTEXT.md → Riddle Gap + Riddle Render Gate):
#   Triggered on WRONG / Simon damage / attack-end (non-KO). MatchPacing.BREATHER_GAP
#   seconds with riddle in REACTION state (or hidden for empty-reaction prompts),
#   defense paused, clock running. Then the next prompt loads and the Riddle
#   Render Gate runs — typewriter + MatchPacing.RIDDLE_READ_FLOOR. DefensePhase
#   activates at the end of the gate.
#   Consecutive triggers during the gap reset the timer via _gap_generation.
func _begin_breather_gap() -> void:
	_visibility = RiddleVisibility.BREATHER_GAP
	_gap_generation += 1
	var my_generation := _gap_generation
	# Preserve REACTION-state riddle (WRONG-path reaction line lives in the box
	# through the breather; RIGHT-timeout path likewise). Empty-reaction prompts
	# (tofu) and pre-prompt entries are already hidden by RiddleBox itself.
	if _riddle.get_state() != RiddleBox.State.REACTION:
		_riddle.visible = false
	# Keep the carousel container mounted while a per-outcome choreography is
	# in flight — the cards self-hide via tween callbacks (Card Toss, Card
	# Rebound, RIGHT flight). Hiding the container synchronously on Tofu's
	# WRONG path used to cancel the Card Toss before any frame rendered.
	if not _carousel.is_punching():
		_carousel.visible = false
	await get_tree().create_timer(MatchPacing.BREATHER_GAP, false).timeout
	if my_generation != _gap_generation:
		return
	# Open the encounter and run the render gate.
	_visibility = RiddleVisibility.ENCOUNTER
	_current_prompt = _deck.draw()
	assert(_current_prompt != null, "DialogueDeck.draw() returned null — deck not loaded?")
	_riddle.visible = true
	_carousel.visible = true
	_carousel.display_prompt(_current_prompt)
	await _riddle.display(_current_prompt)
	if my_generation != _gap_generation:
		return
	# Post-typewriter read floor — defense still paused so the player can read
	# the full prompt before being asked to block.
	await get_tree().create_timer(MatchPacing.RIDDLE_READ_FLOOR, false).timeout
	if my_generation != _gap_generation:
		return
	# Fresh chain at length 1 — WRONG/damage/attack-end all reset the chain.
	_defense.start()

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
	AudioBus.play_sfx("player_block_or_hit")
	var direction: int = _defense.current_sequence().steps()[index]
	_defense_step_generation += 1
	var my_generation := _defense_step_generation
	# Reset the input-window bar for the next keystroke. If this was the last
	# step, sequence_completed fires immediately after and cancels it (synchronous,
	# same frame — no flicker).
	_input_bar.start(_defense.input_window_seconds)
	# SUCCESS flash, opponent swing, and glove BLOCK pose all land on the same
	# frame so the block reads as a single beat.
	_prompts.flash_success(direction, _BLOCK_FLASH_SECONDS)
	_swing_opponent_for(direction)
	_gloves.set_state(PlayerGloves.State.BLOCK, direction)
	await get_tree().create_timer(_BLOCK_FLASH_SECONDS, false).timeout
	# If a faster next-step input bumped the generation while we awaited, that
	# newer handler owns cleanup — bail before clobbering its in-flight pose.
	if my_generation != _defense_step_generation:
		return
	_gloves.set_state(PlayerGloves.State.IDLE)
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
	_hearts.take_damage(_damage_multiplier)
	AudioBus.play_sfx("player_block_or_hit")
	AudioBus.play_sfx("input_failure")
	if _combo.level() > 1:
		AudioBus.play_sfx("combo_reset")
	_refresh_heart_row()
	_combo.on_damage_taken()
	_refresh_combo_meter()
	_damage_effect.play(_prompts.prompt_center_global(expected_direction))
	if _hearts.is_empty():
		# Begin the opponent-BGM fade the moment the killing blow lands so the
		# track is mostly out by the time the you_lose banner + stinger fire.
		AudioBus.stop_music(_BGM_END_FADE_SECONDS)
		_end_match_loss()
		return
	_begin_breather_gap()
	# Hold the punch frame briefly so the hit reads, then recover to IDLE. The
	# next show phase doesn't land until the breather gap + render gate complete,
	# so we have plenty of time.
	await get_tree().create_timer(_DAMAGE_HIT_SECONDS, false).timeout
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
	_carousel.visible = false
	_gap_generation += 1  # invalidate any in-flight gap awaits
	AudioBus.play_music("defeat")
	AudioBus.play_sfx("round_knockout")
	_awaiting_continue = true
	await _banner.show_banner_skippable("you_lose", MatchPacing.YOU_LOSE_BANNER, _continue_pressed)
	_awaiting_continue = false
	Globals.last_match_outcome = Globals.MatchOutcome.LOSE
	SceneRouter.goto_match_results()

func _swing_opponent_for(direction: int) -> void:
	# Opponent swings layer here for every block/hurt path that routes through this
	# helper. Player attack swings fire in _on_attack_step_landed.
	AudioBus.play_sfx("swing")
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
			action = Opponent.Action.HIT_BODY
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

func _snap_clear_simon_visuals() -> void:
	_prompts.hide_all()
	_input_bar.cancel()
	_gloves.set_state(PlayerGloves.State.IDLE)
	_opponent.set_action(Opponent.Action.IDLE, Opponent.Direction.LEFT)

func _refresh_combo_meter() -> void:
	_combo_meter.set_level(_combo.level())

func _refresh_knockdown_meter() -> void:
	_knockdown_meter.set_count(_knockdowns.count())

func _trigger_attack_phase() -> void:
	_in_attack = true
	_defense.stop()
	_snap_clear_simon_visuals()
	_opponent.set_action(Opponent.Action.GUARD_DOWN_EXCITED, Opponent.Direction.LEFT)
	_attack.begin(_combo.input_count())

func _on_attack_step_flashed(direction: int) -> void:
	_prompts.flash(direction, _attack.step_seconds)

func _on_attack_repeat_started() -> void:
	_input_bar.start(_attack.input_window_seconds)

func _on_attack_step_landed(index: int) -> void:
	# Layered punch beat: player swing + body impact + the combo-position cue.
	# Index 0/1/2 within the attack sequence maps to the 1st/2nd/3rd combo_success
	# file, so a 3-hit finisher escalates audibly across its three keystrokes.
	# Clamp at the 3rd cue for high-input-step opponents (e.g. Sebastian) whose
	# finisher chain exceeds three hits — only three combo_success_*.wav exist.
	AudioBus.play_sfx("swing")
	AudioBus.play_sfx("opponent_punch_body")
	AudioBus.play_sfx("combo_success_%d_hit" % min(index + 1, 3))
	var direction: int = _attack.current_sequence().steps()[index]
	_attack_step_generation += 1
	var my_generation := _attack_step_generation
	# Restart the input-window bar for the next attack keystroke. The final
	# step's attack_succeeded handler cancels it synchronously (same frame —
	# no flicker), matching the defense-side block flow.
	_input_bar.start(_attack.input_window_seconds)
	_prompts.flash_success(direction, _PUNCH_FLASH_SECONDS, true)
	_hit_opponent_for(direction)
	_opponent.play_sweat(direction)
	_gloves.set_state(PlayerGloves.State.PUNCH, direction)
	# Wait the full flash window before resetting. If the player inputs the
	# next step faster than this await (a real risk at the x3 finisher pace),
	# that step bumps _attack_step_generation and this handler bails below —
	# otherwise we'd snap the next step's in-flight punch tween mid-pose and
	# clobber its opponent HIT sprite.
	await get_tree().create_timer(_PUNCH_FLASH_SECONDS, false).timeout
	if my_generation != _attack_step_generation:
		return
	_gloves.set_state(PlayerGloves.State.IDLE)
	# Skip the GUARD_DOWN reset when attack has ended — _play_knockdown_sequence
	# is mid-fall/recover, or _return_to_defense has set IDLE; both flip _in_attack.
	if _in_attack:
		_opponent.set_action(Opponent.Action.GUARD_DOWN, Opponent.Direction.LEFT)

func _on_attack_succeeded() -> void:
	_input_bar.cancel()
	# Hold the final HIT sprite for the same dwell non-final steps get.
	# AttackPhase emits step_landed and attack_succeeded synchronously back-to-back
	# on the last input — without this await, KNOCKED_DOWN or IDLE would clobber
	# the HIT sprite within the same frame, before any render.
	await get_tree().create_timer(_PUNCH_FLASH_SECONDS, false).timeout
	if _combo.is_at_knockdown_threshold():
		await _play_knockdown_sequence()
	else:
		_combo.on_attack_success()
		_refresh_combo_meter()
		_return_to_defense()

func _on_attack_first_input() -> void:
	# Reaction-state riddle visible from the RIGHT-answer beat is now interrupted —
	# the player has committed to the attack phase. Hide it for the rest of the
	# phase; the next breather's display() call rebuilds in NORMAL.
	_riddle.hide()
	_carousel.hide()

func _on_attack_failed(expected_direction: int) -> void:
	# CONTEXT.md → "Combo": failed attack inputs do not reset combo. We just
	# flash the missed key (mirrors the defense-fail flash) and return to
	# defense. flash_fail shows the _fail.png variant at the EXPECTED direction
	# so the wrong-key and timeout cases read identically.
	# combo_reset audio fires here even though combo state is preserved — the
	# SFX is a "you lost your running combo" cue, paired with input_failure.
	# Skip when already at 1× since there's no combo to lose.
	AudioBus.play_sfx("input_failure")
	if _combo.level() > 1:
		AudioBus.play_sfx("combo_reset")
	_input_bar.cancel()
	_prompts.flash_fail(expected_direction, _MISS_FLASH_SECONDS, true)
	_return_to_defense()

func _return_to_defense() -> void:
	_in_attack = false
	_opponent_idle()
	# Phase transition resets the Simon chain to length 1 (CONTEXT.md → Simon
	# Sequence). stop() clears any in-flight show generation; the breather gap
	# will call start() at the end of its render gate to reseed at length 1.
	_defense.stop()
	_begin_breather_gap()

func _play_knockdown_sequence() -> void:
	_in_attack = false
	_clock.pause()
	# Defensive snap-clear: the x3 finisher's flash_success and glove-PUNCH can
	# still be on screen as we land here. Matches the snap-clear pattern used
	# everywhere else a banner takes over the frame (round end, match loss,
	# attack-phase entry).
	_snap_clear_simon_visuals()
	# Internal state ticks now so is_knockout() drives the BGM fade and the
	# downstream branch at the right beat — but the meter's UI tick is held
	# until the banner flies into the icon below.
	_knockdowns.increment()
	if _knockdowns.is_knockout():
		# Begin the opponent-BGM fade the instant the KO knockdown lands so the
		# track is fully out under the knock_down + knock_out banners ahead of
		# the you_win stinger.
		AudioBus.stop_music(_BGM_END_FADE_SECONDS)
	await _opponent.play_knockdown_fall()
	# Banner slides in, holds, then flies into the KnockdownMeter icon. The
	# counter increments + pulses the moment the banner lands, selling the
	# "delivered hit" feedback.
	await _banner.show_banner_then_fly_to("knock_down", MatchPacing.KNOCK_DOWN_BANNER, _knockdown_meter.icon_global_center())
	_refresh_knockdown_meter()
	# Knockdown reward: regain one heart (capped at MAX_HEARTS) so the player
	# trades successful punches for survivability.
	_hearts.heal()
	_refresh_heart_row()
	# KNOCKDOWN_PAUSE is the total clock-pause duration; the banner ate part of
	# it, hold the remainder before resuming the clock. The banner's wall-clock
	# now includes its slide-in + hold + fly-to-target, so derive the remainder
	# via AnnouncementBanner.total_duration_with_fly() — the raw hold constant
	# would under-count and shorten the post-knockdown pause.
	var remainder := MatchPacing.KNOCKDOWN_PAUSE - AnnouncementBanner.total_duration_with_fly(MatchPacing.KNOCK_DOWN_BANNER)
	if remainder > 0.0:
		await get_tree().create_timer(remainder, false).timeout
	if _knockdowns.is_knockout():
		AudioBus.play_sfx("round_knockout")
		await _banner.show_banner("knock_out", MatchPacing.KNOCK_OUT_BANNER)
		AudioBus.play_music("victory")
		_awaiting_continue = true
		await _banner.show_banner_skippable("you_win", MatchPacing.YOU_WIN_BANNER, _continue_pressed)
		_awaiting_continue = false
		Globals.last_match_outcome = Globals.MatchOutcome.WIN
		SceneRouter.goto_match_results()
		return
	_deck.set_active_tier(_knockdowns.count())
	_combo.on_knockdown_completed()
	_refresh_combo_meter()
	await _opponent.play_knockdown_recover()
	_clock.resume()
	# CONTEXT.md → Fresh-Start Gap is the post-knockdown entry, not Breather Gap.
	# Defense restarts inside _begin_fresh_start_gap() after the 1s dead-air front.
	_defense.stop()
	_begin_fresh_start_gap()

# K-press commit beat — fires synchronously from AnswerCarousel BEFORE the
# GLOVE_TRAVEL_DURATION await that delays answer_submitted. End the Simon
# phase here so the ~150ms glove travel doesn't let stale defense activity
# leak into the attack phase:
#   - Show-loop step_flashed emissions that would visually collide with the
#     attack telegraph (or with each other on Tofu's slow 0.8s pace).
#   - Repeat-phase _on_input_timeout firing _fail_with_damage during the
#     glove travel — which would reset the combo BEFORE attack begins and
#     schedule a breather_gap whose later _defense.start() runs in parallel
#     with the active attack phase.
#   - Lingering _on_step_blocked / _on_damage_taken handlers awaiting their
#     flash windows; bumping _defense_step_generation invalidates them so
#     they can't clobber the attack opponent's GUARD_DOWN_EXCITED pose.
# answer_submitted continues to own outcome-specific choreography at the
# impact frame; the redundant _defense.stop() calls inside those branches
# remain safe no-ops.
func _on_answer_committed(_outcome: int) -> void:
	if _visibility != RiddleVisibility.ENCOUNTER:
		return
	_gap_generation += 1
	_defense_step_generation += 1
	_defense.stop()
	_snap_clear_simon_visuals()

# Riddle answer submission (K-press on the highlighted answer card). RiddleBox
# emits answer_submitted whenever K fires while it's mounted — including while
# the box is hidden (gaps / round transitions). The visibility gate below is
# the single source of truth for "is the player actually answering a prompt
# right now".
func _on_answer_submitted(outcome: int, picked: DialogueAnswer) -> void:
	# Route reaction text or hide the riddle body based on whether the picked
	# answer has one. The AnswerCarousel container stays mounted on both paths
	# — its per-outcome card choreography (RIGHT flight, NEUTRAL Card Rebound,
	# WRONG Card Toss) self-hides each card via tween-finished callbacks, and
	# hiding the container synchronously here would cancel those animations
	# before they render (we just emitted at the impact frame).
	if picked.has_reaction():
		_riddle.show_reaction(picked.reaction_text)
	else:
		_riddle.hide()
	if _visibility != RiddleVisibility.ENCOUNTER:
		return
	# Flip out of ENCOUNTER immediately so re-entrant K-presses bail at the
	# gate above. RiddleBox has already entered REACTION state synchronously
	# from its confirm branch (and ignores menu input there); this is the
	# belt-and-suspenders layer for the gameplay-side flow. The riddle node
	# itself stays visible — RiddleBox owns its own visibility through the
	# REACTION state and its fallback hide() for empty-reaction (tofu) prompts.
	_visibility = RiddleVisibility.BREATHER_GAP
	# Reaction emote fires at the impact frame, in parallel with the per-outcome
	# card choreography. RIGHT has no emote (the opponent is hit, not reacting).
	_opponent.play_reaction(outcome)
	match outcome:
		Outcome.Type.WRONG:
			# Snap-clear first so leftover Simon visuals don't co-exist with the
			# new opponent swing pose.
			_snap_clear_simon_visuals()

			AudioBus.play_sfx("riddle_wrong")
			assert(_defense.current_sequence().length() > 0, "WRONG submitted with empty Simon chain")
			var hit_direction: int = _defense.current_sequence().steps()[0]
			_swing_opponent_for(hit_direction)
			_hearts.take_damage(_damage_multiplier)
			AudioBus.play_sfx("player_block_or_hit")
			if _combo.level() > 1:
				AudioBus.play_sfx("combo_reset")
			_refresh_heart_row()
			_combo.on_damage_taken()
			_refresh_combo_meter()
			_damage_effect.play(_prompts.prompt_center_global(hit_direction))
			if _hearts.is_empty():
				_end_match_loss()
				return

			# Reset Simon chain (CONTEXT.md → Outcome: wrong resets chain).
			# stop() clears _running so any in-flight show-phase awaits bail out;
			# the breather gap will call start() at the end of its render gate.
			_defense.stop()
			_begin_breather_gap()

			# Hold the punch frame briefly so the hit reads, then recover to IDLE.
			# Runs in parallel with the 4s gap (same pattern as _on_damage_taken).
			await get_tree().create_timer(_DAMAGE_HIT_SECONDS, false).timeout
			_opponent_idle()
		Outcome.Type.NEUTRAL:
			# NEUTRAL gate: RiddleBox is already in REACTION state from confirm,
			# with the picked answer's reaction line typing in. Wait for that
			# typewriter to complete, then hold NEUTRAL_READ_HOLD seconds so the
			# reaction lands, then re-display the SAME prompt instantly (the
			# player already read it) and replay the Simon chain at its current
			# length from step 0. No render gate floor on the re-display — the
			# read window for the reaction was the gate.
			AudioBus.play_sfx("riddle_neutral")
			_snap_clear_simon_visuals()
			_defense.stop()

			var my_gen := _gap_generation
			# Tofu (empty reaction_text) skips the typewriter — is_rendering is
			# already false and RiddleBox hid itself in show_reaction.
			if _riddle.is_rendering():
				await _riddle.body_render_complete
				if my_gen != _gap_generation:
					return
			await get_tree().create_timer(MatchPacing.NEUTRAL_READ_HOLD, false).timeout
			if my_gen != _gap_generation:
				return

			# Re-show riddle (Tofu hide() path needs the visibility flip).
			_riddle.visible = true
			_carousel.visible = true
			_opponent.clear_reaction()
			_riddle.display_instant(_current_prompt)
			_carousel.display_prompt_instant(_current_prompt)
			_visibility = RiddleVisibility.ENCOUNTER
			# Replay simon chain at current length. Edge case: player K'd the
			# answer before defense.start() fired (during the render gate's read
			# floor) — sequence is empty, so replay's length assertion would
			# fire. Start fresh at length 1 in that case.
			if _defense.current_sequence().length() > 0:
				_defense.replay()
			else:
				_defense.start()
		Outcome.Type.RIGHT:
			AudioBus.play_sfx("riddle_correct")
			_trigger_attack_phase()

# Carousel's picked card has landed on the opponent. Show the body_hit_low
# pose (mirrored toward the card's incoming direction), hold HIT_HOLD_DURATION,
# then transition to guard_down. The Opponent.set_action(action, direction)
# signature handles flip_h via direction == RIGHT.
func _on_card_struck_opponent(direction: int) -> void:
	_opponent.set_action(Opponent.Action.HIT_LOW, direction)
	await get_tree().create_timer(AnswerCarousel.HIT_HOLD_DURATION, false).timeout
	_opponent.set_action(Opponent.Action.GUARD_DOWN)
