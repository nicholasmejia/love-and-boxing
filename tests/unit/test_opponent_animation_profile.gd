extends GutTest

# GUT's custom-warnings load path doesn't pick up class_name registrations made
# in the same branch as this test file. Preload explicitly so parse succeeds.
const OpponentAnimationProfile = preload("res://scripts/data/opponent_animation_profile.gd")

func test_default_values():
    var p := OpponentAnimationProfile.new()
    assert_almost_eq(p.idle_bob_amplitude_x, 22.0, 0.001)
    assert_almost_eq(p.idle_bob_amplitude_y, 10.0, 0.001)
    assert_almost_eq(p.idle_bob_period, 1.1, 0.001)
    assert_almost_eq(p.attack_lunge_shift_x, 40.0, 0.001)
    assert_almost_eq(p.attack_lunge_scale_peak, 1.10, 0.001)
    assert_eq(p.attack_lunge_transition_out, Tween.TRANS_BACK)
    assert_eq(p.attack_lunge_transition_return, Tween.TRANS_QUAD)
    assert_almost_eq(p.hit_recoil_shift_x, 40.0, 0.001)
    assert_almost_eq(p.hit_recoil_scale_dip, 0.92, 0.001)
    assert_almost_eq(p.knockdown_fall_rotation_degrees, -40.0, 0.001)
    assert_almost_eq(p.knockdown_fall_drop_y, 200.0, 0.001)
    assert_almost_eq(p.guard_bounce_amplitude_y, 18.0, 0.001)
    assert_almost_eq(p.guard_bounce_period, 0.45, 0.001)

func test_tofu_resource_loads_with_expected_values():
    var p: OpponentAnimationProfile = load("res://data/opponent_animation/tofu.tres")
    assert_not_null(p, "tofu animation profile should load")
    assert_almost_eq(p.idle_bob_amplitude_x, 22.0, 0.001)
    assert_almost_eq(p.idle_bob_period, 1.1, 0.001)
    assert_almost_eq(p.attack_lunge_shift_x, 40.0, 0.001)
    assert_eq(p.attack_lunge_transition_out, Tween.TRANS_BACK)
    assert_almost_eq(p.knockdown_fall_rotation_degrees, -40.0, 0.001)
    assert_almost_eq(p.guard_bounce_period, 0.45, 0.001)
