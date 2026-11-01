class_name DragonRiders
extends RefCounted
## v0.081: a bonded rider sits on the dragon as a live native target (the v0.023 gap). MountedCombat in reverse:
## the dragon acts and moves, the rider is a passive body at the dragon's cell that enemies pick and strike through
## the unchanged BattleSim/BattleDamage/BattleMorale. The rider occupies no tile and never decides; he does not keep
## a side in the fight (end checks skip seated and fallen riders, like horse bodies).
## The rider leaves the field ("waiting") when he is downed, routed or grabbed, or when his dragon goes down, flees
## or routs: he is no longer a target. His live wounds stay on his body; the existing post-battle rules
## (DragonCombat._rider_result: fall roll when the dragon went down, death and wound bookkeeping) run afterwards.
## Opt-in: setup(sim, riders) with riders = {str(dragon unit uid): {"unit": Unit, "detached": bool}} from
## DragonCombat.battle_riders; a sim without it is unchanged. A deployed rider already on the field mounts; any
## other rider is a battle body for this fight ("detached", no loot, prisoners or casualty rows of its own).

static func setup(sim, riders: Dictionary) -> void:
	if riders.is_empty(): return
	for dragon: Fighter in sim.fighters.duplicate():
		if not dragon.dragon or dragon.seated_rider >= 0 or not dragon.active() or dragon.prone: continue
		var entry: Dictionary = riders.get(str(dragon.unit.uid), {})
		var u = entry.get("unit")
		if not u is Unit or u.dead: continue
		var rider: Fighter = null
		for f: Fighter in sim.fighters:
			if f.unit == u:
				rider = f
				break
		if rider != null:
			# A rider who is already a fighter (deployed with the army) climbs into the saddle instead of walking.
			if rider.side != dragon.side or rider.mount_idx >= 0 or rider.mount_rider_idx >= 0 or rider.seat_dragon >= 0: continue
			if not rider.active() or rider.prone: continue
			if not rider.waiting and rider.standing() and sim.occ[sim._ci(rider.cell)] == rider.idx:
				sim.occ[sim._ci(rider.cell)] = -1
		else:
			rider = Fighter.new()
			rider.idx = sim.fighters.size()
			rider.unit = u
			rider.side = dragon.side
			rider.cell = dragon.cell
			rider.prev_cell = dragon.prev_cell
			rider.facing = dragon.facing
			rider.seat_body = bool(entry.get("detached", false))
			rider.seat_joined = true
			Food.apply_battle(u)
			sim._init_fighter(rider)
			sim._food_refresh(rider)
			if not rider.standing() or rider.prone:
				Food.clear_battle(u)
				continue
			sim.fighters.append(rider)
		rider.seat_dragon = dragon.idx
		rider.seated_on = dragon.idx
		rider.seat_damage0 = DragonCombat.rider_damage(u)
		rider.hold = true
		rider.tiebreak = dragon.tiebreak
		dragon.seated_rider = rider.idx
		dragon.had_rider = true
		follow(sim, dragon)

## The rider is where his dragon is (no tile of his own).
static func follow(sim, dragon: Fighter) -> void:
	if dragon.seated_rider < 0: return
	var rider: Fighter = sim.fighters[dragon.seated_rider]
	rider.cell = dragon.cell
	rider.prev_cell = dragon.prev_cell
	rider.facing = dragon.facing
	rider.waiting = dragon.waiting
	rider.last_move_tick = dragon.last_move_tick
	sim._tcells_ok = false

## Once a tick (with MountedCombat.sync): follow, or take the rider out of the fight.
static func sync(sim) -> void:
	for dragon: Fighter in sim.fighters:
		if dragon.seated_rider < 0: continue
		var rider: Fighter = sim.fighters[dragon.seated_rider]
		var rider_down: bool = rider.unit.dead or rider.prone or not rider.active() or rider.routed or rider.grabbed_by >= 0
		var mount_down: bool = dragon.unit.dead or dragon.prone or not dragon.active() or dragon.routed or dragon.state == "fled"
		if rider_down or mount_down:
			unseat(sim, dragon, rider, "the rider fell" if rider_down else "the mount went down")
		else:
			follow(sim, dragon)

static func unseat(sim, dragon: Fighter, rider: Fighter, why: String) -> void:
	dragon.seated_rider = -1
	rider.seat_dragon = -1
	rider.unseated = why
	if rider.grabbed_by >= 0: sim._release_grab(sim.fighters[rider.grabbed_by])   # nobody keeps hold of a rider who is gone
	sim._release_grab(rider)
	rider.waiting = true   # off the field: no longer a target; post-battle rules settle the fall
	rider.target = -1
	sim._tcells_ok = false

## After the battle: what happened to each seated rider in the fight itself (for DragonCombat._rider_result).
## {dragon_uid: {state, dead, detached, unseated, unit, damage (live tissue/blood loss this battle)}}
static func report(sim) -> Dictionary:
	var out := {}
	for rider: Fighter in sim.fighters:
		if rider.seated_on < 0: continue
		var dragon: Fighter = sim.fighters[rider.seated_on]
		out[str(dragon.unit.dragon_uid)] = {"idx": rider.idx, "state": rider.state, "dead": rider.unit.dead,
			"detached": rider.seat_body, "joined": rider.seat_joined, "unseated": rider.unseated, "unit": rider.unit,
			"damage": maxf(0.0, DragonCombat.rider_damage(rider.unit) - rider.seat_damage0)}
	return out
