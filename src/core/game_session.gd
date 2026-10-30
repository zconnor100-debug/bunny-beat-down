class_name GameSession
## Small bag of state carried from the menu into a match (and between rounds).

static var quick := false
static var last_seed := 0
static var replay_seed := 0          ## set by "Rematch (same seed)": the next match uses it
static var matches_played := 0
static var wins := 0
static var replays_in_tests := false ## captures and the trailer want the final-shot replay
static var open_trail := false        ## back from a run's match: the menu opens the Trail
static var open_quest := false        ## back from a Kernel Hunt mission: the menu opens its page
