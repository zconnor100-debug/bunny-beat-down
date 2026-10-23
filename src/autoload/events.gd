extends Node
## Global signal bus. Gameplay systems emit here; UI, audio and AI listen,
## so none of them need direct references to each other.

signal critter_spawned(critter: Node)
signal critter_damaged(victim: Node, info: DamageInfo)
signal critter_died(victim: Node, info: DamageInfo)
signal shot_fired(shooter: Node, origin: Vector3, weapon_id: StringName)
signal explosion(position: Vector3, radius: float)
signal item_picked_up(critter: Node, item_name: String)

signal match_phase_changed(phase: int)
signal storm_changed(stage: int, center: Vector2, radius: float, next_center: Vector2, next_radius: float, time_left: float, shrinking: bool)
signal alive_count_changed(alive: int, total: int)
signal supply_drop_incoming(position: Vector3)
signal player_hit_confirmed(victim: Node, damage: float, headshot: bool, killed: bool)
signal taunt(critter: Node, text: String)          ## a bot says something (see RivalBook)
signal rival_news(text: String, sub: String)        ## a rival turned up, or you got revenge
signal announce(text: String, sub: String)          ## a big centre-screen message (the Briar's rules...)
signal clover_eaten(critter: Node)
