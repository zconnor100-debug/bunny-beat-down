class_name Cast
extends RefCounted
## The bots are the same 49 characters every run, so you get to know them:
## seven of each species, each with a name, a voice (RivalBook.PERSONALITIES:
## what it says), a combat STYLE (how it fights: AIBrain reads the numbers),
## a favourite carrot gun, and a line of its own. No two share a style and a
## favourite gun, so every one of them fights a little differently.
##
## They remember (RivalBook keeps the score): beat one down again and again
## and it gets more radical, from Sore to Vengeful, Unhinged and finally your
## Nemesis, fighting harder and coming for you. They hold grudges against
## the bots that beat them, and against the director (the Briar, the pacing).

## How each style fights. Every number scales an AIBrain default (1.0 = as
## the default bot does), except the ranges and healths, which replace it.
##   range: preferred fighting distance; fight_range: how far off it starts a
##   fight with another bot (m); jump / strafe / burst / melee: how much it
##   hops, sidesteps, holds the trigger, swings; break_off: health it runs at
##   when losing to a bot; gunfire: how far it hears shots and how keenly it
##   goes to look; weak: how much it picks on the wounded; crouch: stays low
##   while fighting; spot: how fast it spots; settle: how long it loots after
##   landing before it picks fights; heal_at: health it heals at; sticky: how
##   much it sticks to the target it has; memory: how long it remembers a
##   target it lost; feet: aims at the ground under you (splash).
const STYLES := {
	"rusher": {"label": "Rusher", "text": "Charges straight in, close and loud.",
		"range": 0.55, "fight_range": 42.0, "jump": 2.0, "burst": 1.3, "melee": 3.0, "break_off": 30.0, "settle": 0.5},
	"sniper": {"label": "Sharpshooter", "text": "Keeps its distance and makes every shot count.",
		"range": 1.8, "fight_range": 45.0, "jump": 0.3, "strafe": 0.5, "burst": 0.8, "melee": 0.5, "break_off": 55.0,
		"crouch": 1.0, "spot": 1.25},
	"ambusher": {"label": "Ambusher", "text": "Waits low and still, and spots you first.",
		"range": 0.8, "fight_range": 25.0, "jump": 0.5, "strafe": 0.6, "melee": 1.5, "gunfire": 0.4, "crouch": 1.0,
		"spot": 1.45},
	"brawler": {"label": "Brawler", "text": "Gets in your face and swings the club.",
		"range": 0.35, "jump": 1.5, "strafe": 1.2, "melee": 6.0, "break_off": 25.0, "settle": 0.6},
	"skirmisher": {"label": "Skirmisher", "text": "Never stands still: hops and circles while it shoots.",
		"range": 0.9, "fight_range": 32.0, "jump": 2.5, "strafe": 1.8, "burst": 0.9},
	"turtle": {"label": "Turtle", "text": "Digs in, stays low, heals early.",
		"range": 1.1, "fight_range": 22.0, "jump": 0.2, "strafe": 0.4, "break_off": 60.0, "crouch": 1.0, "settle": 1.4,
		"heal_at": 75.0},
	"vulture": {"label": "Vulture", "text": "Goes where the shooting is and finishes off the wounded.",
		"fight_range": 35.0, "gunfire": 2.0, "weak": 2.5, "break_off": 50.0},
	"duelist": {"label": "Duelist", "text": "One opponent at a time, and it doesn't let go.",
		"strafe": 1.3, "burst": 0.9, "break_off": 40.0, "sticky": 0.25, "memory": 1.6},
	"bomber": {"label": "Bomber", "text": "Loves a big bang: aims at your feet, keeps its distance.",
		"range": 1.2, "fight_range": 35.0, "feet": 1.0},
	"sprayer": {"label": "Sprayer", "text": "Holds the trigger down and lets the carrots fly.",
		"range": 0.8, "burst": 2.2, "strafe": 0.8},
	"trickster": {"label": "Trickster", "text": "Jumps, ducks and dodges. Good luck pinning it down.",
		"range": 0.7, "jump": 3.0, "strafe": 2.5, "melee": 2.0, "crouch": 0.5},
	"survivor": {"label": "Survivor", "text": "Runs from a losing fight and lives to see the end.",
		"fight_range": 25.0, "break_off": 70.0, "settle": 1.5, "heal_at": 80.0},
	"hunter": {"label": "Hunter", "text": "Tracks you down and remembers where you went.",
		"fight_range": 40.0, "gunfire": 1.5, "memory": 2.5, "spot": 1.15},
	"hoarder": {"label": "Hoarder", "text": "Loots everything first. Turns up late, very well armed.",
		"fight_range": 25.0, "settle": 2.0, "break_off": 50.0},
}

## [name, species, voice, style, favourite gun, who they are, what they say]
const MEMBERS := [
	# bandit bunnies
	["Captain Carrot", "bandit_bunny", "showoff", "rusher", "carrot_shotgun", "Leads every charge, mostly by accident.", "Charge! ...Is anyone behind me?"],
	["Vex", "bandit_bunny", "sneak", "ambusher", "carrot_smg", "Sits so still in the ferns that moss grows on her.", "Been here the whole time."],
	["Bunnicula", "bandit_bunny", "grump", "hunter", "carrot_sniper", "Only comes out at dusk. Never forgets a face.", "I smelled you from the other hill."],
	["Lop-Eared Larry", "bandit_bunny", "scaredy", "survivor", "carrot_pistol", "Has survived nine matches by never being anywhere.", "I'm not here! Nobody's here!"],
	["Snickerdoodle", "bandit_bunny", "prankster", "trickster", "carrot_lmg", "Thinks a 300-carrot belt is a joke. It is not a joke.", "Hehe! Dance for me!"],
	["Cottontail Kate", "bandit_bunny", "zen", "duelist", "carrot_rifle", "One target, one breath, one carrot.", "Breathe in. Breathe out. Bonk."],
	["Hops McGee", "bandit_bunny", "hothead", "brawler", "carrot_rocket_launcher", "Treats the rocket launcher as a club. Also uses it as one.", "Close enough to kiss, close enough to boom!"],
	# squirrels
	["Nutsy", "squirrel", "hothead", "skirmisher", "carrot_smg", "Has never once stood still. Not even asleep.", "Can't hit what won't stop!"],
	["Acorn Al", "squirrel", "grump", "hoarder", "carrot_lmg", "Keeps forty acorns in each cheek and a grudge in his heart.", "Mine. All of it. Mine."],
	["Sir Scamper", "squirrel", "noble", "duelist", "carrot_pistol", "Challenges everyone to a duel at dawn. Dawn is whenever he says.", "En garde, you scoundrel!"],
	["Hazel", "squirrel", "sneak", "sniper", "carrot_rifle", "Picks her branch, picks her shot.", "Top branch. Best view."],
	["Twitch", "squirrel", "scaredy", "trickster", "carrot_shotgun", "Jumps at every sound. Lands shooting.", "WAH! Oh, it's you. BLAM!"],
	["Kernel", "squirrel", "zen", "turtle", "carrot_rocket_launcher", "Builds a nest, sits in it, rockets anyone who knocks.", "Please wipe your feet. And duck."],
	["Bushytail Betty", "squirrel", "prankster", "vulture", "carrot_sniper", "Arrives just after the fight, just in time to finish it.", "Oh, are you two busy? Don't mind me."],
	# foxes
	["Sly", "fox", "sneak", "hunter", "carrot_smg", "Follows tracks nobody else can see.", "You leave pawprints, you know."],
	["Vixen Vera", "fox", "showoff", "sniper", "carrot_sniper", "Every shot is a trick shot, and she'll tell you about it.", "From up here you all look like snacks."],
	["Fennick", "fox", "hothead", "rusher", "carrot_smg", "Big ears, bigger temper.", "I HEARD THAT!"],
	["Foxy Roxy", "fox", "prankster", "skirmisher", "carrot_shotgun", "Circles you like a game of tag she's winning.", "Round and round we go!"],
	["Sir Reynard", "fox", "noble", "duelist", "carrot_sniper", "A gentleman: always lets you shoot first. Once.", "After you. I insist."],
	["Ember", "fox", "hothead", "bomber", "carrot_rocket_launcher", "Likes things loud and bright and on (carrot) fire.", "Boom goes the fluff!"],
	["Duchess", "fox", "grump", "turtle", "carrot_lmg", "Holds the high ground like she owns it. She thinks she does.", "You are trespassing."],
	# raccoons
	["Bandit Bill", "raccoon", "showoff", "vulture", "carrot_smg", "Steals kills, steals loot, steals the show.", "Thanks for softening them up!"],
	["Trash Panda", "raccoon", "prankster", "hoarder", "carrot_shotgun", "Rummages through every crate, bin and pocket.", "Ooh, what's in YOUR pockets?"],
	["Rocco", "raccoon", "hothead", "brawler", "carrot_shotgun", "Leads with his face. It has worked so far.", "Put 'em up! Put 'em UP!"],
	["Masky", "raccoon", "sneak", "ambusher", "carrot_rifle", "You won't see the mask until it's too late.", "Peekaboo is for amateurs."],
	["Dumpster Dot", "raccoon", "zen", "survivor", "carrot_smg", "Has lived through worse than you. Has lived IN worse than you.", "Patience. Everyone runs out of carrots."],
	["Grimsby", "raccoon", "grump", "survivor", "carrot_lmg", "Complains about everything, the director most of all.", "Rigged. All of it. RIGGED."],
	["Lady Garbage", "raccoon", "noble", "hoarder", "carrot_rocket_launcher", "Collects only the finest refuse. And rockets.", "One does not share."],
	# frogs
	["Croaker", "frog", "grump", "ambusher", "carrot_shotgun", "Waits in the reeds with a shotgun and a grudge.", "Ribbit. That's frog for gotcha."],
	["Lily Pad Lou", "frog", "zen", "turtle", "carrot_rifle", "Sits on one lily pad all match. It is a very well defended lily pad.", "The pond provides."],
	["Hopscotch", "frog", "prankster", "trickster", "carrot_pistol", "Hops in patterns only she understands.", "One, two, three, BOING!"],
	["Sir Toadsworth", "frog", "noble", "sprayer", "carrot_smg", "A gentleman of means. Means a lot of carrots in the air.", "Do pardon the spray."],
	["Puddles", "frog", "scaredy", "vulture", "carrot_rifle", "Afraid of everything except finishing off the wounded.", "Is it hurt? Can I... sorry!"],
	["Bog Boss", "frog", "hothead", "rusher", "carrot_lmg", "Runs at you with a carrot machine gun. Every time. It works.", "BOSS COMING THROUGH!"],
	["Gulp", "frog", "showoff", "brawler", "carrot_pistol", "Swallows his fear, and now and then a carrot.", "Watch this! *gulp*"],
	# beavers
	["Chompers", "beaver", "hothead", "brawler", "carrot_smg", "Gnaws through cover and anyone behind it.", "Nom nom nom. You're next."],
	["Dam Dan", "beaver", "grump", "turtle", "carrot_shotgun", "Builds a dam, holds the dam, defends the dam.", "Nobody crosses Dan's dam."],
	["Buck Toothington", "beaver", "noble", "hunter", "carrot_rifle", "Tracks you like a lord on a hunt.", "Tally-ho!"],
	["Timber", "beaver", "zen", "bomber", "carrot_lmg", "Fells his enemies like trees: loudly.", "TIMBERRR!"],
	["Lodge Lady", "beaver", "sneak", "hoarder", "carrot_smg", "Her lodge is full of other people's carrots.", "Finders keepers."],
	["Gnawman", "beaver", "scaredy", "turtle", "carrot_pistol", "Hides behind things he has gnawed. They are very thin things.", "Don't look at me!"],
	["Dr. Splash", "beaver", "showoff", "skirmisher", "carrot_rocket_launcher", "Rocket-jumps for science.", "For SCIENCE!"],
	# hamsters
	["Squeaks", "hamster", "scaredy", "survivor", "carrot_shotgun", "Hasn't won a fight yet. Hasn't lost one either: he ran.", "Squeak! Squeak! Nope!"],
	["Cheeks McGee", "hamster", "showoff", "sprayer", "carrot_lmg", "Stuffs his cheeks with ammo and empties them at you.", "Say cheese!"],
	["Nibbler", "hamster", "prankster", "ambusher", "carrot_pistol", "Small, quiet, bitey.", "Nibble nibble."],
	["Pudge", "hamster", "hothead", "rusher", "carrot_rocket_launcher", "Round, fast and armed with rockets: a bowling ball with opinions.", "STRIKE!"],
	["Whisker Biscuit", "hamster", "zen", "skirmisher", "carrot_rifle", "Bounces round a fight like it's a hamster wheel.", "Round and round, and round."],
	["Turbo", "hamster", "hothead", "trickster", "carrot_smg", "Fastest critter in the cage, and he knows it.", "Too slow! TOO SLOW!"],
	["Wheelie", "hamster", "noble", "vulture", "carrot_lmg", "Rolls in late, rolls out rich.", "Ah. Leftovers."],
]

## Radicalisation: how many times you've beaten a bot down before it turns
## Sore, Vengeful, Unhinged, and your Nemesis.
const HEAT_AT := [1, 3, 5, 8]
const HEAT_TITLES := ["", "the Sore", "the Vengeful", "the Unhinged", "the Nemesis"]
const HEAT_LABELS := ["Calm", "Sore", "Vengeful", "Unhinged", "Nemesis"]
const HEAT_COLORS := [Color(1.0, 0.42, 0.3), Color(1.0, 0.62, 0.25), Color(1.0, 0.38, 0.12), Color(1.0, 0.16, 0.12), Color(0.95, 0.1, 0.35)]
## What a radical bot says (any voice), by heat; {w} = your beat-downs of it.
const HEAT_LINES := [
	{},
	{"spot": ["Oh. You.", "Not you again, {you}.", "Back for more, {you}?"],
		"kill": ["That's for the last {w}.", "Felt good, that. {k}–{w}."],
		"lose": ["That's {w} now. I'm counting.", "Okay. OKAY, {you}."]},
	{"spot": ["{w} times, {you}. I remember every one.", "I came back for you, {you}.", "I've been looking for you, {you}."],
		"kill": ["Payback, {you}! {k}–{w}!", "Remember that one, {you}."],
		"lose": ["{w}! You'll pay for every single one!", "Again?! AGAIN?!"]},
	{"spot": ["{w} TIMES, {you}! I'M NOT EVEN MAD!", "I've been practising, {you}. On trees shaped like you.", "THERE YOU ARE!"],
		"kill": ["FINALLY! FINALLY!! {k}–{w}!", "Who's laughing now, {you}?!"],
		"lose": ["{w}... {w}... this is fine. THIS IS FINE.", "I'll be worse next time, {you}. MUCH worse."]},
	{"spot": ["There's no burrow deep enough, {you}.", "I dream about you, {you}. Not nice dreams.", "You made me, {you}."],
		"kill": ["You made me what I am, {you}.", "This is what you made, {you}. {k}–{w}."],
		"lose": ["I'll be back. I'm always back.", "{w}. See you next match, {you}."]},
]
## What a bot says about what you're wearing: lines for each piece (and each
## coat: Workshop.wearing), by event: spotting you, beating you down, being
## beaten down by you.
const OUTFIT_LINES := {
	"cheese_hat": {"spot": ["Is that... CHEESE on your head, {you}?", "I can smell your hat from here, {you}."],
		"kill": ["Say cheese, {you}!"], "lose": ["Beaten by a walking cheese board..."]},
	"snorkel_mask": {"spot": ["A snorkel? There's no water here, {you}!", "Going for a swim, {you}?"],
		"kill": ["Glub glub, {you}."], "lose": ["Sunk by a snorkeller. Unbelievable."]},
	"windup_key": {"spot": ["Who wound YOU up, {you}?", "Somebody turn your key off, {you}!"],
		"kill": ["Wound down at last."], "lose": ["Clockwork. Couldn't stop it."]},
	"laurel_wreath": {"spot": ["Laurels? You haven't beaten ME, {you}.", "Nice leaves, champ. Let's see you earn them."],
		"kill": ["Rest on THOSE laurels, {you}."], "lose": ["Fine. Keep the laurels."]},
	"jester_hat": {"spot": ["Nice hat, clown.", "Jingle all you like, {you}."],
		"kill": ["Who's the fool now, {you}?"], "lose": ["Beaten by a jester. Hilarious."]},
	"witch_hat": {"spot": ["Hocus pocus, {you}! Magic THIS away!", "Nice pointy hat, {you}."],
		"kill": ["No spell for that, was there?"], "lose": ["Witchcraft. That was witchcraft."]},
	"wizard_hat": {"spot": ["A wizard? Pull a carrot out of THAT, {you}!", "You're a wizard, {you}? Prove it."],
		"kill": ["Abracadabra. You're gone."], "lose": ["...okay, that was magic."]},
	"santa_hat": {"spot": ["Is it Christmas, {you}? Here's your present!", "Ho ho NO, {you}."],
		"kill": ["Coal for you, {you}."], "lose": ["I'm on the naughty list now, aren't I."]},
	"grad_cap": {"spot": ["Graduated, {you}? Class is in session!", "Fancy cap, smarty."],
		"kill": ["Lesson one: duck."], "lose": ["Top of the class. Ugh."]},
	"fedora": {"spot": ["M'lady... M'BEAT DOWN, {you}!", "Nice fedora, detective."],
		"kill": ["Case closed, {you}."], "lose": ["Tipped my hat to you. Literally."]},
	"flower_crown": {"spot": ["Pretty flowers, {you}. Pity about the rest.", "Aww, a flower crown!"],
		"kill": ["Flowers for your burrow, {you}."], "lose": ["Beaten by a daisy..."]},
	"flap_beanie": {"spot": ["Cold, {you}? I'll warm you up!", "Nice ear flaps, {you}."],
		"kill": ["Now your ears are cold."], "lose": ["Snug AND deadly. Rude."]},
	"heart_glasses": {"spot": ["Aww, {you}, do you love me?", "Heart glasses? Adorable. Target acquired."],
		"kill": ["Heartbreaker, me."], "lose": ["You broke my heart, {you}."]},
	"glasses_3d": {"spot": ["Ooh, 3D! Watch this carrot come right at you, {you}!", "Enjoying the show, {you}?"],
		"kill": ["How was it in 3D?"], "lose": ["That one popped off the screen..."]},
	"pixel_shades": {"spot": ["Deal with it? DEAL WITH THIS, {you}!", "Cool shades, {you}. Too cool."],
		"kill": ["Dealt with."], "lose": ["Okay. I'm dealing with it."]},
	"star_glasses": {"spot": ["Seeing stars already, {you}?", "Star glasses! Who do you think you are?"],
		"kill": ["NOW you're seeing stars."], "lose": ["A star is born. Ugh."]},
	"sapphire_necklace": {"spot": ["Ooh, shiny! I'm taking that, {you}.", "Nice rock, {you}. Mine now."],
		"kill": ["Dibs on the sapphire!"], "lose": ["Keep your jewels, then."]},
	"ring_necklace": {"spot": ["Lovely bling, {you}.", "Is that a ring? Are you proposing, {you}?"],
		"kill": ["I'll take the ring."], "lose": ["Bling AND aim. Not fair."]},
	"butterfly_wings": {"spot": ["Float like a butterfly, {you}... drop like one too!", "Pretty wings, {you}!"],
		"kill": ["Wings clipped."], "lose": ["Stung by a butterfly..."]},
	"fairy_wings": {"spot": ["Fly away, little fairy!", "A fairy? Make a wish, {you}!"],
		"kill": ["Wish denied, {you}."], "lose": ["Fairy magic. Has to be."]},
	"dark_wings": {"spot": ["Edgy wings, {you}. Very scary.", "Ooh, dark wings. I'm SO scared."],
		"kill": ["Grounded, {you}."], "lose": ["...okay, the wings ARE scary."]},
	"jetpack": {"spot": ["A JETPACK? Cheater, {you}!", "Nice jetpack, {you}. Does it go?"],
		"kill": ["Out of fuel, {you}?"], "lose": ["Flew right past me..."]},
	# your coat
	"mended_mirror": {"spot": ["Is that a MIRROR, {you}? I'll crack it again!", "Gold in the cracks? Fancy, {you}."],
		"kill": ["Seven years' bad luck, {you}."], "lose": ["Beaten by a broken mirror..."]},
	"golden_acorn": {"spot": ["Solid gold, {you}? Hold still, I'll melt you down!", "All that gold won't stop a carrot, {you}."],
		"kill": ["Gold doesn't bounce, {you}."], "lose": ["Gold. Of course you're gold."]},
	"starry_night": {"spot": ["Twinkle twinkle, {you}!", "Look, everyone! A walking night sky!"],
		"kill": ["Lights out, little star."], "lose": ["Starstruck. I'm starstruck."]},
	"tiger_stripe": {"spot": ["Here, kitty kitty, {you}!", "Stripes, {you}? You're no tiger."],
		"kill": ["Not so fierce now, {you}."], "lose": ["Rawr. Fine. You win."]},
	"smouldering": {"spot": ["Something's burning... oh, it's you, {you}.", "Hot stuff, {you}. Too hot."],
		"kill": ["Put out, {you}."], "lose": ["Burned. Properly burned."]},
}
## How often a bot talks about your outfit instead of its usual line.
const OUTFIT_TAUNT_CHANCE := 0.35

## A bot sent after you for sitting still too long.
const HUNT_LINE := "Somebody's been sitting still... coming for you, {you}!"

## A bot with a grudge against another one, on spotting it.
const FEUD_LINES := ["{them}! Remember me?", "We're not done, {them}!", "This is for last time, {them}!", "{them}. Finally.", "Oi, {them}! You owe me!"]
## A bot with a grudge against the director (the Briar, the pacing).
const DIRECTOR_LINES := ["Oi, Director! I see what you're doing!", "This lobby is RIGGED!", "The Briar? AGAIN? Who's running this?",
	"Hey, up there! Pick on someone else!", "I don't play by your rules, Director!"]
## Gangs (Gang, MatchManager): a gang mate calling out the one they're after,
## the rush while it reloads or heals, a truce to team up (against a bot, or
## you), turning on a mate, the one turned on, walking out, and the job done.
## (Spoken, a name ends a phrase, with a "." or "!": tools/voices/lines.py.)
const GANG_SPOT_LINES := ["Over here! Over here!", "Found 'em! This way!", "There! Get over here, all of you!"]
const GANG_RUSH_LINES := ["They're reloading! GO!", "Now! While they're busy!", "Rush 'em!"]
const TRUCE_LINES := ["Truce? Just till we get {them}.", "You and me, against {them}. Deal?"]
const TRUCE_YOU_LINES := ["Truce? Just till we get {you}.", "Everyone's losing to {you}. Together?"]
const BETRAY_LINES := ["Nothing personal, {them}.", "Sorry, partner. Only one of us wins.", "We were never friends, {them}."]
const BETRAYED_LINES := ["{them}! I trusted you!", "You RAT, {them}!", "Of course. OF COURSE, {them}."]
const SPLIT_LINES := ["I'm out!", "Every critter for themselves!", "Nope. Not dying for this gang."]
const DONE_LINES := ["Pleasure doing business.", "That's that. Don't follow me.", "Truce over."]
## The gang lines by the key prefix MatchManager picks them with (Cast.pick_say).
const GANG_LINES := {"gspot": GANG_SPOT_LINES, "grush": GANG_RUSH_LINES, "gr": TRUCE_LINES, "gy": TRUCE_YOU_LINES,
	"gb": BETRAY_LINES, "gt": BETRAYED_LINES, "gs": SPLIT_LINES, "gd": DONE_LINES}
## Grudge points against the director before a bot defies it: its hits on
## other bots aren't softened by the director's pacing (and it says so).
const DEFIANT_AT := 3

static var _by_name: Dictionary = {}


static func names() -> Array:
	return MEMBERS.map(func(m): return m[0])


## A member as a dictionary: name, species, voice, style, weapon, bio, says
## (empty for a name that isn't in the cast: an old save, a test critter).
static func member(n: String) -> Dictionary:
	if _by_name.is_empty():
		for m in MEMBERS:
			_by_name[m[0]] = {"name": m[0], "species": m[1], "voice": m[2], "style": m[3], "weapon": m[4], "bio": m[5], "says": m[6]}
	return _by_name.get(n, {})


static func voice_of(n: String) -> String:
	return member(n).get("voice", "")


static func style_label(n: String) -> String:
	return STYLES.get(member(n).get("style", ""), {}).get("label", "")


## How radical a bot is from your beat-downs of it: 0 calm .. 4 nemesis.
static func heat(n: String) -> int:
	var k := RivalBook.your_kills(n)
	var t := 0
	for at in HEAT_AT:
		if k >= at:
			t += 1
	return t


## "Sly the Vengeful" (the bare name while calm).
static func title(n: String) -> String:
	var t := heat(n)
	return n if t == 0 else "%s %s" % [n, HEAT_TITLES[t]]


## Who's in a match of `count` bots: your rivals and nemeses first (they
## always come back), then the bots with the hottest grudges, then anyone.
static func lineup(count: int, rng: RandomNumberGenerator) -> Array:
	var all := names()
	var order := []
	for n in all:
		var urgency := (10.0 if RivalBook.is_rival(n) else 0.0) + heat(n) * 2.0 + minf(RivalBook.grudge_total(n), 3.0) * 0.5
		order.append([urgency + rng.randf() * 0.9, n])
	order.sort_custom(func(a, b): return a[0] > b[0])
	return order.slice(0, mini(count, all.size())).map(func(o): return o[1])


## The AIBrain trait numbers for a bot: its style, pushed further by how
## radical you've made it.
static func traits_for(n: String) -> Dictionary:
	var m := member(n)
	var out: Dictionary = (STYLES.get(m.get("style", ""), {}) as Dictionary).duplicate()
	out.erase("label")
	out.erase("text")
	out["favorite"] = m.get("weapon", "")
	var t := heat(n)
	if t > 0:
		var push := 1.0 + 0.15 * t
		out["fight_range"] = float(out.get("fight_range", AIBrain.BOT_FIGHT_RANGE)) * push
		out["spot"] = float(out.get("spot", 1.0)) * (1.0 + 0.1 * t)
		# braver: even a Survivor stops running once it's out for you
		out["break_off"] = float(out.get("break_off", AIBrain.BREAK_OFF_HEALTH)) * (1.0 - 0.18 * t)
		out["player_focus"] = 1.0 - 0.16 * t    # (scales your target score: lower = you first)
		out["hunts_you"] = t >= 2
		out["no_slot"] = t >= 3                 # doesn't wait its turn to shoot at you
	out["defiant"] = RivalBook.director_grudge(n) >= DEFIANT_AT
	# how its off-screen matches left it (WarrenSim): on a streak it's braver,
	# picks fights from further off and hops about, and spots you a bit slower
	# for it; freshly scarred, it keeps its distance and runs sooner
	match RivalBook.mood(n):
		"cocky":
			out["fight_range"] = float(out.get("fight_range", AIBrain.BOT_FIGHT_RANGE)) * 1.2
			out["break_off"] = float(out.get("break_off", AIBrain.BREAK_OFF_HEALTH)) * 0.7
			out["spot"] = float(out.get("spot", 1.0)) * 0.9
			out["jump"] = float(out.get("jump", 1.0)) * 1.3
		"wary":
			out["break_off"] = float(out.get("break_off", AIBrain.BREAK_OFF_HEALTH)) * 1.3
			out["range"] = float(out.get("range", 1.0)) * 1.15
			out["settle"] = float(out.get("settle", 1.0)) * 1.3
	return out


## A line for a radical bot, or "" while it's calm.
static func heat_line(n: String, event: String, you: String, rng: RandomNumberGenerator) -> String:
	return String(heat_say(n, event, you, rng).get("text", ""))


## The same as something said (see say()), or {} while it's calm.
static func heat_say(n: String, event: String, you: String, rng: RandomNumberGenerator) -> Dictionary:
	var t := heat(n)
	if t == 0:
		return {}
	var lines: Array = HEAT_LINES[t].get(event, [])
	if lines.is_empty():
		return {}
	return pick_say(lines, "h.%d.%s" % [t, event], rng, {"you": you, "k": RivalBook.kills_on_you(n), "w": RivalBook.your_kills(n)})


## A line about something you're wearing (one of `wear`, piece ids), or ""
## when you wear nothing.
static func outfit_line(wear: Array, event: String, you: String, rng: RandomNumberGenerator) -> String:
	return String(outfit_say(wear, event, you, rng).get("text", ""))


static func outfit_say(wear: Array, event: String, you: String, rng: RandomNumberGenerator) -> Dictionary:
	if wear.is_empty():
		return {}
	var piece: String = wear[rng.randi() % wear.size()]
	var lines: Array = OUTFIT_LINES.get(piece, {}).get(event, [])
	if lines.is_empty():
		return {}
	return pick_say(lines, "o.%s.%s" % [piece, event], rng, {"you": you})


## Something a bot says: the text shown, which line it is (`key`: RogueVoice
## plays that line in the bot's own voice) and what fills its blanks.
static func say(key: String, template: String, fields := {}) -> Dictionary:
	return {"text": template.format(fields), "key": key, "fields": fields}


## One of `lines` at random, as said (its key: `prefix`.index).
static func pick_say(lines: Array, prefix: String, rng: RandomNumberGenerator, fields := {}) -> Dictionary:
	var i := rng.randi() % lines.size()
	return say("%s.%d" % [prefix, i], lines[i], fields)


static func pick(lines: Array, rng: RandomNumberGenerator, fields := {}) -> String:
	return String(lines[rng.randi() % lines.size()]).format(fields)
