extends RefCounted
## Native remittance regression: authentic extinct recipients and per-day
## affordability with an unresolved legacy home reference. No wage tuning,
## fabricated units, extinct-family fabrication, or coin compensation.
var checks: int = 0
var fails: int = 0
const EPS: float = 0.001
var authentic_stats: Dictionary = {}
var unresolved_stats: Dictionary = {}

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL: ", message)

func _close(a: float, b: float) -> bool:
	return absf(a - b) < EPS

func _coin_snapshot() -> String:
	return JSON.stringify(Game.world.get("coin", {}))

func _group_target(groups: Array[Dictionary], target: Array, amount: float) -> void:
	var holder: Dictionary = target[0]
	var key: String = String(target[1])
	for group in groups:
		if is_same(group["holder"], holder) and String(group["key"]) == key:
			group["expected"] = float(group["expected"]) + amount
			return
	groups.append({"holder": holder, "key": key,
		"before": float(holder.get(key, 0.0)), "expected": amount})

func _authentic_recipients() -> void:
	var source_path: String = OS.get_environment("V046_SAVE")
	check(not source_path.is_empty() and FileAccess.file_exists(source_path), "V046_SAVE names an authentic readable campaign")
	if source_path.is_empty() or not FileAccess.file_exists(source_path):
		return
	# load_game reads this path; this test never calls any save function.
	Game.wait_save()
	var previous_path: String = Game.SAVE_PATH
	Game.SAVE_PATH = source_path
	var loaded: bool = Game.load_game()
	Game.SAVE_PATH = previous_path
	check(loaded, "native campaign loader reads authentic checkpoint")
	if not loaded:
		return
	var groups: Array[Dictionary] = []
	var extinct_rows: Array[Dictionary] = []
	var recipients: Array[Unit] = []
	var expected_paid: int = 0
	var ordinary_count: int = 0
	for candidate in Game.company:
		var u: Unit = candidate as Unit
		if u == null or u.dead or u.wage <= 0:
			continue
		var town: Dictionary = Game.world.get("towns", {}).get(u.home_town, {})
		var f: Dictionary = People.fam_of(town, u.family)
		check(TownEcon.has_econ(town) and not f.is_empty(), "authentic living wage recipient has an actual household")
		if not TownEcon.has_econ(town) or f.is_empty():
			continue
		var target: Array = WageClaims._recipient(town["econ"], f)
		check(not target.is_empty(), "authentic household has an established-policy wage target")
		if target.is_empty():
			continue
		recipients.append(u)
		expected_paid += u.wage
		_group_target(groups, target, float(u.wage))
		if f.get("gone", false) and f.get("extinct", false):
			var p: Array = Persons.by_uid(f, u.uid)
			check(not p.is_empty() and String(p[4]) == "company" and ServiceIdentity.unit_person(town["econ"], f, p, u), "extinct household retains this exact living company identity")
			extinct_rows.append({"family": f, "before": float(f.get("purse", 0.0))})
		else:
			ordinary_count += 1
			check(not f.get("gone", false) and String(target[1]) == "purse" and is_same(target[0], f), "ordinary recipient resolves to its own actual family purse")
	check(not extinct_rows.is_empty(), "authentic checkpoint contains property-selected extinct wage recipients")
	check(ordinary_count > 0, "authentic checkpoint contains ordinary live household recipients")
	check(recipients.size() == Game.company.filter(func(u): return not u.dead and u.wage > 0).size(), "every living authentic wage recipient is accounted for")
	check(Game.gold >= expected_paid, "authentic company can fund this complete native payroll")
	if Game.gold < expected_paid or recipients.is_empty():
		return
	var before_gold: int = Game.gold
	var before_holdings: float = Barge.holdings(Game)
	var before_coin: String = _coin_snapshot()
	var before_day: float = Game.day
	Game.pay_wages(1)
	check(before_gold - Game.gold == expected_paid, "authentic player debit equals all resolved accepted wages")
	var credited: float = 0.0
	for group in groups:
		var holder: Dictionary = group["holder"]
		var delta: float = float(holder.get(String(group["key"]), 0.0)) - float(group["before"])
		credited += delta
		check(_close(delta, float(group["expected"])), "shared native target receives its exact aggregated company wages")
	check(_close(credited, float(before_gold - Game.gold)), "authentic accepted recipient credits equal the actual player debit")
	for row in extinct_rows:
		var f: Dictionary = row["family"]
		check(_close(float(f.get("purse", 0.0)), float(row["before"])), "extinct purse remains untouched by remittance")
	for u in recipients:
		check(u.unpaid_days == 0 and _close(u.last_pay, float(u.wage)), "authentic accepted wage updates native paid flags accurately")
	check(_close(Barge.holdings(Game), before_holdings), "authentic remittance conserves every global coin holding")
	check(_coin_snapshot() == before_coin, "authentic remittance does not change global casting or loss ledger")
	check(Game.day == before_day, "native payroll does not rewrite the authentic world clock")
	authentic_stats = {"recipients": recipients.size(), "extinct_recipients": extinct_rows.size(), "ordinary_recipients": ordinary_count, "expected_paid": expected_paid, "credited": credited, "holdings_delta": Barge.holdings(Game) - before_holdings}
	print("COMPANY_WAGES_AUTHENTIC ", JSON.stringify(authentic_stats))

func _unresolved_roster_order() -> void:
	var previous_size: String = WorldGen.gen_size
	WorldGen.gen_size = "normal"
	Game.new_game(4646046)
	WorldGen.gen_size = previous_size
	var first: Unit = null
	var second: Unit = null
	for candidate in Game.company:
		var u: Unit = candidate as Unit
		if u == null or u.dead or u.is_officer() or u.wage <= 0:
			continue
		var town: Dictionary = Game.world.get("towns", {}).get(u.home_town, {})
		var f: Dictionary = People.fam_of(town, u.family)
		if not TownEcon.has_econ(town) or f.is_empty() or f.get("gone", false):
			continue
		if first == null:
			first = u
		elif u.wage == first.wage:
			second = u
			break
	check(first != null and second != null, "fresh native company supplies two real nonofficers with identical positive wages")
	if first == null or second == null:
		return
	var treasury: Dictionary = {}
	for candidate in Game.world.get("towns", {}).values():
		var town: Dictionary = candidate
		if TownEcon.has_econ(town) and town["econ"].has("treasury"):
			treasury = town["econ"]
			break
	check(not treasury.is_empty(), "fresh generated world has an actual treasury for conserving the budget transfer")
	if treasury.is_empty():
		return
	var budget: int = 2 * second.wage
	check(Game.gold >= budget, "fresh company has existing coins sufficient for two valid wages")
	if Game.gold < budget:
		return
	var transfer_holdings: float = Barge.holdings(Game)
	var before_coin: String = _coin_snapshot()
	var excess: int = Game.gold - budget
	treasury["treasury"] = float(treasury["treasury"]) + float(excess)
	Game.gold -= excess
	check(_close(Barge.holdings(Game), transfer_holdings), "budgeting transfers excess company coins to a real treasury without creation")
	check(_coin_snapshot() == before_coin, "budget transfer does not rewrite global coin ledger")
	var original_roster: Array = Game.company.duplicate()
	var original_home: String = first.home_town
	var original_family: int = first.family
	var unresolved_home: String = "__unresolved_company_home__"
	while Game.world.get("towns", {}).has(unresolved_home):
		unresolved_home += "_"
	# A runtime copy of a legacy unresolved home reference; the household itself
	# remains real and live, with its original purse and person history untouched.
	first.home_town = unresolved_home
	Game.company = [first, second]
	var valid_town: Dictionary = Game.world["towns"][second.home_town]
	var valid_family: Dictionary = People.fam_of(valid_town, second.family)
	var unresolved_family: Dictionary = People.fam_of(Game.world["towns"][original_home], original_family)
	var valid_purse: float = float(valid_family["purse"])
	var unresolved_purse: float = float(unresolved_family["purse"])
	var first_unpaid: int = first.unpaid_days
	var before_holdings: float = Barge.holdings(Game)
	var before_day: float = Game.day
	Game.pay_wages(2)
	check(Game.gold == 0, "two valid daily wages consume exactly the conserved company budget")
	check(_close(float(valid_family["purse"]) - valid_purse, float(budget)), "rejected first wage leaves funding for the second real member on both days")
	check(_close(float(unresolved_family["purse"]), unresolved_purse), "unknown home reference does not guess or credit its former household")
	check(first.unpaid_days == first_unpaid + 2 and _close(first.last_pay, 0.0), "unresolved recipient accrues exactly two unpaid days with zero last payment")
	check(second.unpaid_days == 0 and _close(second.last_pay, float(second.wage)), "valid recipient is fully paid on both days with accurate native flags")
	check(_close(Barge.holdings(Game), before_holdings), "unresolved reference and repeated daily payroll conserve all holdings")
	check(_coin_snapshot() == before_coin, "unresolved and accepted wages leave the global coin ledger unchanged")
	check(Game.day == before_day, "multi-day payroll requires no world-clock reset or rewrite")
	unresolved_stats = {"days": 2, "native_wage": second.wage, "budget": budget, "valid_received": float(valid_family["purse"]) - valid_purse, "unresolved_unpaid_days": first.unpaid_days - first_unpaid, "valid_unpaid_days": second.unpaid_days, "holdings_delta": Barge.holdings(Game) - before_holdings}
	print("COMPANY_WAGES_UNRESOLVED ", JSON.stringify(unresolved_stats))
	first.home_town = original_home
	first.family = original_family
	Game.company = original_roster
	Game.invalidate_deploy()

func run(_tree: SceneTree) -> int:
	Game.main = null
	_authentic_recipients()
	_unresolved_roster_order()
	print("COMPANY_WAGES checks=", checks, " failures=", fails)
	print("COMPANY_WAGES_AGGREGATE ", JSON.stringify({"checks": checks, "failures": fails, "authentic": authentic_stats, "unresolved": unresolved_stats, "native_payroll": true, "wage_tuning": false, "compensation_coins": false}))
	return fails
