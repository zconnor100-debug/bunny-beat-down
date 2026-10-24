class_name RivalBook
extends RefCounted
## The bots remember you. Every bot is a character (Cast: a name, a voice, a
## way of fighting), and this book (saved between runs) keeps the score
## between each of them and you: how often it has beaten you down, how often
## you've beaten it (which radicalises it: Cast.heat), how often you've met.
## A bot that has beaten you twice (and more often than you've beaten it)
## becomes your RIVAL: it's always in your next matches, it hunts you, and it
## taunts you, in its own voice. Beat it and the game tells you about your
## revenge. Bots also keep grudges against the bots that beat them down, and
## against the director (the Briar, the pacing), and count their wins.
##
## Automated test runs use their own file, like Settings.

const PATH := "user://rivals.cfg"
const TEST_PATH := "user://rivals_test.cfg"
const RIVAL_AT := 2                   ## beat-downs on you before a bot becomes your rival

## What each kind of bot is like: how it plays, and what it says.
const PERSONALITIES := {
	"hothead": {"label": "Hothead", "skill": 0.04, "aggression": 1.4,
		"spot": ["THERE you are, {you}!", "Get over here, {you}!", "Oh, it's ON, {you}."],
		"kill": ["Ha! That's {k} for me!", "Stay down, {you}! {k}–{w}!", "Too slow, {you}. Again."],
		"lose": ["This isn't over, {you}!", "Lucky shot! LUCKY!", "Rematch. RIGHT NOW."]},
	"sneak": {"label": "Sneak", "skill": 0.06, "aggression": 0.8,
		"spot": ["...I see you, {you}.", "Shhh. Found you.", "Don't turn around, {you}."],
		"kill": ["Didn't see me, did you? {k}–{w}.", "From the shadows. Again.", "You never look behind you, {you}."],
		"lose": ["...noted.", "You got lucky, {you}. I'll be quieter.", "Next time you won't see me."]},
	"showoff": {"label": "Show-off", "skill": 0.0, "aggression": 1.15,
		"spot": ["Watch THIS, {you}!", "Front row seats, {you}!", "Ready for the highlight reel?"],
		"kill": ["And the crowd goes wild! {k}–{w}!", "Did you get that on camera?", "Style points: mine."],
		"lose": ["That was a warm-up.", "The crowd loved it anyway.", "Okay, okay — nice one, {you}."]},
	"grump": {"label": "Grudge-holder", "skill": 0.05, "aggression": 1.25,
		"spot": ["I remember you, {you}.", "We have unfinished business.", "You owe me, {you}."],
		"kill": ["That's for last time. {k}–{w}.", "I never forget, {you}.", "Square? Not even close."],
		"lose": ["I'll remember this, {you}.", "Add it to the list.", "You'll pay for that."]},
	"scaredy": {"label": "Scaredy-cat", "skill": -0.04, "aggression": 0.7,
		"spot": ["Eep! It's {you}!", "Oh no oh no oh no—", "P-please go away, {you}!"],
		"kill": ["I... I did it? {k}–{w}!", "Sorry! Sorry! That's {k}!", "Did I win? I won!"],
		"lose": ["I knew it...", "Not the face!", "Mommy..."]},
	"prankster": {"label": "Prankster", "skill": 0.02, "aggression": 1.0,
		"spot": ["Peekaboo, {you}!", "Knock knock, {you}!", "Tag, you're it!"],
		"kill": ["Gotcha! {k}–{w}!", "Hehe. Classic {you}.", "Boop! That's {k}."],
		"lose": ["Ow! Good one!", "Okay, you got me back.", "Rematch? For the laughs?"]},
	"noble": {"label": "Noble", "skill": 0.05, "aggression": 1.0,
		"spot": ["Ah, {you}. We meet again.", "Have at thee, {you}!", "I say, {you}, how common of you."],
		"kill": ["Jolly good show. {k}–{w}.", "Do send my regards to the Burrow, {you}.", "Most unsporting of you to lose."],
		"lose": ["How frightfully rude.", "I demand satisfaction, {you}!", "Bad form, {you}. Bad form."]},
	"zen": {"label": "Calm one", "skill": 0.04, "aggression": 0.9,
		"spot": ["Hello, {you}. Let's begin.", "The carrot finds its mark, {you}.", "Be still, {you}."],
		"kill": ["It was always going to end this way. {k}–{w}.", "Breathe, {you}. Try again.", "Balance. {k}–{w}."],
		"lose": ["A good lesson.", "Even the river loses to the rock, sometimes.", "Well struck, {you}."]},
}

static var _cfg: ConfigFile


static func path() -> String:
	return TEST_PATH if Settings.is_test_run() else PATH


static func _book() -> ConfigFile:
	if _cfg == null:
		_cfg = ConfigFile.new()
		_cfg.load(path())
	return _cfg


static func save() -> void:
	_book().save(path())


## Forget everyone (tests only; the player's book is never wiped by the game).
static func reset_for_tests() -> void:
	assert(Settings.is_test_run())
	_cfg = ConfigFile.new()
	save()


## The bot's voice: its Cast voice (a name from an old save gets one from
## its name, the same every run).
static func personality_of(bot: String) -> String:
	var voice := Cast.voice_of(bot)
	if voice != "":
		return voice
	var ids := PERSONALITIES.keys()
	return ids[absi(hash(bot)) % ids.size()]


static func label_of(bot: String) -> String:
	return PERSONALITIES[personality_of(bot)]["label"]


static func kills_on_you(bot: String) -> int:
	return int(_book().get_value(bot, "kills_on_you", 0))


static func your_kills(bot: String) -> int:
	return int(_book().get_value(bot, "your_kills", 0))


static func meetings(bot: String) -> int:
	return int(_book().get_value(bot, "meetings", 0))


static func is_rival(bot: String) -> bool:
	return kills_on_you(bot) >= RIVAL_AT and kills_on_you(bot) > your_kills(bot)


## Your rivals, the worst first: [[name, species id], ...].
static func rivals() -> Array:
	var out := []
	for bot in _book().get_sections():
		if is_rival(bot):
			out.append([bot, String(_book().get_value(bot, "species", ""))])
	out.sort_custom(func(a, b): return kills_on_you(a[0]) - your_kills(a[0]) > kills_on_you(b[0]) - your_kills(b[0]))
	return out


static func note_meeting(bot: String, species: String) -> void:
	_book().set_value(bot, "species", species)
	_book().set_value(bot, "meetings", meetings(bot) + 1)


## The bot beat you down. Returns true if that just made it your rival.
static func note_you_died_to(bot: String, species: String) -> bool:
	var was := is_rival(bot)
	_book().set_value(bot, "species", species)
	_book().set_value(bot, "kills_on_you", kills_on_you(bot) + 1)
	save()
	return is_rival(bot) and not was


## You beat the bot down. Returns true if it was your rival (revenge!).
static func note_you_beat(bot: String, species: String) -> bool:
	var was := is_rival(bot)
	_book().set_value(bot, "species", species)
	_book().set_value(bot, "your_kills", your_kills(bot) + 1)
	save()
	return was


## Grudges this bot holds against other bots: {name: beat-downs not yet paid back}.
static func grudges(bot: String) -> Dictionary:
	return (_book().get_value(bot, "grudges", {}) as Dictionary).duplicate()


static func grudge_total(bot: String) -> int:
	var n := 0
	for v in grudges(bot).values():
		n += int(v)
	return n


## A bot beat down another one: the loser holds it against the winner, and
## if the winner held a grudge against the loser, that's one paid back.
## Returns true if it was paying one back. (Saved with the match: save().)
static func note_bot_beat(winner: String, loser: String) -> bool:
	var theirs := grudges(loser)
	theirs[winner] = int(theirs.get(winner, 0)) + 1
	_book().set_value(loser, "grudges", theirs)
	_book().set_value(winner, "bot_kills", bot_kills(winner) + 1)
	var mine := grudges(winner)
	if int(mine.get(loser, 0)) <= 0:
		return false
	mine[loser] = int(mine[loser]) - 1
	if int(mine[loser]) <= 0:
		mine.erase(loser)
	_book().set_value(winner, "grudges", mine)
	return true


static func bot_kills(bot: String) -> int:
	return int(_book().get_value(bot, "bot_kills", 0))


## How sore the bot is at the director (the Briar caught it, the pacing
## softened its hits): see Cast.DEFIANT_AT.
static func director_grudge(bot: String) -> int:
	return int(_book().get_value(bot, "director", 0))


static func note_director(bot: String, points: int) -> void:
	_book().set_value(bot, "director", director_grudge(bot) + points)


static func wins(bot: String) -> int:
	return int(_book().get_value(bot, "wins", 0))


static func note_win(bot: String) -> void:
	_book().set_value(bot, "wins", wins(bot) + 1)


## A line in the bot's own voice for an event: "spot", "kill" or "lose".
static func line(bot: String, event: String, you: String, rng: RandomNumberGenerator = null) -> String:
	var lines: Array = PERSONALITIES[personality_of(bot)][event]
	var pick: String = lines[(rng.randi() if rng else randi()) % lines.size()]
	return pick.format({"you": you, "k": kills_on_you(bot), "w": your_kills(bot)})


## "3–1 against you" style score from your side.
static func score(bot: String) -> String:
	return "%d–%d" % [your_kills(bot), kills_on_you(bot)]
