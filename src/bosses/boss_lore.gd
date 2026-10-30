class_name BossLore
extends RefCounted
## The giants' story, as the Warren tells it: how the Starfall Acorn came
## down over Wildwood and split three ways, and what each piece made of the
## one that took it in. Each boss's story is told in four chapters, opened
## by facing it (StatBook.boss): the first is the legend everyone knows, the
## second you hear once you've faced it, the third once you've beaten it, and
## the last once you've beaten it three times. Shown on the Trophy Room's
## Bosses page (TrophyPanel), the boss's line on its arrival (BossIntro) and
## the loading screen's rumours. The whole story, and where it's going (the
## Kernel Hunt), is in docs/LORE.md.

const IDS := ["brute", "robot", "hamster"]

const MYTH_TITLE := "The Night the Acorn Fell"
const MYTH := "Ask anyone in the Warren how the giants came and they'll tell it the same way, usually with a torch under their chin. One midsummer night a star fell over Wildwood. It wasn't a star. It was an acorn, gold and humming, as big as the Big Red Barn, and it hit Boulder Bluff so hard the lake jumped. It split three ways. The biggest piece rolled down into the Carrot Patch. The second skipped across the lake and in through an open window of the House on the shore, into a toy box. The last, no bigger than a seed, fell plink into a hamster's water bottle. Whatever ate a piece, or was wound by one, or drank one, grew. And grew. And went wrong. The Warren calls the pieces the Starfall Kernels. Nobody has ever held one: the giants carry them inside."

## What opens each chapter after the first: [what's counted (StatBook.BOSS_KEYS), how many].
const OPENS := [[], ["fought", 1], ["beaten", 1], ["beaten", 3]]

## Each boss: its name and billing, where it lives, the line on its arrival,
## its four chapters ([title, text]) and the rumours the loading screen tells.
const BOSSES := {
	"brute": {
		"name": "Brutus", "title": "the Meadow's Nightmare", "map": "island", "where": "Wildwood Island",
		"epigraph": "DAYS SINCE BRUTUS: 0",
		"chapters": [
			["Little Bru", "Before he was Brutus he was Bru, the runt of the Carrot Patch warren: the smallest, the shyest, the one who always shared. He never won a scrap and never started one. He liked carrots, and quiet, and lying in the long grass counting stars. He was counting them the night one fell."],
			["Nine Days", "By morning every carrot in the Patch had grown as long as a log and glowed like a lantern, and Bru was hungry. He ate them all, and the piece of the Acorn they'd grown round. He grew for nine days. On the ninth night the Warren heard him crying out in the Patch. On the tenth, the crying stopped. The Big Red Barn has kept a tally on its door ever since: DAYS SINCE BRUTUS. It has never got past nine."],
			["The Dent", "The Acorn hit him on its way down, and the dent's still there: a hollow in his skull the size of a hay bale that never healed. Hit him there and he flinches like a kit. Hit his jaw and for a moment he forgets how to be angry. Only for a moment. Don't stand in the ring when his fists come down, and when he picks up a boulder, start running before he throws it."],
			["What He Hears", "He sleeps under Boulder Bluff, which is why there are fewer boulders on it every year. He wakes when the ground drums, and nothing drums like a field of critters fighting. The rangers say he comes to feed. Old Mother Clover, who taught Bru to count, says he comes because he's lonely. \"He can hear the other two,\" she says. \"Humming. Across the lake.\""],
		],
		"rumours": ["The Big Red Barn keeps a tally: DAYS SINCE BRUTUS. It has never got past nine.",
			"Brutus flinches when you hit the dent in his head. His jaw's softer still."],
	},
	"robot": {
		"name": "Tin Tyrant", "title": "the Wind-Up Warlord", "map": "toybox", "where": "Toy Box Bash",
		"epigraph": "\"WIND HIM UP AND WATCH HIM GO!\" (on the box he came in)",
		"chapters": [
			["Model No. 7", "TIN ROBOT, MODEL No. 7. WIND HIM UP AND WATCH HIM GO! Three steps, a beep, and sparks from his chest while the flint still worked. He kept watch on the windowsill of the toy room through three children and one very curious dog, and was wound so often his key wore shiny. Then one summer night the window was open."],
			["The Key Turns Itself", "The second piece of the Acorn came through the window like a cannonball and lodged in the Robot's winding drum. Nobody wound him that night. He wound himself. By morning he stood taller than the bookcase, and the painted red dots of his eyes had begun to burn. He climbed Block Castle, crowned himself with a bottle cap and read out the Clockwork Decree: every toy shall be wound, and every toy that will not be wound shall be UNWOUND."],
			["Thirty-Some Turns", "The Acorn can push a spring a long way, but not forever. Every half a minute or so the Tyrant has to stop and wind down, and while it does, the key in its back slows and steam pours out of its seams. That's when it's soft, and that's the only time. Shoot the key. Stay out of the red line its eyes paint on the floor, and when it raises its arms, the missiles are coming."],
			["Under the Lid", "The children think it's broken. They put it back in the toy box and shut the lid. They should have locked it. Some nights the Warren's lookouts on the windowsill see red light sweeping under the lid, back and forth, back and forth. The Jack-in-the-Box, who used to be its friend and won't come out any more, says it isn't looking for the children. \"It's looking for the rest of itself.\""],
		],
		"rumours": ["The Tin Tyrant has to stop and wind down every half a minute or so. Shoot the key in its back.",
			"Every toy shall be wound. Every toy that will not be wound shall be UNWOUND. (The Clockwork Decree)"],
	},
	"hamster": {
		"name": "Nibbles", "title": "the Rabid", "map": "cage", "where": "the Hamster Cage",
		"epigraph": "He ran twelve kilometres a night. Now he runs at you.",
		"chapters": [
			["Good Boy", "Nibbles was a golden hamster with a squeaky wheel and very full cheeks. He ran twelve kilometres a night on the Big Wheel and slept all day in the Hamster Hut, and the children loved him, and he loved sunflower seeds, and that was the whole of his life."],
			["Water Bottle Falls", "The smallest piece of the Acorn came in on the same wind as the second, no bigger than a sunflower seed, and fell plink into Nibbles's water bottle. He drank it the next morning. By lunchtime he'd chewed through the Big Wheel. By teatime he was foaming. He's grown a little with every drink since, and the bottle has never once run dry."],
			["He Can't Stop", "He charges whatever moves, and once he's going he can't stop: not for critters, not for walls. So stand in front of something hard and let him come. He'll hit it so hard he forgets his own name, and his head will be right there. Stay out of the foam: it burns, it sticks, and it slows you down while he turns round for another go."],
			["Tunnels", "He doesn't sleep in the Hamster Hut any more. Under the bedding he's dug tunnels deeper than any cage should go, and they all run the same way: toward the toy room. Toward the hum. The grown-ups say he's just grumpy. The children say he's lonely. The children are closer."],
		],
		"rumours": ["Nibbles can't stop once he's charging. Stand in front of a wall and let him come.",
			"Don't stand in Nibbles's foam: it burns, it sticks, and it slows you down."],
	},
}


## How the Warren Gazette reports one beaten (WarrenSim.boss_news): the
## headline the first time and the times after, where everyone went to fight
## it, how things stand after, and the caption under the photo of it falling.
const NEWS := {
	"brute": {"fell": "BRUTUS FALLS AT THE CARROT PATCH", "again": "BRUTUS DOWN AGAIN", "where": "out to the meadow",
		"after": "The tally on the Big Red Barn's door went back to zero, which for once nobody minded.",
		"caption": "Brutus, down at last."},
	"robot": {"fell": "TIN TYRANT UNWOUND AT BLOCK CASTLE", "again": "TIN TYRANT UNWOUND AGAIN", "where": "into the toy room",
		"after": "His key has stopped turning. The toys say they'll believe it when it stays stopped.",
		"caption": "The Tin Tyrant, unwound."},
	"hamster": {"fell": "NIBBLES STOPPED AT LAST", "again": "NIBBLES STOPPED AGAIN", "where": "into the Hamster Cage",
		"after": "The water bottle is still full. Nobody is drinking from it.",
		"caption": "Nibbles, stopped at last."},
}


static func of(id: String) -> Dictionary:
	return BOSSES.get(id, {})


## The boss that lives on a map ("" if none does).
static func id_for_map(map_id: String) -> String:
	for id in IDS:
		if BOSSES[id].map == map_id:
			return id
	return ""


## The line under its name as it lands (BossIntro).
static func epigraph(id: String) -> String:
	return String(of(id).get("epigraph", ""))


## Whether you've opened chapter `i` (0..3) of its story.
static func is_open(id: String, i: int) -> bool:
	if i <= 0:
		return true
	var need: Array = OPENS[mini(i, OPENS.size() - 1)]
	return float(StatBook.boss(id)[need[0]]) >= float(need[1])


## How many of its chapters you've opened.
static func chapters_open(id: String) -> int:
	var n := 0
	for i in OPENS.size():
		if is_open(id, i):
			n = i + 1
	return n


## What opens chapter `i`, for a closed one ("Beat Brutus to read on.").
static func opens_when(id: String, i: int) -> String:
	var who := String(of(id).get("name", "it"))
	if who == "Tin Tyrant":
		who = "the Tin Tyrant"
	var need: Array = OPENS[mini(i, OPENS.size() - 1)]
	if need.is_empty():
		return ""
	if need[0] == "fought":
		return "Face %s in a Boss Battle to read on." % who
	return "Beat %s to read on." % who if int(need[1]) == 1 else "Beat %s %d times to read on." % [who, int(need[1])]


## The rumours about the boss of a map, for the loading screen.
static func rumours(map_id: String) -> Array:
	var id := id_for_map(map_id)
	return of(id).get("rumours", []) if id != "" else []
