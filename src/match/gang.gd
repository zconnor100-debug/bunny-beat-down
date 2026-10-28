class_name Gang
extends RefCounted
## A gang: a few bots out for the same enemy together (MatchManager makes
## them). Gang mates leave each other alone (Critter.gang: their carrots
## don't hurt each other), call out what they see, and hunt as a pack
## (AIBrain: one pins the enemy down from range, the others flank it, and
## they all rush it while it reloads or heals). The drop's gang is out for
## you; a gang that forms mid-match is out for you (when you're leading the
## match) or for a bot both hold grudges against. None of them lasts: when
## the win is in sight, a disloyal member turns on a mate, and the one it
## betrayed never forgets (RivalBook.note_betrayal).

## How keen each kind of bot (its voice: RivalBook.PERSONALITIES) is to team up...
const JOIN := {"grump": 0.8, "hothead": 0.6, "scaredy": 0.55, "showoff": 0.5, "noble": 0.5, "prankster": 0.4, "zen": 0.2, "sneak": 0.15}
## ...and how ready to turn on its gang once the win is in sight (a noble never does).
const DISLOYAL := {"noble": 0.0, "zen": 0.05, "scaredy": 0.2, "grump": 0.3, "hothead": 0.4, "showoff": 0.45, "prankster": 0.6, "sneak": 0.8}

var name := ""
var members: Array[Critter] = []
var enemy: Critter            ## the bot they're out for (null: you)
var called := -100.0          ## (the match clock at its last callout)


func _init(gang_name: String, enemy_bot: Critter = null) -> void:
	name = gang_name
	enemy = enemy_bot


## The members still standing, and still in it.
func alive() -> Array[Critter]:
	var out: Array[Critter] = []
	for c in members:
		if is_instance_valid(c) and c.alive and c.gang == name:
			out.append(c)
	return out


func add(c: Critter) -> void:
	members.append(c)
	c.gang = name
	if c.visual and c.visual.name_tag:
		c.visual.name_tag.text += "\n" + name


func leave(c: Critter) -> void:
	members.erase(c)
	if is_instance_valid(c) and c.gang == name:
		c.gang = ""
		if c.visual and c.visual.name_tag:
			c.visual.name_tag.text = c.visual.name_tag.text.replace("\n" + name, "")
