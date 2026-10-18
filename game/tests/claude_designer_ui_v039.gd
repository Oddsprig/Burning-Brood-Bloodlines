extends RefCounted
## Roadmap v0.039: house select "Design your ruler" applies name, look and focus.
var checks: int = 0
var fails: int = 0
var tree: SceneTree

class RouteProbe extends Node:
	var path: String = ""
	func show_screen(value: String) -> void: path = value

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL designer ui: ", message)

func settle() -> void:
	for _i in 4: await tree.process_frame

func _pick(button: OptionButton, value: Variant) -> void:
	var values: Array = button.get_meta("design_values")
	for i in values.size():
		if values[i] == value or str(values[i]) == str(value):
			button.select(i)
			button.item_selected.emit(i)
			return
	check(false, "missing design choice %s" % str(value))

func run(scene_tree: SceneTree) -> int:
	tree = scene_tree
	await tree.process_frame
	var logic = load("res://tests/claude_designer_v039.gd").new()
	var fx: Dictionary = logic.fixture()
	var leader: Array = fx["leader"]
	var leader_uid := str(leader[Persons.PERSON_UID])
	var household := str(fx["ordinary"]["household_uid"])
	Game.world["w"] = 4
	Game.world["h"] = 4
	Game.world["cell"] = 32
	Game.world["terrain"] = "g".repeat(16)
	Game.world["region"] = "0".repeat(16)
	Game.world["road"] = "0".repeat(16)
	var probe := RouteProbe.new()
	tree.root.add_child(probe)
	var previous_main = Game.main
	Game.main = probe
	Game._active_screen = "house_select"
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(viewport)
	var page: HouseSelectView = (load("res://ui/house_select.tscn") as PackedScene).instantiate()
	viewport.add_child(page)
	await settle()
	page.select_settlement("seat")
	page.next_stage()
	await settle()
	page.select_house(household)
	page.next_stage()
	await settle()
	check(page.stage == 2 and page.name_input != null, "customize stage still precedes ruler design")
	page.name_input.text = "Copper Oath"
	page.name_input.text_changed.emit(page.name_input.text)
	page.next_stage()
	await settle()
	check(page.stage == 3 and page.stage_label.text.contains("Design your ruler"), "design stage opens after Customize House")
	var first := page.find_child("DesignFirstName", true, false) as LineEdit
	var focus := page.find_child("DesignFocus", true, false) as OptionButton
	var skin := page.find_child("DesignPick_skin", true, false) as OptionButton
	var hair := page.find_child("DesignPick_hair", true, false) as OptionButton
	var seed := page.find_child("DesignPick_seed", true, false) as OptionButton
	var beard := page.find_child("DesignPick_beard", true, false) as OptionButton
	var beard_style := page.find_child("DesignPick_beard_style", true, false) as OptionButton
	var note := page.find_child("DesignFocusEffect", true, false) as Label
	var portrait := page.find_child("DesignPortrait", true, false) as Portrait
	check(first != null and focus != null and skin != null and hair != null and seed != null and beard != null and beard_style != null and portrait != null, "design stage exposes name, look, focus and portrait")
	first.text = "A"
	first.text_changed.emit(first.text)
	check(page.next_button.disabled and "2 and 20" in page.status.text, "invalid first name shows preview reason and disables Next")
	var opts: Dictionary = CharacterDesign.options(Game, leader_uid)
	var choices: Dictionary = opts["choices"]
	var skin_val: String = str(((choices["skin"] as Array)[1] as Dictionary)["value"])
	var hair_val: String = str(((choices["hair"] as Array)[2] as Dictionary)["value"])
	first.text = "Aldric"
	first.text_changed.emit(first.text)
	_pick(skin, skin_val)
	_pick(hair, hair_val)
	_pick(seed, 4)
	_pick(beard, true)
	_pick(beard_style, 5)
	_pick(focus, "martial")
	check(not page.next_button.disabled and note != null and "tactician" in note.text, "valid design enables Next and shows the focus effect")
	var spec: Dictionary = portrait._spec
	check(spec.get("skin") == Color(skin_val) and spec.get("hair") == Color(hair_val) and int(spec.get("seed", -1)) == 4 and bool(spec.get("beard", false)) and int(spec.get("beard_style", -1)) == 5, "live portrait uses CharacterDesign preview look")
	page.next_stage()
	await settle()
	check(page.stage == 4 and page.next_button.text == "Begin", "review follows the design stage")
	var lines: PackedStringArray = []
	for node in page.editor.get_children():
		if node is Label: lines.append((node as Label).text)
	var joined := "\n".join(lines)
	check("Aldric Native Cadet" in joined and "Martial" in joined and "tactician" in joined, "review lists the designed name and focus")
	var begun: Dictionary = page.begin_review()
	Game.wait_save()
	await settle()
	var saved: Dictionary = Game.world.get("player_house", {}).get("design", {})
	check(bool(begun.get("ok", false)) and str(leader[7]) == "Aldric Native Cadet", "Begin applies the designed ruler name (%s)" % str(begun.get("reason", "")))
	check(str(Game.world.get("player_house", {}).get("ruler_name", "")) == "Aldric Native Cadet" and str(saved.get("first_name", "")) == "Aldric" and str(saved.get("focus", "")) == "martial", "player house keeps the designed name and focus")
	var look: Dictionary = saved.get("look", {}) if saved.get("look") is Dictionary else {}
	check(str(look.get("skin", "")) == skin_val and str(look.get("hair", "")) == hair_val and int(look.get("seed", -1)) == 4 and bool(look.get("beard", false)) and int(look.get("beard_style", -1)) == 5, "player house stores the chosen look")
	page.queue_free()
	viewport.queue_free()
	probe.queue_free()
	Game.main = previous_main
	print("designer ui v039: %d checks, %d failures" % [checks, fails])
	tree = null
	return fails
