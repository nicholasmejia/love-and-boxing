# scripts/match_pacing.gd
class_name MatchPacing

# Riddle gap durations, in seconds. See CONTEXT.md → "Riddle Gap".
const FRESH_START_SETTLE := 0.5     # Pre-prompt settle on round start / post-knockdown — opponent IDLE, riddle hidden, defense paused.
const BREATHER_GAP := 4.0           # Post-WRONG / post-Simon-damage / post-attack-end hold before next prompt renders.

# Riddle Render Gate — see CONTEXT.md.
const RIDDLE_READ_FLOOR := 1.0      # Fixed post-typewriter read window before DefensePhase activates.
const NEUTRAL_READ_HOLD := 2.0      # Hold after NEUTRAL reaction typewriter completes, before the prompt body re-displays instantly.

# Knockdown pause, in seconds. See CONTEXT.md → "Match" + "Knockdown".
const KNOCKDOWN_PAUSE := 5.0

# Banner display durations, in seconds. AnnouncementBanner.show_banner awaits these.
const PRE_READY_DELAY := 0.5  # Settle beat between scene load (or round transition) and the Ready banner sliding in.
const READY_BANNER := 1.0
const FIGHT_BANNER := 1.0
const ROUND_OVER_BANNER := 3.0

# Attack phase and knockdown timings, in seconds. See CONTEXT.md → "Attack Phase" + "Knockdown".
const KNOCK_DOWN_BANNER := 2.0
const KNOCK_OUT_BANNER := 2.0
# YOU_WIN_BANNER and YOU_LOSE_BANNER are sized to cover their stinger
# track lengths (victory.ogg ≈ 5.4s, defeat.ogg ≈ 11.6s). The player
# can K-skip before the timer expires; the constants are an upper bound,
# not a guaranteed hold.
const YOU_WIN_BANNER := 5.5
const YOU_LOSE_BANNER := 12.0
const DRAW_BANNER := 2.0  # Shown after the final round_over banner when the match ends in a draw.
