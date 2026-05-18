# scripts/match_pacing.gd
class_name MatchPacing

# Riddle gap durations, in seconds. See CONTEXT.md → "Riddle Gap".
const FRESH_START_GAP := 3.0
const FRESH_START_DEAD_AIR := 1.0   # Front portion of FRESH_START_GAP with Simon defense paused
const BREATHER_GAP := 4.0

# Knockdown pause, in seconds. See CONTEXT.md → "Match" + "Knockdown".
const KNOCKDOWN_PAUSE := 5.0

# Banner display durations, in seconds. AnnouncementBanner.show_message awaits these.
const READY_BANNER := 1.0
const FIGHT_BANNER := 1.0
const ROUND_OVER_BANNER := 3.0
