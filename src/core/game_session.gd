class_name GameSession
## Small bag of state carried from the menu into a match (and between rounds).

static var quick := false
static var last_seed := 0
static var replay_seed := 0          ## set by "Rematch (same seed)": the next match uses it
static var matches_played := 0
static var wins := 0
