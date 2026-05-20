class_name OpponentAnimationProfile
extends Resource

# Idle bob (continuous)
@export var idle_bob_amplitude_x: float = 22.0
@export var idle_bob_amplitude_y: float = 10.0
@export var idle_bob_period: float = 1.1

# Attack lunge (transient, two-phase)
@export var attack_lunge_shift_x: float = 40.0
@export var attack_lunge_scale_peak: float = 1.10
@export var attack_lunge_out_duration: float = 0.12
@export var attack_lunge_return_duration: float = 0.15
@export var attack_lunge_transition_out: int = Tween.TRANS_BACK
@export var attack_lunge_transition_return: int = Tween.TRANS_QUAD

# Hit recoil (transient, two-phase, scale inverted vs lunge)
@export var hit_recoil_shift_x: float = 40.0
@export var hit_recoil_scale_dip: float = 0.92
@export var hit_recoil_out_duration: float = 0.10
@export var hit_recoil_return_duration: float = 0.15
@export var hit_recoil_transition_out: int = Tween.TRANS_BACK
@export var hit_recoil_transition_return: int = Tween.TRANS_QUAD

# Knockdown fall (transient, multi-phase)
@export var knockdown_fall_sway_amplitude: float = 30.0
@export var knockdown_fall_sway_cycles: float = 1.5
@export var knockdown_fall_sway_duration: float = 0.8
@export var knockdown_fall_end_scale: float = 0.7
@export var knockdown_fall_rotation_degrees: float = -40.0
@export var knockdown_fall_drop_y: float = 200.0
@export var knockdown_fall_drop_duration: float = 0.3
@export var knockdown_fall_drop_transition: int = Tween.TRANS_QUAD

# Knockdown recover (transient, non-KO only)
@export var knockdown_recover_duration: float = 0.3
@export var knockdown_recover_transition: int = Tween.TRANS_BACK

# Guard-dropped bounce (continuous, GUARD_DOWN_EXCITED only)
@export var guard_bounce_amplitude_y: float = 18.0
@export var guard_bounce_period: float = 0.45
