class_name Market
extends RefCounted
## Menu-side wrapper over campaign/economy.gd (Economy): prices with the company's best Appraiser applied,
## buy/sell returning "" or a reason, and the "Buy to fill uniforms" helper.

static func price(town: Dictionary, item: Item) -> int:
	return Economy.price(town, item, Economy.appraiser_of(Game))

static func sell_price(town: Dictionary, item: Item) -> int:
	return Economy.sell_price(town, item, Economy.appraiser_of(Game))

static func buy(game, town: Dictionary, item: Item) -> String:
	if not town.get("shop", []).has(item):
		return "no longer for sale"
	var p := Economy.price(town, item, Economy.appraiser_of(game))
	if game.gold < p:
		return "not enough coins (%d needed)" % p
	return "" if Economy.buy(game, town, item) else "could not buy"

static func sell(game, town: Dictionary, item: Item) -> String:
	if not game.stash.has(item):
		return "not in the stash"
	if not town.has("shop"):
		town["shop"] = []
	return "" if Economy.sell(game, town, item) > 0 else "could not sell"

## Buys the cheapest matching shop item for every piece the squad uniforms are missing, while gold lasts,
## then applies every squad's uniform. Returns {"bought": [names], "spent": int, "short": [lines]}.
static func buy_to_fill(game, town: Dictionary) -> Dictionary:
	var need := Outfit.shortfall(game.squads, game.company, game.stash)
	var bought := []
	var spent := 0
	var short := []
	var shop: Array = town.get("shop", [])
	var appr := Economy.appraiser_of(game)
	for n in need:
		for i in int(n["count"]):
			var best: Item = null
			for it in shop:
				if not it.broken and it.tid == n["tid"] and Outfit.material_ok(it, n["material"]):
					if best == null or Economy.price(town, it, appr) < Economy.price(town, best, appr):
						best = it
			if best == null or Economy.price(town, best, appr) > game.gold:
				var mat_word: String = "" if n["material"] == "any" else n["material"] + " "
				short.append("%s%s" % [mat_word, Outfit.template_name(n["tid"])])
				continue
			var p := Economy.price(town, best, appr)
			if buy(game, town, best) == "":
				bought.append(best.display_name())
				spent += p
	for l in Roster.leaders(game):
		Outfit.apply_uniform(game.squads, game.company, l.uid, game.stash)
	return {"bought": bought, "spent": spent, "short": short}

## "Buy best from local shops" for one man (Douglas, v0.006). For each slot: if his squad rule / override
## names a template, buy the best affordable one of that template; otherwise only upgrade what he already
## wears (same template, better score). Never buys a downgrade. Greedy by improvement while gold lasts.
## Returns {"buys": [{"slot", "item", "price"}], "total": int}. Pure plan; nothing is bought.
static func plan_best_for_unit(game, town: Dictionary, u: Unit) -> Dictionary:
	var shop: Array = town.get("shop", [])
	var want := Outfit.wanted(game.squads, u)
	var material: String = Outfit.rule_of(game.squads, u).get("material", "any")
	var current_main: Item = u.equip.get("main_hand", null)
	var target_main := String(want.get("main_hand", current_main.tid if current_main != null else ""))
	var cands := []
	for slot in DB.EQUIP_SLOTS:
		if slot == "off_hand" and Outfit.is_two_handed(target_main):
			continue
		var cur: Item = u.equip.get(slot, null)
		var tid := String(want.get(slot, cur.tid if cur != null else ""))
		if tid == "":
			continue
		var choices := []
		for it in shop:
			if it.broken or it.tid != tid or not Outfit.material_ok(it, material):
				continue
			if cur != null and not cur.broken and cur.tid == tid and Outfit.score(it) <= Outfit.score(cur):
				continue
			var p := price(town, it)
			if p <= game.gold:
				var gain := Outfit.score(it) - (Outfit.score(cur) if cur != null and not cur.broken and cur.tid == tid else -100.0)
				choices.append({"slot": slot, "item": it, "price": p, "gain": gain})
		choices.sort_custom(func(a, b): return a["gain"] > b["gain"] if not is_equal_approx(a["gain"], b["gain"]) else a["price"] < b["price"])
		if not choices.is_empty():
			cands.append({"gain": choices[0]["gain"], "choices": choices})
	cands.sort_custom(func(a, b): return a["gain"] > b["gain"])
	var selected := {}
	var total := 0
	var deferred_shield := {}
	for c in cands:
		var slot := String(c["choices"][0]["slot"])
		# A shield cannot replace the weapon which must first free the hand. Other
		# slots retain their original greedy priority while that dependency waits.
		if slot == "off_hand" and current_main != null and Outfit.is_two_handed(current_main.tid) and not selected.has("main_hand"):
			deferred_shield = c
			continue
		var choice := _affordable_choice(c["choices"], game.gold - total)
		if choice.is_empty():
			continue
		selected[slot] = choice
		total += int(choice["price"])
		if slot == "main_hand" and not deferred_shield.is_empty() and not Outfit.is_two_handed(choice["item"].tid):
			var shield := _affordable_choice(deferred_shield["choices"], game.gold - total)
			if not shield.is_empty():
				selected["off_hand"] = shield
				total += int(shield["price"])
	# Display the selected items in their original gain order, including a shield
	# deferred for allocation. Execution independently handles hand dependencies.
	var buys := []
	for c in cands:
		var slot := String(c["choices"][0]["slot"])
		if selected.has(slot):
			buys.append(selected[slot])
	# Do not pay for a shield which the final two-handed weapon cannot equip.
	var main: Item = u.equip.get("main_hand", null)
	for b in buys:
		if b["slot"] == "main_hand":
			main = b["item"]
	if main != null and Outfit.is_two_handed(main.tid):
		for b in buys.duplicate():
			if b["slot"] == "off_hand":
				total -= int(b["price"])
				buys.erase(b)
	return {"buys": buys, "total": total}

static func _affordable_choice(choices: Array, coins: int) -> Dictionary:
	for choice in choices:
		if int(choice["price"]) <= coins:
			return choice
	return {}

## Executes a plan from plan_best_for_unit: buys each item (gold to the town via Economy) and equips it;
## replaced gear goes to the stash. Returns the number of pieces bought.
static func buy_best_for_unit(game, town: Dictionary, u: Unit, plan: Dictionary) -> int:
	# A stale preview must never spend money or leave bought-but-unusable gear.
	if u.dead or not game.company.has(u):
		return 0
	var seen := []
	var total := 0
	var want := Outfit.wanted(game.squads, u)
	var material := String(Outfit.rule_of(game.squads, u).get("material", "any"))
	var main: Item = u.equip.get("main_hand", null)
	for b in plan.get("buys", []):
		var it: Item = b["item"]
		var slot := String(b["slot"])
		var cur: Item = u.equip.get(slot, null)
		if it.broken or seen.has(it.uid) or not town.get("shop", []).has(it) or Outfit.slot_of(it.tid) != slot or price(town, it) != int(b["price"]):
			return 0
		if it.tid != String(want.get(slot, cur.tid if cur != null else "")) or not Outfit.material_ok(it, material):
			return 0
		if cur != null and not cur.broken and cur.tid == it.tid and Outfit.score(it) <= Outfit.score(cur):
			return 0
		seen.append(it.uid)
		total += int(b["price"])
		if slot == "main_hand":
			main = it
	if total > game.gold or total != int(plan.get("total", -1)):
		return 0
	if main != null and Outfit.is_two_handed(main.tid):
		for b in plan.get("buys", []):
			if b["slot"] == "off_hand":
				return 0
	# Keep the greedy selection/preview intact, but equip the planned weapon before
	# a shield. A current two-hander must leave the hand before a shield can fit.
	var execution := []
	for b in plan["buys"]:
		if b["slot"] == "main_hand":
			execution.append(b)
	for b in plan["buys"]:
		if b["slot"] != "main_hand":
			execution.append(b)
	var n := 0
	for b in execution:
		if buy(game, town, b["item"]) == "":
			if Outfit.equip_item(u, b["item"], game.stash) == "":
				n += 1
	return n
