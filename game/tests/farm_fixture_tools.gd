extends RefCounted

## Controlled fixtures move existing productive cereal plots and actual animals.
## They never replace mirrors while leaving the physical books unchanged.
func grain(e: Dictionary, owner: Dictionary, n: int) -> bool:
	var P: Dictionary = e["plots"]
	CropRotation.ensure(e, P, float(e.get("day", 0)))
	for source in e["fams"]:
		if source == owner or int(source["land"].get("grain", 0)) < n: continue
		var plots := []
		for i in Plots.count(P):
			if int(P["own"][i]) == int(source["id"]) and int(P["use"][i]) in Plots.LAND_USES and String(P["crops"][int(P["sub"][i])]) == "grain": plots.append(i)
		# Set the controlled cereal phase on these existing physical fields.
		# This fixture changes its crop input, never acreage, people or stored crops.
		for i in plots:
			P["rotation_phase"][i] = posmod(-Calendar.year(float(e.get("day", 0))), 4)
		if not plots.is_empty():
			P["crop_count"] = -1
			CropRotation.ensure(e, P, float(e.get("day", 0)))
			Families.move_land(e, source, owner, "grain", n)
			# A real partial transfer may split a plot. Control the transferred
			# crop input on that new plot too, using its actual owner and acreage.
			for i in Plots.count(P):
				if int(P["own"][i]) == int(owner["id"]) and int(P["use"][i]) in Plots.LAND_USES and String(P["crops"][int(P["sub"][i])]) == "grain":
					P["rotation_phase"][i] = posmod(-Calendar.year(float(e.get("day", 0))), 4)
			P["crop_count"] = -1
			Families.refresh_worked(e, owner)
			return true
	return false

func animals(e: Dictionary, owner: Dictionary, k: String, n: int) -> bool:
	var remaining := n
	for source in e["fams"]:
		if source == owner: continue
		var count := mini(remaining, int(source["herd"].get(k, 0)))
		if count > 0: Families.move_herd(e, source, owner, k, count); remaining -= count
		if remaining <= 0: return true
	return false

func base_need(e: Dictionary, owner: Dictionary) -> float:
	var active := 0.0; var fallow := 0.0
	var P: Dictionary = e["plots"]
	CropRotation.ensure(e, P, float(e.get("day", 0)))
	for i in Plots.count(P):
		if int(P["own"][i]) != int(owner["id"]) or not int(P["use"][i]) in Plots.LAND_USES: continue
		if String(P["variety"][i]) == "fallow": fallow += float(P["ac"][i])
		else: active += float(P["ac"][i])
	var drafted := minf(active, float(maxi(0, int(owner.get("ox", 0)))) * 8.0)
	var cost := drafted / 8.0 + (active - drafted) / 4.0 + fallow / 8.0 * 0.25
	for h in Herds.of_family(e, int(owner["id"])):
		cost += (float(h["g"]) + float(h["o"]) + 0.5 * float(h["y"])) / float(Herds.kind(String(h["k"]))["per_hand"])
	return cost
