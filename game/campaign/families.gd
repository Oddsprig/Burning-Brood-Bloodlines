class_name Families
extends RefCounted
## Family records and the weekly family turn (economy spec 1, sections 3 and 6).
##
## family = {id, name (surname), m, f, kids, old (counts; named people are generated from `seed` when opened),
##   land {crop: acres}, herd {animal: head}, homes, cond (home repair 0..1), purse (gold), goods {good: int},
##   debt (owed to the town's head), loan_day, jobs {biz id: workers}, owns [biz ids], farm (own farmhands row or -1),
##   hands (members on the family land), worked (share of the land worked), cum {crop|"herd": claim mark},
##   last (day of the last turn), unpaid / hungry (turns in a row), idle (adults without work), tax_season,
##   wear {good: fraction}, named, hist [lines], gone, seed, estate (families[0]: the town's own land)}
##
## The turn runs once a week per family, 1/7 of the families each day (CampaignWorld work queue, one job per
## town per day). Everything is cheap integer and float arithmetic on the record; no per-person objects.

const SEXES := ["m", "f"]

## Immutable anchors, separate from local array id and person house affiliation.
## All households receive identity; only actual office-holding lineages are rulers.
static func identity(e: Dictionary, f: Dictionary) -> void:
	var scope := String(e.get("identity_scope", ""))
	if scope == "" or f.get("estate", false): return
	if String(f.get("household_uid", "")) == "":
		f["household_uid"] = "household:%s:%d" % [scope, int(f["id"])]
	if String(f.get("founding_house_uid", "")) == "":
		f["founding_house_uid"] = "house:%s:%d" % [scope, int(f["id"])]

# ================================================================== generation
static func make_estate(town: Dictionary) -> Dictionary:
	var f := _blank(0)
	f["name"] = town.get("name", "the town")
	f["estate"] = true
	f["named"] = true
	return f

static func _blank(id: int) -> Dictionary:
	return {"id": id, "name": "", "m": 0, "f": 0, "kids": 0, "old": 0, "land": {}, "herd": {}, "homes": 0, "cond": 1.0,
		"purse": 0.0, "store": {"food": 0.0, "drink": 0.0, "wood": 0.0}, "debt": 0.0, "loan_day": -1.0, "jobs": {}, "owns": [], "farm": -1, "hands": 0,
		"worked": 0.0, "cum": {}, "last": 0.0, "unpaid": 0, "hungry": 0, "idle": 0, "tax_season": -1, "wear": {},
		"named": false, "hist": [], "gone": false, "seed": 0, "serve": {}}

static func make_family(id: int, race: String, cul: Dictionary, rng: RandomNumberGenerator, used: Dictionary) -> Dictionary:
	var f := _blank(id)
	var names: Dictionary = DB.names.get(String(cul.get("names", race)), DB.names.get(race, DB.names.get("human", {})))   # (v0.012: the culture's surnames)
	var lasts: Array = names.get("last", ["Smith"])
	var nm: String = lasts[rng.randi() % lasts.size()]
	for _t in 4:
		if not used.has(nm):
			break
		nm = lasts[rng.randi() % lasts.size()]
	used[nm] = true
	f["name"] = nm
	var hh := float(cul.get("household", 5))
	f["m"] = 1 if rng.randf() < 0.92 else 0
	f["f"] = 1 if rng.randf() < 0.92 else 0
	if int(f["m"]) + int(f["f"]) == 0:
		f["m"] = 1
	var extra := hh - 2.0
	f["m"] = int(f["m"]) + (1 if rng.randf() < extra * 0.07 else 0)
	f["f"] = int(f["f"]) + (1 if rng.randf() < extra * 0.07 else 0)
	f["old"] = 1 if rng.randf() < 0.3 else 0
	var kids := int(round(maxf(0.0, rng.randfn(hh - 2.4, 1.3))))
	f["kids"] = kids
	var room := int(cul["home"]["room"])
	f["homes"] = maxi(1, int(ceil(float(people(f)) / float(room) - 0.25)))
	f["cond"] = snappedf(rng.randf_range(0.55, 1.0), 0.01)
	f["purse"] = snappedf(rng.randf_range(8.0, 60.0), 0.01)
	f["seed"] = rng.randi()
	return f

static func people(f: Dictionary) -> int:
	return int(f["m"]) + int(f["f"]) + int(f["kids"]) + int(f["old"])

static func adults(f: Dictionary) -> int:
	return int(f["m"]) + int(f["f"])

## Members away in service (People.draw: militia, caravan crews, later armies).
static func serving(f: Dictionary) -> int:
	var n := 0
	var sv: Dictionary = f.get("serve", {})
	for k in sv:
		n += int(sv[k])
	return n

static func acres(f: Dictionary) -> int:
	var a := 0
	for c in f["land"]:
		a += int(f["land"][c])
	return a

static func heads(f: Dictionary) -> int:
	var h := 0
	for k in f["herd"]:
		h += int(f["herd"][k])
	return h

## Hands the family's crops need: 8 acres a hand with an ox, 4 without (barge part 3 section 1 [ours]); a
## family record without an ox count (older saves, tests) works as if it had its oxen.
static func _cultivation_hands(f: Dictionary, a: float) -> float:
	var L: Dictionary = TownEcon.data()["land"]
	var ox := int(f.get("ox", -1))
	var aph := float(L["acres_per_hand"])
	var crop := a / aph
	if ox >= 0:
		var with_ox := minf(a, float(ox) * aph)
		crop = with_ox / aph + (a - with_ox) / float(L["acres_no_ox"])
	return crop

const EMPTY_CROP_WORK := {"cultivation": 0.0, "fallow": 0.0, "base": 0.0, "harvest": 0.0}

## Physical fallow still needs upkeep, at the explicit [ours] one-quarter
## cultivation allowance, but has no harvest. Draft coverage is shared across
## the holding's active acres; crop productivity and the harvest multiplier stay.
static func crop_work(f: Dictionary, e: Dictionary = {}, day: float = -1.0) -> Dictionary:
	var rows := CropRotation.work_acres(e, f)
	if rows.is_empty():
		return EMPTY_CROP_WORK
	var active := 0.0; var fallow := 0.0
	for good in rows:
		active += float(rows[good]["active"])
		fallow += float(rows[good]["fallow"])
	var cultivation := _cultivation_hands(f, active)
	var upkeep := fallow / float(TownEcon.data()["land"]["acres_per_hand"]) * float(TownEcon.data()["land"].get("fallow_upkeep_share", 0.25))
	var si := Calendar.season_index(day if day >= 0.0 else float(e.get("day", 0)))
	var harvest_acres := 0.0
	var seasons: Dictionary = TownEcon.data()["land"].get("harvest_seasons", {})
	for good in rows:
		for cut in seasons.get(good, [[TownEcon.data()["land"]["harvest_season"], 1.0]]):
			if int(cut[0]) == si:
				harvest_acres += float(rows[good]["active"])
				break
	return {"cultivation": cultivation, "fallow": upkeep, "base": cultivation + upkeep,
		"harvest": cultivation * harvest_acres / active if active > 0.0 else 0.0}

static func crop_hands(f: Dictionary, e: Dictionary = {}) -> float:
	return float(crop_work(f, e)["base"])

static func herd_hands(f: Dictionary, e: Dictionary = {}) -> float:
	if e.has("hd"):
		return Herds.labour_hands(e, int(f["id"]))
	# Totals-only old records have no saved age classes: count their real stored
	# heads conservatively, without making young animals or new herd records.
	var out := 0.0
	for k in f["herd"]:
		out += float(f["herd"][k]) / float(Herds.kind(String(k)).get("per_hand", TownEcon.data()["land"]["head_per_hand"]))
	out += float(maxi(0, int(f.get("ox", 0)))) / float(Herds.kind("oxen")["per_hand"])
	return out

static func need_hands(f: Dictionary, e: Dictionary = {}) -> float:
	return crop_hands(f, e) + herd_hands(f, e)

## Harvest needs extra field hands; caring for livestock keeps its ordinary need.
## Output continues to use base need, so seasonal staff do not multiply the yield.
static func seasonal_need_hands(f: Dictionary, day: float, e: Dictionary = {}) -> float:
	var work := crop_work(f, e, day)
	return float(work["base"]) + herd_hands(f, e) + float(work["harvest"]) * (float(Barge.B()["labour"]["harvest_hands"]) - 1.0)

## Compare actual capacity as well as the season marker. This repairs an older
## save's already-harvest capacity on its ordinary turn without forced matching.
static func farm_capacity_stale(e: Dictionary, f: Dictionary) -> bool:
	var work := crop_work(f, e)
	var herd_need := herd_hands(f, e)
	var need := float(work["base"]) + herd_need
	return _farm_capacity_stale_with(e, f, work, need, -1.0)

static func _farm_capacity_stale_with(e: Dictionary, f: Dictionary, work: Dictionary, need: float, helpers_in: float = -1.0) -> bool:
	var day := float(e.get("day", 0))
	if not is_equal_approx(float(f.get("assigned_need", -1.0)), need) or int(f.get("assigned_crop_year", -1)) != Calendar.year(day):
		return true
	var helpers := helpers_in if helpers_in >= 0.0 else (minf(need, Barge.helper_hands(e, f, day)) if need > 0.0 else 0.0)
	var hneed := need + float(work["harvest"]) * (float(Barge.B()["labour"]["harvest_hands"]) - 1.0)
	var gap := hneed - float(f.get("hands", 0)) - helpers
	var farm := int(f.get("farm", -1))
	if farm < 0:
		return gap > 0.7
	return int(e["biz"][farm]["cap"]) != maxi(0, int(ceil(gap - 0.3)))

## Splits the town's acreage and herds across landholding families (a few big holders, many small).
## herd_shares (v0.012): {kind: share} of the culture's start mix; each herding family keeps one kind picked by these
## shares (two when it has 10+ head, 40%), so the town's head follow the mix. Empty: every kind alike (as before).
static func distribute_land(e: Dictionary, fams: Array, crop_acres: Dictionary, head_total: float, herd_kinds: Array, rng: RandomNumberGenerator,
		herd_shares: Dictionary = {}) -> void:
	var holders := []
	for f in fams:
		if not f.get("estate", false) and not Population.is_cohort(f) and rng.randf() < 0.66:
			holders.append(f)
	if holders.is_empty():
		holders.append(fams[mini(1, fams.size() - 1)])
	var weights := {}
	for f in holders:
		weights[f["id"]] = pow(maxf(0.02, rng.randf()), -0.65)
	var share := {"grain": 1.0, "fruit": 0.55, "flax": 0.3}
	for crop in crop_acres:
		var sub := holders.filter(func(h): return crop == "grain" or rng.randf() < float(share[crop]))
		if sub.is_empty():
			sub = [holders[0]]
		var tw := 0.0
		for h in sub:
			tw += float(weights[h["id"]])
		for h in sub:
			var a := int(round(float(crop_acres[crop]) * float(weights[h["id"]]) / tw))
			if a > 0:
				h["land"][crop] = a
	var hsub := []
	for f in fams:
		if not f.get("estate", false) and not Population.is_cohort(f) and rng.randf() < 0.42:
			hsub.append(f)
	if hsub.is_empty() and head_total > 0.0:
		hsub.append(holders[0])
	var tw2 := 0.0
	var hw := {}
	for f in hsub:
		hw[f["id"]] = pow(maxf(0.03, rng.randf()), -0.5)
		tw2 += float(hw[f["id"]])
	for f in hsub:
		var n := int(round(head_total * float(hw[f["id"]]) / tw2))
		if n <= 0:
			continue
		if herd_shares.is_empty():
			var kinds: Array = [herd_kinds[rng.randi() % herd_kinds.size()]]
			if herd_kinds.size() > 1 and n >= 10 and rng.randf() < 0.4:
				kinds = herd_kinds.duplicate()
			for k in kinds:
				f["herd"][k] = int(f["herd"].get(k, 0)) + int(ceil(float(n) / kinds.size()))
			continue
		var k1 := _pick_share(herd_kinds, herd_shares, rng, "")
		var k2 := ""
		if herd_kinds.size() > 1 and n >= 10 and rng.randf() < 0.4:
			k2 = _pick_share(herd_kinds, herd_shares, rng, k1)
		if k2 == "":
			f["herd"][k1] = int(f["herd"].get(k1, 0)) + n
		else:   # split by the two kinds' shares
			var s1 := float(herd_shares[k1]); var s2 := float(herd_shares[k2])
			var n1 := clampi(int(round(float(n) * s1 / (s1 + s2))), 1, n - 1)
			f["herd"][k1] = int(f["herd"].get(k1, 0)) + n1
			f["herd"][k2] = int(f["herd"].get(k2, 0)) + n - n1
	# landholders start with last harvest's savings
	for f in fams:
		if f.get("estate", false):
			continue
		f["purse"] = snappedf(float(f["purse"]) + float(acres(f)) * rng.randf_range(4.0, 9.0) + float(heads(f)) * rng.randf_range(1.0, 3.0), 0.01)
	_aggregate_land(e)

## A kind picked by its share (not `skip`; "" when nothing else is left).
static func _pick_share(kinds: Array, shares: Dictionary, rng: RandomNumberGenerator, skip: String) -> String:
	var tot := 0.0
	for k in kinds:
		if String(k) != skip:
			tot += float(shares.get(k, 0.0))
	if tot <= 0.0:
		return ""
	var r := rng.randf() * tot
	var last := ""
	for k in kinds:
		if String(k) == skip:
			continue
		last = String(k)
		r -= float(shares.get(k, 0.0))
		if r <= 0.0:
			return last
	return last

## Rebuilds the town's land, herd and worked totals from the families (generation and load).
static func _aggregate_land(e: Dictionary) -> void:
	var land := {}; var herd := {}; var wac := {}; var whd := {}
	var hands := 0
	for f in e["fams"]:
		if f.get("gone", false):
			continue
		var wk := float(f["worked"])
		for c in f["land"]:
			land[c] = int(land.get(c, 0)) + int(f["land"][c])
			wac[c] = float(wac.get(c, 0.0)) + float(f["land"][c]) * wk
		for a in f["herd"]:
			herd[a] = int(herd.get(a, 0)) + int(f["herd"][a])
			whd[a] = float(whd.get(a, 0.0)) + float(f["herd"][a]) * wk
		hands += int(f["hands"])
	e["land"] = land; e["herd"] = herd; e["wacres"] = wac; e["wherd"] = whd; e["hands"] = hands
	if not e.has("cum"):
		e["cum"] = {}
	for c in land:
		if not e["cum"].has(c):
			e["cum"][c] = 0.0
	if not e["cum"].has("herd"):
		e["cum"]["herd"] = 0.0
	for f in e["fams"]:
		for c in f["land"]:
			if not f["cum"].has(c):
				f["cum"][c] = float(e["cum"].get(c, 0.0))
		if not f["cum"].has("herd"):
			f["cum"]["herd"] = float(e["cum"]["herd"])

static func richest(e: Dictionary) -> int:
	var best := 1; var bv := -1.0
	for f in e["fams"]:
		if f.get("estate", false) or f.get("gone", false) or Population.is_cohort(f):
			continue
		var v := float(f["purse"]) + (float(acres(f)) * 60.0 + float(heads(f)) * 25.0) * TownEcon.COIN
		if v > bv:
			bv = v; best = int(f["id"])
	return best

static func person_name(f: Dictionary, rng: RandomNumberGenerator, race: String) -> String:
	var names: Dictionary = DB.names.get(race, DB.names.get("human", {}))
	var firsts: Array = names.get("first", ["Ann"])
	return "%s %s" % [firsts[rng.randi() % firsts.size()], f["name"]]

static func add_hist(f: Dictionary, line: String, day: float) -> void:
	# A prose write paired with the structured event is redundant. Keep only unpaired prose for the UI.
	if f.get("ev", []).is_empty() or int(f["ev"][-1][0]) != int(day):
		var extra: Array = f.get("extra_history", [])
		extra.append("%s: %s" % [Calendar.text(day).split(" - ")[0], line])
		while extra.size() > EV_MAX: extra.pop_front()
		f["extra_history"] = extra
	var h: Array = f["hist"]
	h.append("%s: %s" % [Calendar.text(day).split(" - ")[0], line] if day > 0.0 else line)
	while h.size() > 12:
		h.pop_front()

## Structured history event (Douglas: backstories from what really happened): [day, code, args...], kept
## compact for later record packing; campaign/backstory.gd turns them into text (recruit cards, family record).
## Codes: loan [gold, head title], land [what, head title], home_head [head title], home_ruin [home type],
## shelter, housed, unpaid [business], hunger [season index], left [why], died [name, role, sex], maimed [name, role],
## elder, born, joined [name, role, force], company [name], deserted [name, force], ruined, officer [name, rank].
const EV_MAX := 14

static func event(f: Dictionary, code: String, args: Array, day: float) -> void:
	if not f.has("ev"):
		f["ev"] = []
	var a: Array = f["ev"]
	a.append([int(day), code] + args)
	while a.size() > EV_MAX:
		a.pop_front()

# ================================================================== land claims (barn sales)
## Settle saved cumulative legacy claims and the actual proceeds of this owner's
## stored harvest. New goods retain ownership after acres or work change.
static func settle(e: Dictionary, f: Dictionary) -> float:
	var cum: Dictionary = e["cum"]
	var fc: Dictionary = f["cum"]
	var pay := 0.0
	for c in f["land"]:
		var now := float(cum.get(c, 0.0))
		pay += float(f["land"][c]) * (now - float(fc.get(c, now)))
		fc[c] = now
	var hn := heads(f)
	var nowh := float(cum.get("herd", 0.0))
	if hn > 0:
		pay += float(hn) * (nowh - float(fc.get("herd", nowh)))
	fc["herd"] = nowh
	if e.has("harvest_book"):
		# Old cumulative books remain valid, but cannot spend money already
		# backing somebody else's new sale or unknown older proceeds.
		var legacy_due := pay + float(f.get("legacy_land_pending", 0.0))
		pay = minf(legacy_due, maxf(0.0, float(e["farm_till"]) - HarvestClaims.reserved_cash(e))) if legacy_due > 0.0 else legacy_due
		f["legacy_land_pending"] = maxf(0.0, legacy_due - pay)
		pay += HarvestClaims.collect(e, f, maxf(0.0, pay))
	if pay != 0.0:
		e["farm_till"] = float(e["farm_till"]) - pay
		if f.get("estate", false):
			e["treasury"] = float(e["treasury"]) + pay
		else:
			receive_harvest(e, f, pay)
	return pay

## Apply the existing gross harvest tribute once, then payroll before profit.
## The caller has already debited the real payer or farm_till.
static func receive_harvest(e: Dictionary, f: Dictionary, pay: float) -> float:
	var ru: Dictionary = e.get("ruler", {})
	var trib: float = 0.0
	if pay > 0.0 and String(ru.get("kind", "")) == "coin":
		trib = pay * float(ru.get("tribute", 0.0))
		e["treasury"] = float(e["treasury"]) + trib
		if e.has("stats"):
			e["stats"]["tribute_coin"] = float(e["stats"].get("tribute_coin", 0.0)) + trib
	var net: float = pay - trib
	var surplus: float = net - Businesses.receive_farm(e, f, net)
	f["purse"] = float(f["purse"]) + surplus
	return surplus

## The existing proportional draft transfer, shared by a purchase preview and
## the physical move. Legacy households without an ox count keep their fallback.
static func land_oxen(a: Dictionary, n: int) -> int:
	var total := acres(a)
	var ox := int(a.get("ox", -1))
	return mini(ox, int(round(float(ox) * float(n) / float(total)))) if ox > 0 and total > 0 else 0

## Moves `n` acres of `crop` from family a to family b (either may be the estate). Both settle first.
static func move_land(e: Dictionary, a: Dictionary, b: Dictionary, crop: String, n: int) -> void:
	n = mini(n, int(a["land"].get(crop, 0)))
	if n <= 0:
		return
	settle(e, a); settle(e, b)
	# the oxen go with the fields they plough (one per 8 acres) [ours]
	var a_ac := acres(a)
	var oxa := int(a.get("ox", -1))
	if oxa > 0 and a_ac > 0:
		var mo := land_oxen(a, n)
		a["ox"] = oxa - mo
		b["ox"] = maxi(0, int(b.get("ox", 0))) + mo
		Herds.moved(e, a, b, "oxen", mo)   # herds: the oxen's records follow the fields
	e["wacres"][crop] = float(e["wacres"].get(crop, 0.0)) - float(n) * float(a["worked"]) + float(n) * float(b["worked"])
	a["land"][crop] = int(a["land"][crop]) - n
	if int(a["land"][crop]) <= 0:
		a["land"].erase(crop)
	b["land"][crop] = int(b["land"].get(crop, 0)) + n
	b["cum"][crop] = float(e["cum"].get(crop, 0.0))
	Plots.land_moved(e, a, b, crop, n)   # land map: whole plots change hands, with a history line (campaign/plots.gd)
	refresh_worked(e, a)
	refresh_worked(e, b)

static func move_herd(e: Dictionary, a: Dictionary, b: Dictionary, animal: String, n: int) -> void:
	n = mini(n, int(a["herd"].get(animal, 0)))
	if n <= 0:
		return
	settle(e, a); settle(e, b)
	e["wherd"][animal] = float(e["wherd"].get(animal, 0.0)) - float(n) * float(a["worked"]) + float(n) * float(b["worked"])
	a["herd"][animal] = int(a["herd"][animal]) - n
	if int(a["herd"][animal]) <= 0:
		a["herd"].erase(animal)
	b["herd"][animal] = int(b["herd"].get(animal, 0)) + n
	Herds.moved(e, a, b, animal, n)   # herds: the records follow (a sale on both sides)
	refresh_worked(e, a)
	refresh_worked(e, b)

static func set_worked(e: Dictionary, f: Dictionary, wk: float) -> void:
	var d := wk - float(f["worked"])
	if absf(d) < 0.0001:
		return
	for c in f["land"]:
		e["wacres"][c] = float(e["wacres"].get(c, 0.0)) + float(f["land"][c]) * d
	for a in f["herd"]:
		e["wherd"][a] = float(e["wherd"].get(a, 0.0)) + float(f["herd"][a]) * d
	f["worked"] = wk

## Keep field output in step with the hands actually assigned. This changes future
## output only; harvest claims and wage settlement keep their existing cadence.
static func refresh_worked(e: Dictionary, f: Dictionary) -> void:
	if f.get("gone", false):
		return
	var need := need_hands(f, e)
	var helpers := 0.0 if (f.get("estate", false) or need <= 0.0) else minf(need, Barge.helper_hands(e, f, float(e.get("day", 0))))
	_refresh_worked_with(e, f, need, helpers)

static func _refresh_worked_with(e: Dictionary, f: Dictionary, need: float, helpers: float) -> void:
	if f.get("gone", false):
		return
	f["work_need"] = need
	f["work_crop_year"] = Calendar.year(float(e.get("day", 0)))
	if need <= 0.0:
		set_worked(e, f, 0.0)
		return
	var estate: bool = f.get("estate", false)
	var own := 0 if estate else int(f["hands"])
	var hired: float = 0.0
	var bid := int(f.get("farm", -1))
	if bid >= 0 and bid < (e["biz"] as Array).size():
		var b: Dictionary = e["biz"][bid]
		if not b.get("closed", false):
			hired = field_hands(e, b)
			if not estate:
				hired = minf(hired, float(maxi(0, int(ceil(need - float(own) - helpers - 0.3)))))
	var own_output: float = 1.0 if estate else Barge.output_mult(int(f.get("hungry", 0)))
	set_worked(e, f, clampf(((float(own) + helpers) * own_output + hired) / need, 0.0, 1.0))

## The employer's hunger cannot disable another household's workers. Bedridden
## named employees remain assigned and retain their dated wage accounting.
static func field_hands(e: Dictionary, b: Dictionary) -> float:
	var hands: float = float(b["workers"])
	if hands <= 0.0: return 0.0
	var day: float = float(e.get("day", 0))
	var key: String = str(int(b["id"]))
	for worker in e.get("fams", []):
		var n: int = int(worker.get("jobs", {}).get(key, 0))
		if n <= 0: continue
		var bed: int = 0
		for c in worker.get("sk", {}).values():
			if int(c[Sickness.C_BIZ]) == int(b["id"]) and int(c[Sickness.C_BED]) == 1 and day >= float(c[Sickness.C_ON]) and day < Sickness._stop(c): bed += 1
		hands -= float(n) - float(maxi(0, n - bed)) * Barge.output_mult(int(worker.get("hungry", 0)))
	return clampf(hands, 0.0, float(b["workers"]))

static func refresh_employers(e: Dictionary, f: Dictionary) -> void:
	for key in f.get("jobs", {}):
		var b: Dictionary = e["biz"][int(key)]
		if b.get("closed", false): continue
		if String(b["type"]) == "farm": refresh_worked(e, e["fams"][int(b["owner"])])
		elif String(b["type"]) == "estate": refresh_worked(e, e["fams"][0])

# ================================================================== jobs
static func set_job(e: Dictionary, f: Dictionary, bid: int, n: int) -> void:
	var k := str(bid)
	var cur := int(f["jobs"].get(k, 0))
	if cur == n:
		return
	var b: Dictionary = e["biz"][bid]
	if n < cur:
		b["staff_left_day"] = int(e.get("day", 0))
		WageClaims.pay_business(e, f, b)
	b["workers"] = maxi(0, int(b["workers"]) + n - cur)
	e["open_n"] = maxi(0, int(e.get("open_n", 0)) - (n - cur))
	if n <= 0:
		f["jobs"].erase(k)
	else:
		f["jobs"][k] = n
	# A hired hand's turn is independent of the landowner's. Waiting for the
	# owner's next reassignment left newly staffed or vacated fields stale.
	var owner := int(b.get("owner", -1))
	if String(b["type"]) == "farm" and owner >= 0 and owner < (e["fams"] as Array).size():
		var landholder: Dictionary = e["fams"][owner]
		if int(landholder.get("farm", -1)) == bid:
			refresh_worked(e, landholder)
	elif String(b["type"]) == "estate" and bid == int(e.get("estate_biz", -1)):
		refresh_worked(e, e["fams"][0])

static func job_total(f: Dictionary) -> int:
	var t := 0
	for k in f["jobs"]:
		t += int(f["jobs"][k])
	return t

## Recorded adult places must cover the real civilians exactly once. Child cleanup
## is fractional helper work and is deliberately separate from these adult places.
static func assignments_stale(f: Dictionary) -> bool:
	var assigned := int(f.get("hands", 0)) + job_total(f) + int(f.get("idle", 0)) + (f.get("keeps", []) as Array).size()
	for job in f.get("cj", {}):
		assigned += int(f["cj"][job])
	return assigned != maxi(0, adults(f) - serving(f))

## Puts the family's adults to work: own land and herds first, own businesses next, then the best-paying
## open places in town; the rest are idle. Leaves employers that have not paid for weeks.
static func reassign(e: Dictionary, f: Dictionary) -> void:
	_reassign_with(e, f, {}, -1.0, -1.0)

static func _reassign_with(e: Dictionary, f: Dictionary, work_in: Dictionary, herd_need_in: float, helpers_in: float) -> void:
	if f.get("estate", false) or f.get("gone", false):
		return
	# Places can reopen or gain funding between the weekly market lists. Read the
	# real vacancies on this family's ordinary turn, without advancing its pay day.
	Businesses.refresh_hiring(e)
	var biz: Array = e["biz"]
	var ad := maxi(0, adults(f) - serving(f))   # members in service (militia, caravans, armies) work there
	ad -= _keep(e, f, ad)   # v0.014: a grown-up keeps and works each of the family's shops, before its land
	# This reassignment changes jobs and cash, not these physical fields/herds.
	# Reuse the current crop-work calculation for its seasonal capacity below.
	var work: Dictionary = work_in if not work_in.is_empty() else crop_work(f, e)
	var herd_need: float = herd_need_in if herd_need_in >= 0.0 else herd_hands(f, e)
	var need := float(work["base"]) + herd_need
	# barge: children 10-14 (0.2 of a hand) and elders (0.15) help on the family's own land first
	var helpers := helpers_in if helpers_in >= 0.0 else (minf(need, Barge.helper_hands(e, f, float(e.get("day", 0)))) if need > 0.0 else 0.0)
	var own := mini(ad, int(ceil(need - helpers - 0.3))) if need > 0.0 else 0
	own = maxi(own, 0)
	if own > 0:
		own -= _to_trades(e, f, own, ad, need, biz)
	e["hands"] = int(e.get("hands", 0)) + own - int(f["hands"])
	f["hands"] = own
	var spare := ad - own
	# homeless families take the town's casual work first (before anyone else's regular hiring)
	if f.has("hl"):
		spare -= Shelter.claim_casual(e, f, spare)
	elif f.has("cj"):
		Shelter.release_casual(e, f)
	var leave_unpaid := int(TownEcon.data()["family"]["unpaid_leave_weeks"])
	# drop places that are gone, over capacity, or have stopped paying
	for k in f["jobs"].keys():
		var b: Dictionary = biz[int(k)]
		var n := int(f["jobs"][k])
		if b.get("closed", false):
			set_job(e, f, int(k), 0)
		elif int(b["workers"]) > int(b["cap"]):
			set_job(e, f, int(k), maxi(0, n - (int(b["workers"]) - int(b["cap"]))))
		elif int(f["unpaid"]) >= leave_unpaid and float(b["till"]) < float(b["wage"]) * 3.0:
			set_job(e, f, int(k), 0)
	var total := job_total(f)
	while total > spare:
		var worst := ""; var ww := INF
		for k in f["jobs"]:
			var wv := float(biz[int(k)]["wage"])
			if wv < ww:
				ww = wv; worst = k
		var cur_w := int(f["jobs"][worst])
		var drop := mini(cur_w, total - spare)
		set_job(e, f, int(worst), cur_w - drop)
		total -= drop
	# _keep already assigns the profit-taking keeper. Additional paid relatives
	# compete for real funded places under the same rules as other staff.
	total = _best_places(e, f, spare)
	e["idle_n"] = maxi(0, int(e.get("idle_n", 0)) + (spare - total) - int(f.get("idle", 0)))
	f["idle"] = spare - total
	# hired field hands make up for missing family hands (barge: hired first, at 1.15 x the day wage; the harvest needs
	# 2x hands for its days: more places then, the same yield)
	var hv := float(work["harvest"]) > 0.0
	var hneed := float(work["base"]) + herd_need + float(work["harvest"]) * (float(Barge.B()["labour"]["harvest_hands"]) - 1.0)
	if int(f["farm"]) < 0 and hneed - float(own) - helpers > 0.7 and e.has("biz") and not f.get("estate", false):
		var nb: Dictionary = Businesses._row(e, "farm", int(f["id"]), 0, TownEcon.data())   # a farm that needs hands opens a place
		nb["till"] = 0.0
		nb["wage"] = EconomyRules.wage_limit(e, nb, Barge.day_wage(e) * float(Barge.B()["labour"]["field"]))
		f["farm"] = int(nb["id"])
		Businesses.rebuild_open(e)
	if int(f["farm"]) >= 0:
		var fb: Dictionary = biz[int(f["farm"])]
		var old_cap := int(fb["cap"])
		fb["cap"] = maxi(0, int(ceil(hneed - float(own) - helpers - 0.3)))
		if int(fb["cap"]) > old_cap:
			var funded: float = Businesses.fund_farm(f, fb, e)
			if funded > 0.0:
				f["farm_funding_pending"] = float(f.get("farm_funding_pending", 0.0)) + funded
	f["farm_harvest"] = hv
	f["assigned_need"] = need
	f["assigned_crop_year"] = Calendar.year(float(e.get("day", 0)))
	_refresh_worked_with(e, f, need, helpers)

## v0.014 (town spec 08: "every business is held by a real family member and family"; barge part 3 section 4: "a
## family shop counts its keeper"): one grown-up of the family keeps and works each of its open shops (not its farm),
## ahead of its land; the land then hires hands for him (the fields hire first). He is not a hired hand: no wage, no
## place counted; he draws the keeper's take (Businesses.owner_turn). Who he is: the family's places go eldest first
## (Persons.work), the keepers' first. Returns how many grown-ups keep shops. (Before: an owner's family worked its
## shop only with grown-ups its land did not need, so most shops stood empty, made nothing and were drained to 0 by
## their upkeep, and then nobody would sign on at an empty till: Fenmere's 0-coin, 0/1 shops beside 46 idle.)
static func _keep(e: Dictionary, f: Dictionary, ad: int) -> int:
	var biz: Array = e["biz"]
	if adults(f) <= 0:
		_heirless(e, f)
	var keeps := []
	var herder_changed := false
	for bid in f["owns"]:
		var b: Dictionary = biz[int(bid)]
		if b.get("closed", false) or String(b["type"]) == "farm" or int(b["owner"]) != int(f["id"]):
			continue
		if keeps.size() < ad:
			keeps.append(int(bid))
	for bid in f.get("keeps", []):
		if int(bid) < biz.size() and not keeps.has(int(bid)):
			if String(biz[int(bid)]["type"]) == "herder" and int(biz[int(bid)].get("kw", 0)) != 0: herder_changed = true
			biz[int(bid)]["kw"] = 0
	for bid in keeps:
		if String(biz[int(bid)]["type"]) == "herder" and int(biz[int(bid)].get("kw", 0)) != 1: herder_changed = true
		biz[int(bid)]["kw"] = 1
	f["keeps"] = keeps
	if herder_changed:
		Herds._herder_caps(e)
		Businesses.refresh_hiring(e)
	return keeps.size()

## Barge part 3 section 6: a shop "closes when the keeper dies with no heir". A family left with no grown-up (only
## children and elders) gives up its shops: they go up for sale to a family with the savings (TownEcon's weekly
## _sell_businesses, as when a family dies out or moves) [ours: for sale rather than closed, as the sim already did
## for those]. Its farm stays (the land is still the family's).
static func _heirless(e: Dictionary, f: Dictionary) -> void:
	var keep := []
	for bid in f["owns"]:
		var b: Dictionary = e["biz"][int(bid)]
		if String(b["type"]) == "farm" or b.get("closed", false):
			keep.append(bid)
			continue
		b["owner"] = -1
		b["for_sale"] = true
		b["kw"] = 0
	f["owns"] = keep

## The family's shops that want a keeper it could give (its turn re-runs reassign then).
static func keeps_stale(e: Dictionary, f: Dictionary) -> bool:
	if adults(f) <= 0:
		for bid in f["owns"]:
			if String(e["biz"][int(bid)]["type"]) != "farm":
				return true   # no grown-up left to keep its shops (_heirless)
	var keeps: Array = f.get("keeps", [])
	for bid in keeps:
		var kb: Dictionary = e["biz"][int(bid)]
		if kb.get("closed", false) or int(kb["owner"]) != int(f["id"]) or int(kb.get("kw", 0)) <= 0:
			return true   # closed, sold or a claimed keeper no longer at work
	if keeps.size() >= adults(f) - serving(f):
		return keeps.size() > adults(f) - serving(f)   # fewer grown-ups at home than keepers
	for bid in f["owns"]:
		var b: Dictionary = e["biz"][int(bid)]
		if not b.get("closed", false) and String(b["type"]) != "farm" and int(b["owner"]) == int(f["id"]) and not keeps.has(int(bid)):
			return true   # a shop of the family without its keeper, and a grown-up who could keep it
	return false

## [ours] a place in a trade the family's people have worked before (their life histories) is weighed as paying this
## much more: Douglas 21:14 "unless the job fits their personality more". Town people have no traits or values in
## the register, so their past work is the only taste the sim has. A hungry or indebted family weighs pay alone.
const FIT_BONUS := 0.1
static var _casual_ids: Array = []

## v0.014 (Douglas 21:14: "youd think people would be interested in higher paying jobs first"): the family's hired
## places, chosen afresh each time it looks: the places it holds now and the open places it could take (whose till
## can pay two days of wages: nobody signs on at an empty till) are ranked by pay (a trade the family knows by its
## FIT_BONUS), and its free hands take the best of them; a hand in a worse-paid place leaves it for a better one (at
## equal pay he stays). Its own shops are not in this (Families.reassign tops them up first). Only this town's places
## (no one walks to another town for a day's work). Returns the family's hands at work in jobs.
static func _best_places(e: Dictionary, f: Dictionary, spare: int) -> int:
	var slots: int = spare
	if slots <= 0:
		return job_total(f)
	var biz: Array = e["biz"]
	var needy: bool = int(f.get("hungry", 0)) > 0 or float(f.get("debt", 0.0)) > 0.5
	var max_mult: float = 1.0 if needy else 1.0 + FIT_BONUS
	var known: Dictionary = {}
	var known_ready: bool = needy
	var cand: Array = []
	var cand_total: int = 0
	var held_total: int = 0
	var min_held_wage: float = INF
	for k in f["jobs"]:
		var n: int = int(f["jobs"][k])
		if n > 0:
			held_total += n
			min_held_wage = minf(min_held_wage, float(biz[int(k)]["wage"]))
	var held_ready: bool = held_total == 0
	var changed: bool = held_total > slots
	if held_total > slots:
		if not known_ready:
			known = _known_trades(e, f)
			known_ready = true
			max_mult = 1.0 if known.is_empty() else 1.0 + FIT_BONUS
		for k in f["jobs"]:
			cand_total = _add_cand(cand, cand_total, slots, _pay_score(e, biz[int(k)], known), int(k), 1, int(f["jobs"][k]))
		held_ready = true
	var open_ids: Array = e.get("open", [])
	var open_max: PackedFloat64Array = Businesses.open_suffix_max(e)
	var has_suf: bool = open_max.size() == open_ids.size()
	for i in open_ids.size():
		var bid: int = int(open_ids[i])
		var b: Dictionary = biz[bid]
		if b.get("closed", false):
			continue
		if (cand_total if held_ready else held_total) >= slots:
			if not held_ready:
				if float(b["wage"]) * max_mult <= min_held_wage:
					if has_suf and open_max[i] * max_mult <= min_held_wage:
						break
					continue
				if not known_ready:
					known = _known_trades(e, f)
					known_ready = true
					max_mult = 1.0 if known.is_empty() else 1.0 + FIT_BONUS
					if float(b["wage"]) * max_mult <= min_held_wage:
						if has_suf and open_max[i] * max_mult <= min_held_wage:
							break
						continue
				var sc0: float = _pay_score(e, b, known)
				if sc0 <= min_held_wage:
					continue
				var open0: int = Businesses.takeable(b, e)
				if open0 <= 0:
					continue
				for k in f["jobs"]:
					cand_total = _add_cand(cand, cand_total, slots, _pay_score(e, biz[int(k)], known), int(k), 1, int(f["jobs"][k]))
				held_ready = true
				if sc0 > float(cand[-1][0]):
					cand_total = _add_cand(cand, cand_total, slots, sc0, bid, 0, open0)
					changed = true
				continue
			var min_sc: float = float(cand[-1][0])
			if has_suf and open_max[i] * max_mult <= min_sc:
				break
			if float(b["wage"]) * max_mult <= min_sc:
				continue
			var sc: float = _pay_score(e, b, known)
			if sc <= min_sc:
				continue
			var open: int = Businesses.takeable(b, e)
			if open > 0:
				cand_total = _add_cand(cand, cand_total, slots, sc, bid, 0, open)
				changed = true
		else:
			var open: int = Businesses.takeable(b, e)
			if open <= 0:
				continue   # nobody signs on where the till is empty
			if not known_ready:
				known = _known_trades(e, f)
				known_ready = true
				max_mult = 1.0 if known.is_empty() else 1.0 + FIT_BONUS
			if not held_ready:
				for k in f["jobs"]:
					cand_total = _add_cand(cand, cand_total, slots, _pay_score(e, biz[int(k)], known), int(k), 1, int(f["jobs"][k]))
				held_ready = true
			cand_total = _add_cand(cand, cand_total, slots, _pay_score(e, b, known), bid, 0, open)
			changed = true
	var casual_ids: Array = []
	var cjcap: Dictionary = e.get("cjcap", {})
	if not f.has("hl") and not cjcap.is_empty():
		var cj_defs: Dictionary = TownEcon.data()["casual_jobs"]
		if _casual_ids.size() != cj_defs.size():
			_casual_ids = cj_defs.keys()
			_casual_ids.sort()
		casual_ids = _casual_ids
		var cjused: Dictionary = e.get("cjused", {})
		var day_w: float = Barge.day_wage(e)
		var base_w: float = float(Barge.B()["labour"]["base"])
		var cust_funds: float = -1.0
		var cust_exact: bool = false
		for ci in casual_ids.size():
			var j: String = String(casual_ids[ci])
			var used: float = float(cjused.get(j, 0))
			var places: int = int(floor(float(cjcap.get(j, 0)) - used + 0.00001))
			if places <= 0:
				continue
			var cj: Dictionary = cj_defs[j]
			var cw: float = day_w if cj.has("day") else clampf(day_w * (float(cj["wage"]) / base_w), day_w * 0.75, day_w * 1.8)
			if (cand_total if held_ready else held_total) >= slots:
				if cw <= (float(cand[-1][0]) if held_ready else min_held_wage):
					continue
			var payer: String = String(cj["payer"])
			var week_w: float = maxf(0.01, cw * 7.0)
			var funds: float = 0.0
			if payer == "treasury":
				funds = float(e.get("treasury", 0))
			elif payer == "customers":
				var need_funds: float = (float(places) + used) * week_w
				if cust_funds < need_funds and not cust_exact:
					cust_funds = _customer_funds_up_to(e, need_funds)
					if cust_funds < need_funds:
						cust_exact = true
				funds = cust_funds
			else:
				funds = float((biz[int(e["mkt"])] as Dictionary)["till"])
			var available: int = mini(places, maxi(0, int(floor(funds / week_w - used + 0.00001))))
			if available <= 0:
				continue
			if not held_ready:
				if not known_ready:
					known = _known_trades(e, f)
					known_ready = true
					max_mult = 1.0 if known.is_empty() else 1.0 + FIT_BONUS
				for k in f["jobs"]:
					cand_total = _add_cand(cand, cand_total, slots, _pay_score(e, biz[int(k)], known), int(k), 1, int(f["jobs"][k]))
				held_ready = true
				if cand_total >= slots and cw <= float(cand[-1][0]):
					continue
			cand_total = _add_cand(cand, cand_total, slots, cw, -ci - 1, 0, available)
			changed = true
	if not held_ready or not changed:
		return held_total
	var want := {}
	var casual := {}
	var casual_total := 0
	for entry in cand:
		var bid := int(entry[1])
		var n := int(entry[3])
		if bid < 0:
			var job := String(casual_ids[-bid - 1]); casual[job] = int(casual.get(job, 0)) + n; casual_total += n
		else:
			var key := str(bid); want[key] = int(want.get(key, 0)) + n
	for k in f["jobs"].keys():
		if not want.has(k):
			set_job(e, f, int(k), 0)
	for k in want:
		set_job(e, f, int(k), int(want[k]))
	if not casual.is_empty():
		f["cj"] = casual
		for j in casual: e["cjused"][j] = float(e["cjused"].get(j, 0)) + int(casual[j])
	return job_total(f) + casual_total

## Inserts up to `count` places into `cand` as grouped `[sc, bid, held, n]` runs, keeping only the best `slots`
## (higher score, then held before new, then earlier). Returns the updated total places in `cand`.
static func _add_cand(cand: Array, cand_total: int, slots: int, sc: float, bid: int, held: int, count: int) -> int:
	if count <= 0 or slots <= 0:
		return cand_total
	if cand_total >= slots:
		var last: Array = cand[-1]
		if sc < float(last[0]) or (sc == float(last[0]) and held <= int(last[2])):
			return cand_total
	var m: int = cand.size()
	var idx: int = m
	var before: int = 0
	for j in m:
		var cur: Array = cand[j]
		var csc: float = float(cur[0])
		if sc > csc or (sc == csc and held > int(cur[2])):
			idx = j
			break
		before += int(cur[3])
	var take: int = mini(count, slots - before)
	if take <= 0:
		return cand_total
	cand.insert(idx, [sc, bid, held, take])
	cand_total += take
	if cand_total > slots:
		var excess: int = cand_total - slots
		while excess > 0:
			var tail: Array = cand[-1]
			var tc: int = int(tail[3])
			if tc <= excess:
				cand.pop_back()
				excess -= tc
			else:
				tail[3] = tc - excess
				excess = 0
		cand_total = slots
	return cand_total

static func _customer_funds_up_to(e: Dictionary, cap_funds: float) -> float:
	var funds: float = 0.0
	for b in e["biz"]:
		if not b.get("closed", false):
			funds += maxf(0.0, float(b["till"]) - float(b["owed"]))
			if funds >= cap_funds:
				return funds
	var grain_week: float = float(e["price"].get("grain", 1)) * 7.0
	for f in e["fams"]:
		if not f.get("gone", false) and not f.get("estate", false):
			var purse: float = float(f["purse"])
			if purse > 0.0:
				funds += maxf(0.0, purse - float(daily_rates(e, f)["food"]) * grain_week)
				if funds >= cap_funds:
					return funds
	return funds

static func _available_casual(e: Dictionary, job: String) -> int:
	var used: float = float(e.get("cjused", {}).get(job, 0))
	var places: int = maxi(0, int(floor(float(e.get("cjcap", {}).get(job, 0)) - used + 0.00001)))
	if places <= 0:
		return 0
	var cj: Dictionary = TownEcon.data()["casual_jobs"][job]
	var week_w: float = maxf(0.01, Barge.casual_wage(e, job) * 7.0)
	var payer: String = String(cj["payer"])
	var funds: float = 0.0
	if payer == "treasury":
		funds = float(e.get("treasury", 0))
	elif payer == "customers":
		funds = _customer_funds_up_to(e, (float(places) + used) * week_w)
	else:
		funds = float(e["biz"][int(e["mkt"])]["till"])
	return mini(places, maxi(0, int(floor(funds / week_w - used + 0.00001))))

static func _pay_score(e: Dictionary, b: Dictionary, known: Dictionary) -> float:
	var w := float(b["wage"])
	if known.is_empty():
		return w
	return w * (1.0 + FIT_BONUS) if known.has(Recruits.job_title(e, b)) else w

## The work titles the family's grown-ups have held (their current place and their life histories).
static func _known_trades(_e: Dictionary, f: Dictionary) -> Dictionary:
	var out := {}
	for p in f.get("pp", []):
		if p.size() > Persons.JOB and String(p[Persons.JOB]) != "":
			out[String(p[Persons.JOB]).get_slice("@", 0)] = true
		if p.size() > Persons.HIST:
			for x in p[Persons.HIST]:
				if String(x[1]) == "job":
					out[String(x[2]).get_slice("@", 0)] = true
	return out

## A hand's worth on the family's own land, coins a day: what the land and herds make in a year at today's prices,
## per hand they need, and never less than a field hand's pay (1.15 x the day wage: what the family would pay a man to
## take his place, and what any hand earns in the fields).
static func land_worth(e: Dictionary, f: Dictionary, need: float) -> float:
	var D := TownEcon.data()
	var L: Dictionary = D["land"]
	var fw := Barge.day_wage(e) * float(Barge.B()["labour"]["field"])
	if need <= 0.0:
		return fw
	var price: Dictionary = e.get("price", {})   # (world gen: the goods' base prices)
	var G: Dictionary = D["goods"]
	var clim: Dictionary = D["climates"].get(String(e.get("climate", "temperate")), {})
	var v := 0.0
	for c in f["land"]:
		var y := CropRotation.family_yield(e, f, String(c))
		if c == "grain":
			y *= float(clim.get("grain_yield", 1.0))
		elif c == "fruit":
			y *= float(clim.get("fruit_yield", 1.0))
		v += float(f["land"][c]) * y * float(price.get(c, G.get(c, {}).get("price", 0.0))) / float(EconGen.YEAR_DAYS)
	var H: Dictionary = D["herds"]
	for a in f["herd"]:
		var outs: Dictionary = H.get(a, {})
		for og in outs:
			v += float(f["herd"][a]) * float(outs[og]) * float(price.get(og, G.get(og, {}).get("price", 0.0)))   # (meat: the slaughter shares average 1)
	return maxf(fw, v / need)

## Barge part 3 sections 1 and 5 (v0.011): the family weighs a member's pay in a trade against his worth on its own
## land. Before, every grown-up the land needed stayed on it whatever a trade paid (Grolruk: the land needs 179 hands
## of 140 grown-ups, so its tanner, woodcutter and builder stood empty for five years). The places a released hand
## could take: the trades' open places (not the fields or the public works) whose till can pay him, and the trade
## places the family holds now beyond its spare hands (it would keep them). The spare hands take the best of them first;
## a hand on the land leaves when the next place pays more than a whole hand's worth there (land_worth): even the last
## hand, whom the land needs for part of his days, is wanted whole at the harvest (it takes 2 x the hands: barge part 3
## section 1). So only a trade paying more than the fields draws a man off the land: one whose goods are scarce and that
## bids for hands (Businesses.bid_day). Returns how many leave the land.
static func _to_trades(e: Dictionary, f: Dictionary, own: int, ad: int, need: float, biz: Array) -> int:
	# Only the count above land_worth matters: the first k0 places go to spare hands.
	# Index counts by wage instead of allocating one value per hand and sorting them.
	var pay := {}
	var places := 0
	var field_types := ["farm", "estate", "works"]
	for k in f["jobs"]:
		var b: Dictionary = biz[int(k)]
		if not String(b["type"]) in field_types:
			var n := int(f["jobs"][k])
			var wage := float(b["wage"])
			pay[wage] = int(pay.get(wage, 0)) + n
			places += n
	for bid in e.get("open", []):
		var b: Dictionary = biz[int(bid)]
		if String(b["type"]) in field_types or b.get("closed", false):
			continue
		var n := Businesses.takeable(b, e)
		if n <= 0:
			continue
		var count := mini(n, own)
		var wage := float(b["wage"])
		pay[wage] = int(pay.get(wage, 0)) + count
		places += count
	var k0 := ad - own
	if places <= k0:
		return 0
	var worth := land_worth(e, f, need)
	var better := 0
	for wage in pay:
		if float(wage) > worth:
			better += int(pay[wage])
	return mini(own, maxi(0, better - k0))

## Released or newly financed places can appear after civilian household turns.
## Match only their real idle adults, with no advance to a wage day or payday.
static func match_idle(e: Dictionary) -> void:
	var funded := false
	for b in e["biz"]:
		if Businesses.takeable(b, e) > 0:
			funded = true; break
	# Paid casual work uses the same idle adults even when every regular shop
	# is full. Keep the existing funding and fractional-shift capacity rules.
	if not funded:
		for job in e.get("cjcap", {}):
			if _available_casual(e, String(job)) > 0:
				funded = true; break
	if not funded: return
	for f in e["fams"]:
		if not f.get("gone", false) and not f.get("estate", false) and int(f.get("idle", 0)) > 0:
			reassign(e, f)

## Generation: everyone finds work in family order.
static func assign_all(e: Dictionary) -> void:
	Businesses.rebuild_open(e)
	for f in e["fams"]:
		reassign(e, f)
	for f in e["fams"]:   # a second pass lets families fill places opened by the first
		if int(f.get("idle", 0)) > 0:
			reassign(e, f)

# ================================================================== the weekly family turn
## Household stores: what a family has bought ahead, in days (food, drink, firewood). The goods themselves sit
## in the town's household pool (e.hh, real integer counts) that the daily town pass eats from; a family's
## turn counts its days down and buys its share back from the market (spec 4: consumption over town totals).
const STORES := ["food", "drink", "wood"]
const LUXURY_SHARE := 0.05   # of the purse above family.rich_purse, per week [ours]
const LUX_G := ["meat", "wine", "furniture", "clothing"]
const LUX_W := [0.35, 0.3, 0.2, 0.15]
const LIFE_ROLL := 0.12   # share of family turns that look at births, ageing and deaths (scaled up when they do)
const ELDER_MEAN := 0.4   # an elder's mean years left = this x (lifespan - elder age): a human 8 of 20 (the old rule's 8)

static func turn(game, town: Dictionary, e: Dictionary, f: Dictionary, day: float, rng: RandomNumberGenerator) -> void:
	if f["gone"] or f.has("estate"):
		return
	_k()
	var _p0 := Time.get_ticks_usec() if TownEcon.prof_on else 0
	if Sickness.family_turn(game, town, e, f, day): return   # sickness: body meter (hunger deaths), remedies, bed-ridden days
	var days := clampf(day - float(f["last"]), 1.0, 60.0)
	f["last"] = day
	Barge.purse_drain(game.world, f, days)   # coinage: coin lost, buried or worn (0.072% a day)
	var biz: Array = e["biz"]
	# ---------------------------------------------------------------- income
	f["income_parts"] = {"land": 0.0, "staff wages": 0.0, "casual work": 0.0, "business profit": 0.0, "business funding": 0.0}
	var purse0 := float(f["purse"])
	var prior_wages := float(f.get("wage_receipts", 0.0))
	var prior_harvest := float(f.get("harvest_receipts", 0.0))
	var prior_harvest_gross := float(f.get("harvest_gross", 0.0))
	var prior_farm_funding := float(f.get("farm_funding_pending", 0.0))
	f["lpay"] = snappedf((settle(e, f) + prior_harvest_gross) * 7.0 / days, 0.01)
	f["income_parts"]["land"] = float(f["purse"]) - purse0 + prior_harvest
	f.erase("harvest_receipts"); f.erase("harvest_gross")
	var jobs: Dictionary = f["jobs"]
	var unpaid := 0
	var wages := WageClaims.pay_family(e, f)
	f["income_parts"]["staff wages"] = float(f.get("wage_receipts", 0.0))
	f.erase("wage_receipts")
	if bool(wages[1]):
		unpaid = int(f["unpaid"]) + 1
		if unpaid == 1: event(f, "unpaid", [Businesses.title(e, wages[2])], day)
	f["unpaid"] = unpaid
	if f.has("cj") or not f.get("cjearned", {}).is_empty():
		var casual_before := float(f["purse"])
		Shelter.pay_casual(e, f, days)
		f["income_parts"]["casual work"] = float(f["purse"]) - casual_before   # homeless families' casual work (day labour, portering ...)
	var owns: Array = f["owns"]
	if not owns.is_empty():
		var seen_biz := {}
		for bid in owns:
			if seen_biz.has(int(bid)): continue   # one owner turn (one take) per business a week
			seen_biz[int(bid)] = true
			var owner_before := float(f["purse"])
			Businesses.owner_turn(e, f, biz[int(bid)], days)
			var change := float(f["purse"]) - owner_before
			f["income_parts"]["business profit" if change >= 0 else "business funding"] += change
	f["income_parts"]["business funding"] -= prior_farm_funding
	f["inc"] = snappedf((float(f["purse"]) - purse0 + prior_wages + prior_harvest - prior_farm_funding) * 7.0 / days, 0.01)   # include once the wages received between ordinary turns
	for part in f["income_parts"]: f["income_parts"][part] *= 7.0 / days
	f.erase("farm_funding_pending")
	_harvest_share(e, f, day, days)
	if game != null:   # economy pass coin sinks: household staff and improvements, the house retinue and its kit, court events
		HouseUpkeep.observe_income(f, day)
		HouseUpkeep.weekly(game, town, e, f)
		TroopUpkeep.weekly(game, town, e, f)
		CourtEvents.weekly(game, town, e, f)
	_ruler_to_seat(game, town, e, f)
	var _pt := Time.get_ticks_usec() if TownEcon.prof_on else 0
	if TownEcon.prof_on: TownEcon._prof("f_income", _p0)
	# ---------------------------------------------------------------- stores run down (the pool was eaten daily)
	var food_days := days * (float(Shelter.D()["strain"]) if int(f["homes"]) <= 0 and not f.get("shel", false) else 1.0)
	EconomyRules.cover_food(e, f, food_days, day)
	var st: Dictionary = f["store"]
	var hungry_was := int(f["hungry"])
	f["food_at_hunger_check"] = float(st["food"])
	f["food_days_needed"] = food_days
	var food0 := float(st["food"])   # what the larder held when the family last shopped
	var food: float
	if int(f["homes"]) <= 0:
		food = Shelter.eat(town, e, f, days)   # homeless: broth in the shelter, or their own food (faster without a hearth)
	else:
		food = float(st["food"]) - days
	if food < 0.0:
		food += Barge.gruel(e, f, -food)   # barge: the gruel kitchen feeds the hungry poor out of the granary
	# barge part 2 section 6 (FIX-3): hunger is per family, from its own larder; a full larder is Fed whatever the town.
	# The days it went short: what the larder (or the broth, the gruel) did not cover, and of the days it did, the share
	# the town's household pool could not put on the table (e.food_short). One number: the famine stage and the body
	# meter (Sickness.food_short_days) both read it.
	var short := clampf(-food, 0.0, days)
	# Household hunger comes only from its own uncovered food days.
	f["scraps_kg"] = float(f.get("scraps_kg", 0)) + maxf(0, days - short) * float(people(f)) * 0.025
	f["fshort"] = short
	var stage := Barge.family_stage(e, f, days, short, food0)
	f["hungry"] = stage
	if stage > 0 and hungry_was == 0:
		event(f, "hunger", [Calendar.season_index(day)], day)
	st["food"] = maxf(0.0, food)
	# deaths of hunger: the body meter (sickness 6b), the one path ("starved", the census once)
	if Sickness.body_turn(game, town, e, f, day, days):
		return
	# flight to a real town (barge part 4 section 6)
	if Barge.maybe_flee(game, town, e, f, stage, days, rng, day):
		return
	st["drink"] = maxf(0.0, float(st["drink"]) - days)
	var fuel_rate := float(daily_rates(e, f)["wood"])
	EconomyRules.buy_essential(e, f, "wood", int(ceil(maxf(0, days - float(st["wood"])) * fuel_rate)), "wood", fuel_rate)
	var wood: float = float(st["wood"]) - days
	st["wood"] = maxf(0.0, wood)
	# ---------------------------------------------------------------- tax, loans, the land loop
	if int(f["tax_season"]) != int(e["tax"]["season"]) or float(f["debt"]) > 0.0:
		_taxes(game, town, e, f, day, days)
	# ---------------------------------------------------------------- rent to the landlord (barge part 4 section 4)
	if f.has("landlord") and int(f["homes"]) > 0:
		_pay_rent(e, f, days, day)
	# ---------------------------------------------------------------- homes
	var cond: float = float(f["cond"]) - float(e["hdecay"]) * days * (1.3 if wood < 0.0 else 1.0)
	f["cond"] = maxf(0.0, cond)
	if cond < 0.85:
		var hm: Dictionary = TownEcon.culture_of(e)["home"]
		_repair(e, f, hm)
		if float(f["cond"]) < 0.2 and int(f["homes"]) > 0:
			f["homes"] = int(f["homes"]) - 1
			e["homes"] = int(e["homes"]) - 1
			f["cond"] = 0.6
			event(f, "home_ruin", [hm["type"]], day)
			if f["named"]:
				add_hist(f, "A %s fell into ruin." % hm["type"], day)
			if int(f["homes"]) <= 0:
				Shelter.lost_home(e, f, "ruin", day)
	# ---------------------------------------------------------------- homeless: the shelter, casual work, a roof again
	if int(f["homes"]) <= 0 or f.has("hl") or int(f.get("rent", 0)) > 0:
		Shelter.turn(town, e, f, day)
	if TownEcon.prof_on: _pt = TownEcon._prof("f_stores_homes", _pt)
	# ---------------------------------------------------------------- work (only when something changed)
	var do_reassign := unpaid > 0 or int(f["idle"]) > 0 or _over_cap(biz, jobs) or keeps_stale(e, f) or assignments_stale(f)
	var work: Dictionary = {}
	var herd_need := -1.0
	var helpers := -1.0
	if not do_reassign:
		work = crop_work(f, e)
		herd_need = herd_hands(f, e)
		var need := float(work["base"]) + herd_need
		helpers = minf(need, Barge.helper_hands(e, f, float(e.get("day", 0)))) if need > 0.0 else 0.0
		var harvest_now := float(work["harvest"]) > 0.0
		var farm_season_changed := (not f.has("farm_harvest") or bool(f["farm_harvest"]) != harvest_now) and need > 0.0
		do_reassign = farm_season_changed or _paid_worse(e, f, biz, need, helpers) or _farm_capacity_stale_with(e, f, work, need, helpers)
	if do_reassign:
		_reassign_with(e, f, work, herd_need, helpers)
	if TownEcon.prof_on: _pt = TownEcon._prof("f_reassign", _pt)
	# ---------------------------------------------------------------- people: one roll a week for life events;
	# hungry or crowded families lose people to the road
	if Persons.age_up(e, f, day):   # children come of age, adults grow old, the oldest die (by their birth days)
		reassign(e, f)
		if people(f) <= 0:
			extinct(e, f, day)
			return
	# births: every married woman of the family by her own body and her race's years (Persons.childbearing)
	Population.turn(e, f, day, days)
	var bore := {}
	for kid in Persons.childbearing(e, f, day, days, int(f["hungry"]) > 0):
		born(e, f, kid, day)
		if not bore.has(int(kid[Persons.MO])):   # one birth (twins and litters too): one roll
			bore[int(kid[Persons.MO])] = true
			Persons.childbed(game, town, e, f, kid, day)   # the mother may die in childbirth (cause "childbirth")
	if f["gone"]:
		return
	var pre := rng.randf()
	if pre < LIFE_ROLL or int(f["hungry"]) >= 2:
		_people(town, e, f, TownEcon.culture_of(e), day, rng, 1.0 / LIFE_ROLL if pre < LIFE_ROLL else 0.0)
		if f["gone"]:
			return
	if TownEcon.prof_on: _pt = TownEcon._prof("f_people", _pt)
	# ---------------------------------------------------------------- the coping ladder (barge part 2 section 7)
	# v0.014 (Douglas 23:00): a family short of food money sells its stones first (Legends.sell_gems); it pawns only
	# when it had none to sell
	if float(f["purse"]) < float(TownEcon.data()["family"]["min_purse"]) or int(f["hungry"]) > 0:
		if Legends.sell_gems(e, f, day) <= 0.0 and int(f["homes"]) > 0:
			Barge.pawn(e, f, day)
	# ---------------------------------------------------------------- the head lends when the purse can't cover a week
	if float(f["purse"]) < 40.0 * TownEcon.COIN:
		Loans.maybe_borrow(e, f, day)
	# ---------------------------------------------------------------- restock (the day's orders clear together)
	if TownEcon.prof_on: _pt = TownEcon._prof("f_coping", _pt)
	Persons.sync(e, f, day)   # the register's person records follow the row (births grown up, the old, the dead)
	Persons.track_jobs(e, f, day)   # life histories: places taken and left
	refresh_worked(e, f)   # hunger and helper ages can change without taking a new job
	refresh_employers(e, f)   # the same is true of the household supplying hired hands
	if TownEcon.prof_on: _pt = TownEcon._prof("f_sync", _pt)
	# Capacity can grow at the ordinary seasonal/age reassignment after income
	# was recorded. Report only the real transfer, once, before restock budgets.
	var late_farm_funding := float(f.get("farm_funding_pending", 0.0))
	if late_farm_funding > 0.0:
		f["income_parts"]["business funding"] -= late_farm_funding * 7.0 / days
		f["inc"] = snappedf(float(f["inc"]) - late_farm_funding * 7.0 / days, 0.01)
		f.erase("farm_funding_pending")
	_restock(e, f, days)
	if TownEcon.prof_on: _pt = TownEcon._prof("f_restock", _pt)
	if not TownEcon.batch_open:
		TownEcon.clear_batch(e)   # a turn run on its own (not in the day's batch) clears at once

## Existing callers refresh the physical reserve; weekly turns no longer
## invent harvest from today's acres, yield or work since a previous turn.
static func _harvest_share(e: Dictionary, f: Dictionary, _day: float, _days: float) -> void:
	HarvestClaims.reserve_food(e, f)

## Economy pass: the seat's estate tax, tribute and the house's own land and trades all land in the ruling household's
## purse, while the town's guards, levies, public tills and works are paid from its treasury. A native (AI) ruling
## house keeps a working purse of RULER_KEEP x COIN x (town size + 1) and each week puts RULER_SURPLUS_SHARE of what
## it holds above that into its seat's treasury, the same transfer as the player's "fund garrison" decree (one debit,
## one credit), never filling the treasury above its public spending target. The player's house is never
## moved: the player funds his treasury himself. (Before: AI purses rose 6-50x in 87 days while treasuries ran dry.)
const RULER_KEEP := 1000.0
const RULER_SURPLUS_SHARE := 0.5

static func _ruler_to_seat(game, town: Dictionary, e: Dictionary, f: Dictionary) -> void:
	if game == null or Population.is_cohort(f) or not e.has("treasury"):
		return
	var scale := TownEcon.COIN * float(int(town.get("size", 0)) + 1)
	var spare: float = minf(float(f["purse"]) - RULER_KEEP * scale, HouseUpkeep.spend_room(e, f))
	var room: float = Barge.treasury_target(game, town, e) - float(e["treasury"])
	if spare <= 0.0 or room <= 0.0:
		return
	var uid := str(f.get("household_uid", ""))
	if uid == "" or uid == str(game.world.get("player_house", {}).get("household_uid", "")):
		return
	var lord: Dictionary = Feudal.tax_recipient(game, str(town.get("id", "")))
	if str(lord.get("household_uid", "")) != uid:
		return
	var give: float = minf(minf(spare * RULER_SURPLUS_SHARE, room), HouseUpkeep.recent_income(f) * 0.10 / HouseUpkeep.weeks_per_year())
	HouseUpkeep.book_spending(f, give)
	f["purse"] = float(f["purse"]) - give
	e["treasury"] = float(e["treasury"]) + give
	if e.has("stats"):
		e["stats"]["house_funding"] = float(e["stats"].get("house_funding", 0.0)) + give

static func _pay_rent(e: Dictionary, f: Dictionary, days: float, day: float) -> void:
	var lid := int(f["landlord"])
	var fams: Array = e["fams"]
	if lid < 0 or lid >= fams.size() or fams[lid].get("gone", false):
		f.erase("landlord")
		f.erase("rent_due")
		return
	var lord: Dictionary = fams[lid]
	var due := (TownHousing.rent_week(e, f) if f.has("lodging") else Barge.rent_week(e) * float(f["homes"])) * days / 7.0 * (1.0 + 0.5 * float(e.get("surcharge", 0.0))) + float(f.get("rent_due", 0.0))
	var pay := minf(due, maxf(0.0, float(f["purse"]) - 1.0))
	f["purse"] = float(f["purse"]) - pay
	lord["purse"] = float(lord["purse"]) + pay
	if due - pay > 0.5:
		f["rent_due"] = due - pay
		f["rent_late"] = int(f.get("rent_late", 0)) + 1
		if int(f["rent_late"]) >= int(Barge.B()["rent"]["evict_weeks"]):
			if f.has("lodging"):
				TownHousing.leave(e, f, day); return
			e["fams"][0]["homes"] = int(e["fams"][0]["homes"]) + int(f["homes"])
			e["homes"] = int(e["homes"]) - int(f["homes"])
			f["homes"] = 0
			f.erase("landlord"); f.erase("rent_due"); f.erase("rent_late")
			event(f, "evicted", [], day)
			add_hist(f, "Fell behind on the rent and were put out.", day)
			Shelter.lost_home(e, f, "evicted", day)
	else:
		f.erase("rent_due")
		f.erase("rent_late")

## A hand of the family in a hired place paying less than the best open place in town whose till can pay (v0.014:
## he looks again at his turn and moves when it is better: _best_places).
static func _paid_worse(e: Dictionary, f: Dictionary, biz: Array, need_in: float = -1.0, helpers_in: float = -1.0) -> bool:
	# Crops can become worth more than an existing town job even with no funded
	# vacancy. Reconsider own land as well as offers from other employers.
	var need: float = need_in if need_in >= 0.0 else need_hands(f, e)
	if need > 0.0 and not f["jobs"].is_empty():
		var helpers: float = helpers_in if helpers_in >= 0.0 else Barge.helper_hands(e, f, float(e.get("day", 0)))
		var available: int = maxi(0, adults(f) - serving(f) - (f.get("keeps", []) as Array).size())
		var target: int = mini(available, maxi(0, int(ceil(need - minf(need, helpers) - 0.3))))
		if int(f["hands"]) < target:
			var worth: float = land_worth(e, f, need)
			for k in f["jobs"]:
				var held: Dictionary = biz[int(k)]
				if not String(held["type"]) in ["farm", "estate", "works"] and float(held["wage"]) <= worth:
					return true
	# Compare today's funded offers, including casual work and paid relatives.
	# The cached weekly highest offer may have filled, gained funds or changed pay.
	if f["jobs"].is_empty() and (f.has("hl") or f.get("cj", {}).is_empty()): return false
	var needy := int(f.get("hungry", 0)) > 0 or float(f.get("debt", 0.0)) > 0.5
	var known := {} if needy else _known_trades(e, f)
	var max_mult := 1.0 if known.is_empty() else 1.0 + FIT_BONUS
	var lowest := INF
	for k in f["jobs"]:
		var b: Dictionary = biz[int(k)]
		lowest = minf(lowest, _pay_score(e, b, known))
	if not f.has("hl"):
		for j in f.get("cj", {}): lowest = minf(lowest, Barge.casual_wage(e, j))
	for b in biz:
		if b.get("closed", false) or int(b["cap"]) <= int(b["workers"]) or float(b["wage"]) * max_mult <= lowest:
			continue
		if _pay_score(e, b, known) > lowest and Businesses.takeable(b, e) > 0:
			return true
	if not f.has("hl"):
		for j in TownEcon.data()["casual_jobs"]:
			if Barge.casual_wage(e, String(j)) > lowest and _available_casual(e, String(j)) > 0:
				return true
	return false

static func _over_cap(biz: Array, jobs: Dictionary) -> bool:
	for k in jobs:
		var b: Dictionary = biz[int(k)]
		if int(b["workers"]) > int(b["cap"]) or b["closed"]:
			return true
	return false

## Fractional use carried between turns: returns the whole units due now.
static func _whole(f: Dictionary, key: String, amount: float) -> int:
	var w: Dictionary = f["wear"]
	var v := float(w.get(key, 0.0)) + amount
	var n := int(floor(v))
	w[key] = v - n
	return n

## Repairs buy the home's own materials at the market (a tenth of a new home restores 0.1 condition).
static func _repair(e: Dictionary, f: Dictionary, hm: Dictionary) -> void:
	var mats: Dictionary = hm["materials"]
	var repair_homes := maxi(1, int(f["homes"])) if Population.is_cohort(f) else 1
	var st: Dictionary = e["stock"]
	var price: Dictionary = e["price"]
	var cost := 0.0
	var short := false
	for m in mats:
		var need := maxi(1, int(ceil(float(mats[m]) * 0.1 * repair_homes)))
		if int(st.get(m, 0)) < need:
			short = true
		cost += float(need) * float(price[m])
	# the repair's materials are wanted at the market like any household want (barge part 2: demand = bought + unmet
	# + a fifth of the unaffordable), so a town short of leather, wood or stone raises their price and its makers
	if short or float(f["purse"]) < cost + 5.0 * TownEcon.COIN:
		for m in mats:
			var need2 := float(maxi(1, int(ceil(float(mats[m]) * 0.1 * repair_homes))))
			Barge.add_demand(e, m, 0.0, need2 if short else 0.0, 0.0 if short else need2)
		return
	for m in mats:
		var need := maxi(1, int(ceil(float(mats[m]) * 0.1 * repair_homes)))
		st[m] = int(st[m]) - need
		TownEcon.led(e, "used", m, need)
		Barge.add_demand(e, m, float(need), 0.0, 0.0)
	TownEcon.pay_market(e, f, cost)
	f["cond"] = minf(1.0, float(f["cond"]) + 0.1)


## Seasonal tax and the head's loans (spec 7, one loop: campaign/loans.gd): a tax the family can't pay becomes
## debt to the head (no coin moves); coin loans for food, rent, tools, seed or land are the same debt; it is
## repaid weekly with interest; missed payments in a row -> the family sells its things in order (stores, goods,
## tools, livestock, land, the house; the head buys what nobody else will), until it is clear or destitute.
static func _taxes(game, town: Dictionary, e: Dictionary, f: Dictionary, day: float, days: float = 7.0) -> void:
	var T: Dictionary = TownEcon.data()["tax"]
	var tx: Dictionary = e["tax"]
	var head_title: String = e.get("head", {}).get("title", "head")
	# (the coin taxes are monthly and town-wide now: barge part 4 section 1, Barge.treasury_month)
	f["tax_season"] = int(tx["season"])
	if float(f["debt"]) > 0.0:
		Loans.weekly(e, f, day, days)
	if acres(f) == 0 and heads(f) == 0 and (f["owns"] as Array).is_empty() and float(f.get("ln", {}).get("lent", 0.0)) > 0.0 \
			and not f.get("ruined", false) and not (f.get("ln", {}).get("sold", []) as Array).is_empty():
		f["ruined"] = true
		event(f, "ruined", [], day)
		add_hist(f, "Ruined: landless labourers now.", day)

static func _people(town: Dictionary, e: Dictionary, f: Dictionary, cul: Dictionary, day: float, rng: RandomNumberGenerator, ev_mult: float = 1.0) -> void:
	if Population.is_cohort(f): return
	var room := (float(f["lodging_rooms"]) * TownHousing.PEOPLE_PER_ROOM if f.has("lodging") else float(f["homes"]) * float(cul["home"]["room"])) * (0.6 + 0.4 * float(f["cond"]))
	var m := int(f["m"]); var fe := int(f["f"]); var kids := int(f["kids"]); var old := int(f["old"])
	var ppl := float(m + fe + kids + old)
	# one roll a week for the old dying (a year is EconGen.YEAR_DAYS days). Families with person records: births come
	# from each married woman (Persons.childbearing, every family turn); children come of age and adults grow old by
	# their birth days (Persons.age_up); the elder who dies is the oldest. Record-less rows (tests, older paths) keep
	# the old rolls (a birth a turn at the culture's growth, only into room, never while hungry).
	var yd := float(EconGen.YEAR_DAYS)
	var rec := f.has("pp")
	var pb := float(cul["growth"]) if not rec and int(f["hungry"]) == 0 and ppl < room and fe > 0 and m > 0 else 0.0
	var pk := 0.0 if rec else float(kids) * 7.0 / (14.0 * yd)
	var pa := 0.0 if rec else float(m + fe) * 7.0 / (40.0 * yd)
	# an elder dies with the chance that gives a human elder 8 years on average (of the 20 between elder 55 and lifespan
	# 75): every race by its own elder years (v0.011: it was 8 for every race, so elves of 300, with 150 years to their
	# lifespan, died "of old age" as fast as a human of 60; orcs and goblins, with 15 and 10, too slowly)
	var ab := People.ages(Persons.race_of(e))
	var po := float(old) * 7.0 / (ELDER_MEAN * maxf(1.0, float(ab["lifespan"]) - float(ab["elder"])) * yd)
	var r := rng.randf() / ev_mult if ev_mult > 0.0 else 99.0   # pre-rolled in the turn: events x ev_mult likely here
	if r < pb + pk + pa + po:
		if r < pb:
			born(e, f, [], day)   # (a record-less row)
		elif r < pb + pk:
			f["kids"] = kids - 1
			var s: String = "m" if r < pb + pk * 0.5 else "f"
			f[s] = int(f[s]) + 1
			e["adults"] = int(e["adults"]) + 1
		elif r < pb + pk + pa:
			var s2: String = "m" if r < pb + pk + pa * 0.5 else "f"
			if int(f[s2]) > 0:
				f[s2] = int(f[s2]) - 1
				f["old"] = old + 1
				e["adults"] = int(e["adults"]) - 1
				reassign(e, f)
		elif Persons.can_lose(f, 2):
			var el: Array = Persons.oldest_elder(f) if rec else []
			if not el.is_empty():
				Persons.die_elder(e, f, el, day)
			else:
				e["stats"]["deaths"] = int(e["stats"].get("deaths", 0)) + 1
				Census.record_death(e, -1, "", -1, -1, day, "old age", "", true, int(f["id"]))   # the census: one death, one cause
				f["old"] = old - 1
				event(f, "elder", [""], day)
				e["pop"] = int(e["pop"]) - 1
				if f["named"]:
					add_hist(f, "An elder of the family died.", day)
			if people(f) <= 0:
				extinct(e, f, day)   # the last of the house died: property to the head, cash to the realm
				return
	# (barge part 4 section 6: only hungry families leave, the whole family to a real town: Barge.maybe_flee in the turn;
	# nobody walks off the map)
	if people(f) <= 0:
		extinct(e, f, day)

## A child was born to the family today (kid: its record, [] for a record-less row): the row, the town's people, the
## census, the family's news.
static func born(e: Dictionary, f: Dictionary, kid: Array, day: float) -> void:
	f["kids"] = int(f["kids"]) + 1
	e["pop"] = int(e["pop"]) + 1
	if f.get("shel", false):
		e["shel_n"] = int(e.get("shel_n", 0)) + 1   # born in the poorhouse: one more mouth at its broth
	e["stats"]["births"] = int(e["stats"].get("births", 0)) + 1
	Census.record_birth(e, day, int(kid[0]) if not kid.is_empty() else -1)   # the census (town screen): births
	event(f, "born", [Persons.first_of(e, kid) if not kid.is_empty() else ""], day)
	if f["named"]:
		add_hist(f, "A child was born.", day)

## The family is gone: its land goes to the town (offered for sale), its goods and purse go with it
## (they leave on the road: counted as used), its businesses close.
static func leave_town(e: Dictionary, f: Dictionary, day: float) -> void:
	if f.get("gone", false):
		return
	Shelter.forget(e, f)
	settle(e, f)
	HarvestClaims.transfer(e, "f:%d" % int(f["id"]), "f:0")
	var estate: Dictionary = e["fams"][0]
	for c in f["land"].keys():
		move_land(e, f, estate, c, int(f["land"][c]))
	for a in f["herd"].keys():
		move_herd(e, f, estate, a, int(f["herd"][a]))
	for k in f["jobs"].keys():
		set_job(e, f, int(k), 0)
	set_worked(e, f, 0.0)
	e["hands"] = int(e.get("hands", 0)) - int(f["hands"])
	f["hands"] = 0
	for bid in f["owns"]:
		var b: Dictionary = e["biz"][int(bid)]
		Businesses.town_inherits(b)
	# what they had laid by leaves with them (out of the household pool; their purse goes with them)
	_take_stores(e, f)
	e["homes"] = int(e["homes"]) - int(f["homes"])
	f["homes"] = 0
	var left := float(f["purse"])
	e["stats"]["gold_left"] = float(e["stats"].get("gold_left", 0.0)) + left
	e["treasury"] = float(e["treasury"]) + left   # coin is never lost off the map: the town takes what nobody claims
	f["purse"] = 0.0
	f["gone"] = true
	add_hist(f, "The family left town.", day)

## The house died out (battle, old age, an AI clash): all its property goes to the state, the town's head where
## it lies (land and herds to the town estate, offered for sale by the spec-1 loop; businesses for sale; homes
## to the estate; its stores stay in the town); the remaining cash goes to the faction's coffer.
static func living_company_member(e: Dictionary, f: Dictionary) -> bool:
	for p in f.get("pp", []):
		if not str(p[4]) in ["company", "captive"] or int(p[5]) < 0: continue
		var u: Unit = Persons._unit(int(p[5]))
		if u == null or u.dead: continue
		# v0.033: a member held captive (campaign/prisoners.gd) is alive and can still come home
		if not (Game.company.has(u) if str(p[4]) == "company" else Prisoners.captive_unit(Game, u.uid) == u): continue
		var town: Dictionary = Game.world.get("towns", {}).get(u.home_town, {})
		if not is_same(town.get("econ", {}), e) or not is_same(People.fam_of(town, u.family), f): continue
		if is_same(Persons.by_uid(f, u.uid), p) and ServiceIdentity.unit_person(e, f, p, u): return true
	return false

## A previously struck-off row can receive its actual surviving member again.
## Already inherited land/businesses/homes/coin stay with their current owners.
static func restore_returned(e: Dictionary, f: Dictionary) -> bool:
	if not f.get("gone", false): return true
	if not f.get("extinct", false) or str(f.get("moved", "")) != "" or not living_company_member(e, f): return false
	f["gone"] = false
	f.erase("extinct"); f.erase("packed"); f.erase("gone_at")
	return true

static func extinct(e: Dictionary, f: Dictionary, day: float) -> void:
	if living_company_member(e, f): return
	if f.get("gone", false):
		return
	Shelter.forget(e, f)
	settle(e, f)
	HarvestClaims.transfer(e, "f:%d" % int(f["id"]), "f:0")
	var estate: Dictionary = e["fams"][0]
	for c in f["land"].keys():
		move_land(e, f, estate, c, int(f["land"][c]))
	for a in f["herd"].keys():
		move_herd(e, f, estate, a, int(f["herd"][a]))
	for k in f["jobs"].keys():
		set_job(e, f, int(k), 0)
	set_worked(e, f, 0.0)
	e["hands"] = int(e.get("hands", 0)) - int(f["hands"])
	f["hands"] = 0
	for bid in f["owns"]:
		var b: Dictionary = e["biz"][int(bid)]
		Businesses.town_inherits(b)
	f["owns"] = []
	f["keeps"] = []
	TownHousing.leave(e, f, day)
	estate["homes"] = int(estate["homes"]) + int(f["homes"])
	f["homes"] = 0
	var cash := float(f["purse"])
	f["purse"] = 0.0
	var town_fid := String(e.get("faction", ""))
	var fac: Dictionary = Game.world.get("factions", {}).get(town_fid, {})
	if not fac.is_empty():
		fac["treasury"] = float(fac.get("treasury", 0.0)) + cash
	else:
		e["treasury"] = float(e["treasury"]) + cash
	f["gone"] = true
	f["extinct"] = true
	add_hist(f, "The house died out; its property passed to the %s." % e.get("head", {}).get("title", "head"), day)
	TownEcon.town_hist(e, "The %s house died out; the %s took its property." % [f["name"], e.get("head", {}).get("title", "head")], day)

## Loot hook (core/loot.gd): the coin a dead man carried, out of his household's real purse. An ordinary
## dead enemy carries min(share x purse, max_carried); if he was the last living member of his house the
## looter gets min(last_share x purse, max_carried) and ALL the rest of the cash goes to his faction's coffer
## (the property goes to the town head when the house is struck off: extinct()). 0 without a family.
static func take_carried_coin(u: Unit, share: float, last_share: float, max_carried: int) -> int:
	if u == null:
		return 0
	if u.family < 0:
		# no household record (monsters own nothing; every person of a force has his family since economy spec 2):
		# coinage: no purse, no coin (coin is never made from nothing)
		return 0
	var town: Dictionary = Game.world.get("towns", {}).get(u.home_town, {})
	if not TownEcon.has_econ(town):
		return 0
	var e: Dictionary = town["econ"]
	if u.family >= (e["fams"] as Array).size():
		return 0
	var f: Dictionary = e["fams"][u.family]
	if f.get("gone", false) or f.has("estate"):
		return 0
	var purse := maxf(0.0, float(f["purse"]))
	var last := people(f) <= 1 and not living_company_member(e, f)
	var c := int(minf(purse * (last_share if last else share), float(max_carried)))
	f["purse"] = purse - float(c)
	TownEcon.gold_out(float(c))   # into the looter's purse (outside the town ledgers)
	if last:
		var fac: Dictionary = Game.world.get("factions", {}).get(String(town["faction"]), {})
		if not fac.is_empty():
			fac["treasury"] = float(fac.get("treasury", 0.0)) + float(f["purse"])
			f["purse"] = 0.0
	return c

const HOUSEHOLD_FOOD := ["grain", "fruit", "meat", "fresh_meat"]

## Apportion one bounded integer withdrawal across real goods. Independent
## rounding per good can otherwise take more meals than a family owns.
static func store_quantities(pool: Dictionary, goods: Array, requested: float) -> Dictionary:
	var total := 0
	for good in goods:
		total += maxi(0, int(pool.get(good, 0)))
	var wanted := mini(total, maxi(0, int(round(requested))))
	var out := {}
	if wanted <= 0 or total <= 0:
		return out
	var remainders := []
	var assigned := 0
	for good in goods:
		var exact := float(wanted) * float(maxi(0, int(pool.get(good, 0)))) / float(total)
		var q := int(floor(exact))
		out[good] = q
		assigned += q
		remainders.append({"good": good, "rest": exact - q, "order": remainders.size()})
	remainders.sort_custom(func(a, b): return a["rest"] > b["rest"] if a["rest"] != b["rest"] else a["order"] < b["order"])
	for i in wanted - assigned:
		out[remainders[i]["good"]] += 1
	return out

## A family's stores taken out of the town's household pool (it leaves, or a member takes a share).
static func _take_stores(e: Dictionary, f: Dictionary) -> void:
	var hh: Dictionary = e["hh"]
	var st: Dictionary = f["store"]
	var rates := daily_rates(e, f)
	var lu: Dictionary = e["led"]["used"]
	var take := {"food": float(st["food"]) * float(rates["food"]), "drink": float(st["drink"]) * float(rates["drink"]),
		"wood": float(st["wood"]) * float(rates["wood"])}
	for k in take:
		var goods: Array = HOUSEHOLD_FOOD if k == "food" else (["beer", "wine"] if k == "drink" else ["wood"])
		var quantities := store_quantities(hh, goods, float(take[k]))
		for g in quantities:
			var q := int(quantities[g])
			if q > 0:
				hh[g] = int(hh[g]) - q
				lu[g] = int(lu.get(g, 0)) + q
	for k in st:
		st[k] = 0.0

## Constants the weekly turn reads, pulled out of data/economy.json once (the turn runs ~400 times a day).
static var _k_ready := false
static var K_FOOD := 2.0
static var K_DRINK := 1.0
static var K_TFOOD := 30.0
static var K_TDRINK := 14.0
static var K_TWOOD := 14.0
static var K_RICH := 400.0
static var K_MIX_G := ["grain", "fruit", "meat"]
static var K_MIX := [0.65, 0.15, 0.2]
static var K_WEAR_G := ["clothing", "tools", "blankets", "furniture"]
static var K_WEAR_D := [180.0, 150.0, 365.0, 500.0]
static var K_JEWEL_D := 240.0

static func _k() -> void:
	if _k_ready:
		return
	var D := TownEcon.data()
	var nd: Dictionary = D["needs"]
	K_FOOD = float(nd["food"]); K_DRINK = float(nd["drink_adult"])
	var tg: Dictionary = nd["family_targets"]
	K_TFOOD = float(tg["food"]); K_TDRINK = float(tg["drink"]); K_TWOOD = float(tg["wood"])
	K_RICH = float(D["family"]["rich_purse"])
	var mix: Dictionary = nd["food_mix"]
	K_MIX_G = []; K_MIX = []
	for k in mix:
		K_MIX_G.append(k); K_MIX.append(float(mix[k]))
	var wd: Dictionary = nd["wear_days"]
	K_WEAR_G = []; K_WEAR_D = []
	for k in wd:
		if k == "jewelry":
			K_JEWEL_D = float(wd[k])
		else:
			K_WEAR_G.append(k); K_WEAR_D.append(float(wd[k]))
	_k_ready = true

## What a family uses per day: meals, mugs and cups, loads of firewood (this season: e["wf"] per home).
static func daily_rates(e: Dictionary, f: Dictionary) -> Dictionary:
	_k()
	var eq := float(Barge.eaters(e, f, float(e.get("day", 0)), false)[0])
	return {"food": maxf(0.6, eq) * K_FOOD, "drink": float(adults(f)) * K_DRINK, "wood": float(f["homes"]) * float(e.get("wf", 0.5))}

## Food comes only from the family's own physical stored goods, including
## harvest it still owns after selling its fields. No paper entitlement buys it.
static func keep_harvest(e: Dictionary, f: Dictionary, meals: int, rate: float) -> int:
	return HarvestClaims.keep_food(e, f, meals, rate)

## The family buys at the market (the day's price; the market clears against its stock), topping its stores up
## to its own targets (needs.family_targets: days of food, drink, firewood) once they run below 60% of them;
## its share of clothes, tools, blankets and household goods as they wear out (wealthy families: jewelry);
## a new home when crowded.
static func _restock(e: Dictionary, f: Dictionary, days: float) -> void:
	_k()
	f["frate"] = float(Barge.eaters(e, f, float(e.get("day", 0)))[0])
	var food_rate := float(daily_rates(e, f)["food"])
	keep_harvest(e, f, int(ceil(maxf(0.0, 7.0 - float(f["store"]["food"])) * food_rate)), food_rate)
	var purse: float = f["purse"]
	if purse <= 2.0:
		return
	var b: Array = TownEcon.batch
	var st: Dictionary = f["store"]
	var mkt: Dictionary = e["stock"]
	var barn: Dictionary = e["barn"]
	var price: Dictionary = e["price"]
	var _rt := Time.get_ticks_usec() if TownEcon.prof_on else 0
	var X := Barge.hctx(e)   # the town's household constants for today (classes' jars, budgets, staples on offer)
	if TownEcon.prof_on: _rt = TownEcon._prof("r_hctx", _rt)
	var H: Dictionary = Barge.B()["household"]
	var mk: float = X["mk"]
	var ppl := float(int(f["m"]) + int(f["f"]) + int(f["kids"]) + int(f["old"]))
	var ad := float(int(f["m"]) + int(f["f"]))
	var homes := float(f["homes"])
	var c := int(f.get("cls", 0))   # (the class moves with the savings at the town's weekly turn: Barge.klass)
	var day: float = X["day"]
	var fr := food_rate   # meals a day: children under 10 eat 0.6, 10-14 0.8 of a share
	var inc_w := maxf(0.0, float(f.get("inc", 0.0)))
	var stage := int(f.get("hungry", 0))
	var d7 := absf(days - 7.0) < 0.001
	# barge part 2 section 5. Budget for essentials <= min(savings, income + 35% of savings) a day: over the turn's days
	# income x days + (1 - 0.65^days) of the savings.
	var ess_cap := minf(purse, inc_w * days / 7.0 + (float(X["ess7"]) if d7 else (1.0 - pow(1.0 - float(H["essentials_save"]), days))) * purse)
	var spent := 0.0
	var fill: float = X["fill7"] if d7 else 1.0 - pow(0.8, days)
	# 1. staple food: the days to the next turn plus jars topped toward 3 (poor) / 20 / 50 days x (1 + 1.5 x the town's
	# fear), a fifth of the gap a day; rationing caps the jars at 4 days. Split by the race's taste and the prices.
	var jar: float = X["jar"][c]
	var sf: float = st["food"]
	var want_days := maxf(0.0, 7.0 - sf) + maxf(0.0, jar - maxf(0.0, sf - 7.0)) * fill
	if want_days > 0.0 and fr > 0.0:
		var meals := want_days * fr
		var sh: Dictionary = X["sh"]
		var avail: float = X["avail"]
		var fieldhand := false
		for k in f["jobs"]:
			var jb: Dictionary = e["biz"][int(k)]
			if jb["type"] == "farm" or jb["type"] == "estate":
				fieldhand = true
		var landed := acres(f) > 0
		# barge part 4 section 4 (farm harvest order): a farm family keeps its own food to the next harvest out of its
		# fields' cut (f.hv: its share of the harvest not yet eaten or sold); it moves from the barns into the larder, no
		# coin changes hands (the rest of the harvest is sold to the broker)
		meals -= float(keep_harvest(e, f, int(ceil(meals)), fr))
		for g in sh:
			if avail <= 0.0 or int(mkt.get(g, 0)) + int(barn.get(g, 0)) <= 0:
				continue
			var q := int(ceil(maxf(0.0, meals) * float(sh[g]) / avail))
			var cost := float(q) * float(price[g]) * mk
			if spent + cost > ess_cap:
				q = int(maxf(0.0, ess_cap - spent) / maxf(0.01, float(price[g]) * mk))
			if q <= 0:
				continue
			spent += float(q) * float(price[g]) * mk
			# the farms' own grain first: landholders keep theirs (the broker's 0.75 x P), field hands take part of their
			# pay in grain from the harvest at the market price (Douglas's default)
			if int(barn.get(g, 0)) > 0 and (landed or fieldhand):
				b.append([f, g, q, "food", fr, float(X["broker"]) if landed else 1.0])
				TownEcon.batch_barn = true
			else:
				b.append([f, g, q, "food", fr])
	if int(f["homes"]) <= 0:
		return   # homeless (Douglas): real food is the first call on what they earn; the rest is saved toward a roof
	# 2. fuel: stores 2 / 8 / 25 days (x1.5 in winter); the poor gather up to 40% of a day's fuel free (production)
	var wr := homes * float(e.get("wf", 0.5))
	var sw: float = st["wood"]
	if c == 0 and wr > 0.0:
		var gath := mini(int(EconomyRules.wood_available(e)), int(floor(float(H["gather"]) * wr * days)))
		if gath > 0:
			var hh: Dictionary = e["hh"]
			hh["wood"] = int(hh.get("wood", 0)) + gath
			TownEcon.led(e, "made", "wood", gath)
			sw += float(gath) / wr
			st["wood"] = sw
	var fs: float = X["fs"][c]
	if wr > 0.0:
		var wneed := (maxf(0.0, 7.0 - sw) + maxf(0.0, fs - maxf(0.0, sw - 7.0)) * fill) * wr
		var qw := int(ceil(wneed * float(X["wm_wood"])))
		var cw := float(qw) * float(price["wood"]) * mk
		if spent + cw > ess_cap:
			qw = int(maxf(0.0, ess_cap - spent) / maxf(0.01, float(price["wood"]) * mk))
		if qw > 0:
			spent += float(qw) * float(price["wood"]) * mk
			b.append([f, "wood", qw, "wood", wr])
	if TownEcon.prof_on: _rt = TownEcon._prof("r_staple_fuel", _rt)
	# 3. the rest (meat, produce, drink, clothes, tools, bedding, household goods; jewelry for the rich): want = q x
	# clamp((P / base)^-elasticity, 0.12, 1.6), rising steeply with class; budget <= min(savings - essentials,
	# 0.9 x income + 1.5% of savings (3% rich)) x (1 - 0.5 x coin shortage); luxuries cut to 30% when hungry
	var rent_w := float(X["rent"]) * float(f["homes"]) if f.has("landlord") or int(f.get("rent", 0)) > 0 else 0.0
	var budget := minf(purse - spent - rent_w * days / 7.0, (0.9 * inc_w - rent_w) * days / 7.0 + (float(X["rest7"][c]) if d7 else (1.0 - pow(1.0 - float(H["rest_save"][c]), days))) * purse) \
		* float(X["spend"])
	if stage > 0:
		budget *= float(X["hlux"])
	if budget <= 1.0:
		return
	var n0 := b.size()   # the rest's orders go straight on the batch, scaled to the budget after
	var tot := 0.0
	var rq: Array = X["rq"][c]   # [meat, fruit, beer, wine] q x want for this class
	var q := float(rq[0]) * ppl * days
	if q >= 1.0 and int(mkt.get("meat", 0)) > 0:
		b.append([f, "meat", int(q), "food", fr]); tot += float(int(q)) * float(price["meat"])
	q = float(rq[1]) * ppl * days
	if q >= 1.0 and int(mkt.get("fruit", 0)) > 0:
		b.append([f, "fruit", int(q), "food", fr]); tot += float(int(q)) * float(price["fruit"])
	var dr := ad * K_DRINK
	if dr > 0.0:
		var qb := int(float(rq[2]) * ad * days)
		var qv := int(float(rq[3]) * ad * days)
		if qb > 0 and int(mkt.get("beer", 0)) > 0:
			b.append([f, "beer", qb, "drink", dr]); tot += float(qb) * float(price["beer"])
		if qv > 0 and int(mkt.get("wine", 0)) > 0:
			b.append([f, "wine", qv, "drink", dr]); tot += float(qv) * float(price["wine"])
	var w: Dictionary = f["wear"]
	var cls_k: float = [1.0, 1.5, 3.0][c]   # worn goods replaced faster up the classes [ours]
	var wwm: Array = X["wwm"]
	for i in K_WEAR_G.size():
		var k: String = K_WEAR_G[i]
		var basis := ppl if k == "clothing" else (ad if k == "tools" else homes)
		var v := minf(float(w.get(k, 0.0)) + basis * days / float(K_WEAR_D[i]) * cls_k * float(wwm[i]), 3.0 * cls_k)
		w[k] = v
		if v >= 1.0:
			b.append([f, k, int(v), "wear", 0.0]); tot += float(int(v)) * float(price[k])
	if c == 2:
		var vj := minf(float(w.get("jewelry", 0.0)) + days / K_JEWEL_D, 2.0)
		w["jewelry"] = vj
		if vj >= 1.0:
			b.append([f, "jewelry", int(vj), "wear", 0.0]); tot += float(int(vj)) * float(price["jewelry"])
	tot += Legends.want_order(e, f, c, days, b)   # v0.014: a stone as stored wealth (middling and rich)
	tot *= mk
	if tot > budget:
		var sc := budget / maxf(0.01, tot)
		for i in range(n0, b.size()):
			var o: Array = b[i]
			o[2] = int(float(o[2]) * sc)
	if TownEcon.prof_on: _rt = TownEcon._prof("r_rest", _rt)
	# a new home when crowded
	if int(mkt.get("home", 0)) > 0 and ppl > (float(f.get("lodging_rooms", 0)) * TownHousing.PEOPLE_PER_ROOM if f.has("lodging") else homes * float(TownEcon.culture_of(e)["home"]["room"])) \
			and purse > float(e["price"]["home"]) * 1.2:
		b.append([f, "home", 1, "home", 0.0])



# ================================================================== hardship, recruits, records
## 0..1: how hard times are for this family (unpaid, hungry, idle, broke, in debt, ruined).
static func hardship(f: Dictionary) -> float:
	if f.get("gone", false) or f.get("estate", false):
		return 0.0
	var h := 0.0
	if int(f["unpaid"]) > 0: h += 0.3
	if int(f["hungry"]) > 0: h += 0.35
	if int(f["idle"]) > 0: h += 0.2
	if float(f["purse"]) < float(TownEcon.data()["family"]["min_purse"]): h += 0.2
	if float(f["debt"]) > 0.0: h += 0.15
	if f.get("ruined", false): h += 0.2
	if int(f["homes"]) <= 0:   # homeless (Shelter); destitute = homeless + broke + no land: the most desperate
		h += 0.3
		if Shelter.destitute(f): h += 0.3
		h += 0.2 * float(f.get("weak", 0.0))
	return minf(1.5, h)

## A person leaves the family to join the company (or an army: spec 2). Adults first, never the last one.
static func remove_member(e: Dictionary, f: Dictionary, sex: String = "") -> bool:
	if f.get("gone", false) or adults(f) <= 0:
		return false
	var s := sex if sex in ["m", "f"] and int(f.get(sex, 0)) > 0 else ("m" if int(f["m"]) > 0 else "f")
	f[s] = int(f[s]) - 1
	e["pop"] = int(e["pop"]) - 1
	e["adults"] = int(e["adults"]) - 1
	reassign(e, f)
	return true

## Short readable lines for the family record (town screen).
static func describe(town: Dictionary, e: Dictionary, f: Dictionary) -> Array:
	var D := TownEcon.data()
	var cul: Dictionary = D["cultures"][e["culture"]]
	var lines := []
	if f.get("estate", false):
		if f["land"].is_empty() and f["herd"].is_empty():
			lines.append("The town holds no land of its own right now. Land it confiscates or cannot sell is worked here by hired hands paid from the treasury.")
		else:
			lines.append("The town's own fields and herds (confiscated or unsold), worked by hired hands paid from the treasury.")
	else:
		var parts := []
		for p in [["m", "man", "men"], ["f", "woman", "women"], ["kids", "child", "children"], ["old", "elder", "elders"]]:
			var n := int(f[p[0]])
			if n > 0:
				parts.append("%d %s" % [n, p[1] if n == 1 else p[2]])
		lines.append("The %s %s: %s." % [f["name"], cul.get("kin", "family"), ", ".join(PackedStringArray(parts)) if not parts.is_empty() else "no one left"])
		var cond := float(f["cond"])
		var cw := "in good repair" if cond > 0.75 else ("worn" if cond > 0.45 else "falling apart")
		if f.has("lodging"):
			lines.append("Home: %d rented room%s, %s." % [int(f.get("lodging_rooms", TownHousing.room_need(f))), "" if int(f.get("lodging_rooms", 1)) == 1 else "s", cw])
		elif int(f["homes"]) <= 0:
			lines.append("Home: none. " + Shelter.state_line(e, f))
		else:
			lines.append("Home: %d %s%s, %s." % [int(f["homes"]), cul["home"]["type"], "" if int(f["homes"]) == 1 else "s", cw])
	lines.append(land_line(e, f))
	lines.append(herd_line(f))
	if f.get("estate", false):
		return lines + f["hist"]
	var debt := float(f["debt"])
	lines.append("Purse: %d coins." % int(f["purse"]))
	var dl := Loans.family_line(e, f)   # debt owed, rate, missed payments, what was sold
	if dl != "":
		lines.append(dl)
	lines.append(work_line(e, f))
	if f.has("inc"):
		lines.append("Income last week: %d coins (land, wages, casual work and own business)." % int(round(float(f["inc"]))))
	var s: Dictionary = f["store"]
	var r := daily_rates(e, f)
	lines.append("Stores: food for %d days (%d meals' worth), drink for %d days, firewood for %d days." % [int(s["food"]),
		int(float(s["food"]) * float(r["food"])), int(s["drink"]), int(s["wood"])])
	var BT: Dictionary = Barge.B()["treasury"]
	var c := int(f.get("cls", 0))
	var tax := float(BT["service"][c]) * float(e.get("svc_scale", 1.0)) * Barge.pl(e)
	lines.append("Class: %s. Service money: about %d coins a month%s." % [["poor", "middling", "rich"][c], int(round(tax)), "; in arrears" if debt > 0.5 else ""])
	if f.has("lodging"):
		lines.append("Room rent: %.1f coins a week." % TownHousing.rent_week(e, f))
	elif f.has("landlord"):
		lines.append("Rents its house: about %d coins a week." % int(round(Barge.rent_week(e) * float(f["homes"]))))
	lines.append("Hunger: %s." % Barge.STAGES[clampi(int(f["hungry"]), 0, 5)])
	var troubles := []
	if int(f["hungry"]) > 0: troubles.append("going hungry")
	if int(f["unpaid"]) > 0: troubles.append("wages unpaid for %d week%s" % [int(f["unpaid"]), "" if int(f["unpaid"]) == 1 else "s"])
	if f.get("ruined", false): troubles.append("ruined")
	if int(f["homes"]) <= 0:
		troubles.append("DESTITUTE" if Shelter.destitute(f) else "HOMELESS")
	if float(f.get("weak", 0.0)) >= 0.1:
		troubles.append("weakened by poorhouse broth")
	if not troubles.is_empty():
		lines.append("Hard times: " + ", ".join(PackedStringArray(troubles)) + ".")
	var story := Backstory.family_text(town, e, f)
	if story != "":
		lines.append("Story: " + story)
	elif f.has("lost"):
		lines.append("Story: the family " + lost_line(f) + ".")
	var rl := Backstory.recent_life(town, e, f)
	if not rl.is_empty():
		lines.append("Recent life:")
		for l in rl:
			lines.append("  " + String(l))
	return lines

## Current land and actual receipts are separate: selling the fields does not
## transfer the family's older stored harvest or its later sale proceeds.
static func land_line(e: Dictionary, f: Dictionary) -> String:
	var land := []
	for c in f["land"]:
		land.append("%s of %s" % [TownEcon.n_of(int(f["land"][c]), "acres"), TownEcon.variety_word(e, c)])
	var earned := ""
	if f.has("lpay") and (not land.is_empty() or absf(float(f["lpay"])) > 0.000001):
		earned = " Harvest and herd receipts: %d coins per week." % int(round(float(f["lpay"])))
	if land.is_empty():
		return "Land: none." + earned
	return "Land: %s (%s in all).%s" % [", ".join(PackedStringArray(land)), TownEcon.n_of(acres(f), "acres"), earned]

## "Herds: 19 cattle, 4 pigs." (listed apart from the land)
static func herd_line(f: Dictionary) -> String:
	var hl := []
	for a in f["herd"]:
		hl.append(TownEcon.n_of(int(f["herd"][a]), a))
	return "Herds: " + (", ".join(PackedStringArray(hl)) if not hl.is_empty() else "none") + "."

## "Work: Doran: cattle herder on the family herd; Ivo: tax collector's man at the tax office (21 gold a week);
## Edda: out of work." Every grown-up by name with the place he really holds (Persons.work) or his service.
static func work_line(e: Dictionary, f: Dictionary) -> String:
	if not f.has("pp"):
		return "Work: %d on the family land, %d at work, %d without work." % [int(f["hands"]), job_total(f), int(f["idle"])]
	var parts := []
	for m in Persons.household(e, f, float(e.get("day", 0))):
		if m["kind"] in ["boy", "girl", "elder"]:
			continue
		var wage := int(m["wage"])
		parts.append("%s: %s%s" % [m["first"], m["work"], (" (%d coins a week)" % wage) if wage >= 0 else ""])
	return "Work: " + ("; ".join(PackedStringArray(parts)) if not parts.is_empty() else "nobody of working age at home") + "."

## One household for the register list (filters and sorting on the Town screen): {fid, household, class, people,
## savings, income (last week), hunger (weeks hungry), condition (house 0-1, -1 homeless), homeless, debt}.
## class from what the family really holds: "the head's house", "landholders", "business owners", "wage earners",
## "labourers" (casual work), "destitute" (homeless with nothing), "poor" (no work at all).
static func summary(e: Dictionary, f: Dictionary) -> Dictionary:
	var cls := "poor"
	if int(e.get("head", {}).get("fam", -1)) == int(f["id"]):
		cls = "the head's house"
	elif int(f["homes"]) <= 0 and Shelter.destitute(f):
		cls = "destitute"
	elif acres(f) > 0 or heads(f) > 0:
		cls = "landholders"
	elif not (f["owns"] as Array).is_empty():
		cls = "business owners"
	elif job_total(f) > 0:
		cls = "wage earners"
	elif not f.get("cj", {}).is_empty():
		cls = "labourers"
	return {"fid": int(f["id"]), "household": String(f["name"]), "class": cls, "people": people(f), "savings": int(f["purse"]),
		"income": int(round(float(f.get("inc", 0.0)))), "hunger": int(f["hungry"]), "condition": float(f["cond"]) if int(f["homes"]) > 0 else -1.0,
		"homeless": int(f["homes"]) <= 0, "debt": int(round(float(f["debt"])))}

## One line from the family's real state for a recruit's backstory.
static func story_line(e: Dictionary, f: Dictionary, first: String, he: String) -> String:
	var biz: Array = e["biz"]
	var head_title: String = e.get("head", {}).get("title", "reeve")
	if int(f["unpaid"]) > 0:
		for k in f["jobs"]:
			var b: Dictionary = biz[int(k)]
			if float(b["till"]) < float(b["wage"]) * 7.0:
				var w := int(f["unpaid"])
				return "The %s hasn't paid in %s; %s family is %s." % [Businesses.title(e, b), _weeks(w), he,
					"hungry" if int(f["hungry"]) > 0 else "counting every coin"]
	if f.get("ruined", false) or (float(f["debt"]) > 0.0 and acres(f) == 0):
		if f.has("lost"):
			return "The family %s; %s has nothing left to farm." % [lost_line(f), first]
		return "The family lost its land to the %s; %s has nothing left to farm." % [head_title, first]
	if int(f["hungry"]) > 0:
		return "There is not enough food in the %s house this season; %s eats last." % [f["name"], first]
	if int(f["idle"]) > 0:
		return "There is no work in town for %s, and the %s purse is nearly empty." % [first, f["name"]]
	if float(f["debt"]) > 0.0:
		return "The %s family owes the %s %d coins." % [f["name"], head_title, int(f["debt"])]
	if people(f) > int(f["homes"]) * 6:
		return "Nine to a room in the %s house; %s wants space and coin." % [f["name"], first]
	return ""

## "lost 12 acres of barley to the reeve in the spring of year 2"
static func lost_line(f: Dictionary) -> String:
	var l: Dictionary = f.get("lost", {})
	if l.is_empty():
		return ""
	return "lost %s to the %s in the %s of year %d" % [l["what"], l["to"], l["season"], int(l["year"])]

static func _weeks(w: int) -> String:
	return ["a week", "two weeks", "three weeks", "four weeks", "five weeks"][clampi(w - 1, 0, 4)] if w < 6 else "%d weeks" % w
