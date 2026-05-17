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
