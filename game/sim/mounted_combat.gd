class_name MountedCombat
extends RefCounted
## Coupling only: both bodies use BattleSim/BattleDamage/BattleMorale unchanged.
## Horses are passive native targets, do not occupy a second tile or win alone.
static func setup(sim) -> void:
	for rider: Fighter in sim.fighters.duplicate():
		if not Horses.can_field(rider.unit) or not rider.active() or rider.prone: continue
		var horse := Fighter.new()
		horse.idx = sim.fighters.size()
		horse.unit = rider.unit.horse
		horse.side = rider.side
		horse.cell = Vector2i.ZERO if rider.waiting else rider.cell
		horse.prev_cell = rider.prev_cell
		horse.facing = rider.facing
		horse.mount_rider_idx = rider.idx
		horse.mount_attached = true
		Food.apply_battle(horse.unit)
		sim._init_fighter(horse)
		sim._food_refresh(horse)
		horse.tiebreak = rider.tiebreak
		if not horse.standing() or horse.prone:
			Food.clear_battle(horse.unit)
			continue
		rider.mount_idx = horse.idx
		sim.fighters.append(horse)
		follow(sim, rider)

static func follow(sim, rider: Fighter) -> void:
	if rider.mount_idx < 0: return
	var horse: Fighter = sim.fighters[rider.mount_idx]
	if not horse.mount_attached or not horse.active() or horse.prone: return
	horse.cell = rider.cell
	horse.prev_cell = rider.prev_cell
	horse.facing = rider.facing
	horse.waiting = rider.waiting
	horse.last_move_tick = rider.last_move_tick
	# Presentation reads the carrier's action, not a second locomotion clock.
	horse.action_total = rider.action_total
	horse.action_ticks = rider.action_ticks
	sim._tcells_ok = false

static func sync(sim) -> void:
	for horse: Fighter in sim.fighters:
		if horse.mount_rider_idx < 0 or not horse.mount_attached: continue
		var rider: Fighter = sim.fighters[horse.mount_rider_idx]
		if rider.state == "fled" and horse.active() and not horse.prone:
			follow(sim, rider)
			sim._flee_step(horse) # the attached carrier exits at the same edge
		if horse.unit.dead or horse.prone or not horse.active() or horse.routed \
				or horse.grabbed_by >= 0 or not rider.active() or rider.prone:
			horse.mount_attached = false
			rider.mount_idx = -1
			rider.tempo_tick = -1000
			if horse.standing() and sim.occ[sim._ci(horse.cell)] == -1:
				sim.occ[sim._ci(horse.cell)] = horse.idx
			sim._tcells_ok = false
			if rider.active() and not rider.prone and (horse.unit.dead or horse.prone or not horse.active()):
				sim._fall(rider, "pain", Formulas.KNOCKDOWN_TICKS)
			if horse.unit.dead: Horses.casualty(rider.unit, horse.unit)
		else:
			follow(sim, rider)

static func mover(sim, rider: Fighter) -> Fighter:
	if rider.mount_idx >= 0:
		var horse: Fighter = sim.fighters[rider.mount_idx]
		if horse.mount_attached and horse.active() and not horse.prone: return horse
	return rider
