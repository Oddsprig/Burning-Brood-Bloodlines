extends Node
## Visual check harness for the menus. Acts as Game.main, builds a seeded game with a stub town, and
## steps through screens/tabs every HOLD frames (for --write-movie captures):
##   <GUI exe> --path game --write-movie C:/.../f.png --fixed-fps 10 --quit-after 34 res://ui/debug_ui.tscn
## Optional user arg: -- --only=<state index> to hold one state.

const HOLD := 3
var current: Node = null
var states: Array = []
var frame := 0
var only := -1

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = int(a.substr(7))
	Game.main = self
	Game.new_game(42)
	Game.location = "dev_town"
	DevTown.ensure(Game, "dev_town")
	_wound(Game.company[1])
	# a few stash items so outfitting has something to do
	var rng := RandomNumberGenerator.new(); rng.seed = 5
	for tid in ["mail_shirt", "mail_shirt", "nasal_helm", "dane_axe", "kite_shield"]:
		Game.stash.append(Factory.make_item(rng, tid, 3))
	var off: Unit = Roster.leaders(Game)[1]
	states = [
		func(): Game.goto("title"),
		func(): Game.goto("company", {"back": "town"}),
		func(): current.select(off.uid); current.show_tab("Gear"),
		func(): current.show_tab("Squad"),
		func(): current.show_tab("Mind"),
		func(): current.select(Roster.troops_of(Game, off.uid)[0].uid); current.show_tab("Skills"),
		func(): current.select(Game.company[1].uid); current.show_tab("Health"),
		func(): Game.goto("town"),
		func(): current.show_tab("Recruits"),
		func(): current._recruit_details(DevTown.ensure(Game, "dev_town")["recruits"][0]),
		func(): Game.goto("town", {"tab": "Healer"}),
		func(): current.show_tab("Contracts"),
		func(): Game.goto("settings", {"back": "title"}),
		func(): Game.goto("town"); current._smith("weaponsmith", DevTown.ensure(Game, "dev_town")["crafters"]["weaponsmith"]),
	]
	_apply(only if only >= 0 else 0)

func _wound(u: Unit) -> void:
	if not u.body.has_part("arm_upper_l"):
		return
	var p: Dictionary = u.body.wound_part("arm_upper_l")
	for l in p["layers"]:
		if l["tissue"] in ["skin", "muscle", "bone"]:
			l["dmg"] = 0.6; l["kind"] = "fractured" if l["tissue"] == "bone" else "cut"
	u.body.blood = u.body.blood_max * 0.8

func _apply(i: int) -> void:
	if i < states.size():
		states[i].call()

func _process(_d: float) -> void:
	frame += 1
	if only < 0 and frame % HOLD == 0:
		_apply(frame / HOLD)

func show_screen(path: String) -> void:
	if current != null:
		current.queue_free()
		current = null
	current = (load(path) as PackedScene).instantiate()
	add_child(current)
