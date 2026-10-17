extends RefCounted
var checks := 0
var fails := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL ", message)

func fixture(treasury: float) -> Dictionary:
	return {"treasury": treasury, "mkt": 0, "biz": [{"till": 0.0}], "idle_n": 4,
		"cjused": {"street_sweeper": 2.0, "rat_catcher": 1.0}, "sanitation": {"paid_days": {}}}

func run(_tree: SceneTree) -> int:
	# Three real adult places released after partial wages; earned attendance remains fractional.
	var e := fixture(300.0)
	var f := {"purse": 23.0, "idle": 1, "cj": {"street_sweeper": 2, "rat_catcher": 1},
		"cjearned": {"street_sweeper": [14.0, 1400.0], "rat_catcher": [7.0, 315.0]}}
	var coins := float(e["treasury"]) + float(f["purse"])
	Shelter.pay_casual(e, f, 7)
	check(int(f["idle"]) == 4 and int(e["idle_n"]) == 7, "all three released adult jobs become idle in family and town totals")
	check(not f.has("cj") and float(e["cjused"]["street_sweeper"]) == 0 and float(e["cjused"]["rat_catcher"]) == 0, "released adult places become actual vacancies")
	check(absf(TownSanitation.paid_days(e, "street_sweeper") - 3.0) < 0.00001, "partial payment supports exactly three actual attended service days")
	check(TownSanitation.paid_days(e, "rat_catcher") == 0, "unpaid existing rat catcher creates no paid service")
	check(float(e["treasury"]) + float(f["purse"]) == coins, "partial wages transfer existing coins")
	var purse := float(f["purse"])
	Shelter.pay_casual(e, f, 7)
	check(float(f["purse"]) == purse and TownSanitation.paid_days(e, "street_sweeper") == 3, "settled attendance cannot be paid or consumed twice")
	check(int(f["idle"]) == 4 and int(e["idle_n"]) == 7, "empty second settlement cannot create idle adults")
	# Earned child cleanup can remain due after reassignment; short pay releases no adult places.
	e = fixture(0.0); e["cjused"] = {"street_sweeper": 0.2}
	f = {"purse": 23.0, "idle": 1, "child_cj": {"9": "street_sweeper"}, "cjearned": {"street_sweeper": [1.4, 140.0]}}
	Shelter.pay_casual(e, f, 7)
	check(int(f["idle"]) == 1 and int(e["idle_n"]) == 4, "unpaid child-only attendance never becomes idle adults")
	check(float(e["cjused"]["street_sweeper"]) == 0.2 and f["child_cj"] == {"9": "street_sweeper"}, "adult release leaves registered short child shifts for weekly reassessment")
	check(f["cjearned"].is_empty() and TownSanitation.paid_days(e, "street_sweeper") == 0, "unpaid child work adds no phantom funded removals")
	# Full payment retains jobs and exact attended shifts, rather than a nominal seven-day estimate.
	e = fixture(1000.0); e["cjused"] = {"street_sweeper": 1.0}
	f = {"purse": 23.0, "idle": 1, "cj": {"street_sweeper": 1}, "cjearned": {"street_sweeper": [2.4, 240.0]}}
	Shelter.pay_casual(e, f, 7)
	check(f["cj"] == {"street_sweeper": 1} and int(f["idle"]) == 1 and int(e["idle_n"]) == 4, "fully paid attended work keeps adult assignment and idle totals")
	check(absf(TownSanitation.paid_days(e, "street_sweeper") - 2.4) < 0.00001 and float(f["purse"]) == 263.0, "full pay uses actual fractional attendance")
	print("CASUAL SHORT PAY checks=%d failures=%d" % [checks, fails])
	return fails
