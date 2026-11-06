# TASK086 source recovery

Status: SOURCE DELIVERED; compilation, imports, runtime tests and timing **UNRUN**.
Changes were made only in this writable Library copy with file patches. No git,
engines, helpers, downloads, UI, native worktrees, UIDs, version or roadmap changes.

## Finding and corrections

The seeded candidate connects all eight domestic species to the native herd
records. Oxen remain the ninth data kind, a work group of cattle. Native opening
culture weights, y/g/o age groups, female shares, town sire coverage, life/disease
and market ledgers are retained. Horse foal/mount bodies and their transfer hooks
are unchanged; dogs never become battle units.

The draft was incomplete at several conservation/custody boundaries:

- `game/campaign/domestic_animals.gd`: `feed_dogs` skips empty records and stamps
  the actual owning account on each paid/scrap feed receipt. `raid_share` checks
  that account, current owning household, living adult receipt, hunger, illness
  and the seven-day feed window. `dog_target` permits zero demand; `buy_dogs`
  includes households whose grazing stock belongs to their business.
- `game/campaign/herds.gd`: `change` retires adult guard eligibility when a dog
  leaves by death or transfer; `_life` also retires eligibility on ageing out.
  New/replacement adults cannot borrow those meals. `herd_for` finds a home
  record instead of merging new arrivals into a caravan's away record.
- `game/campaign/herd_raids.gd`: `step`/`take` reject a herd assigned away after
  planning. `take` derives carcasses from the actual `change` debit and updates
  predator feeding only when an animal was taken. Dog deterrence already enters
  this real head-loss path in the seeded draft, before any carcass is produced.
- `game/campaign/domestic_animals.gd`: `prepare_pack` ignores exhausted offers,
  transfers animals before their hay, and invalidates care caches; `pack_herd`
  validates donkey species, estate ownership and matching custody. `pack_tick`
  may suppress cargo trimming when `finish_pack` is settling already lost or
  plundered cargo, preventing a second loss booking after native caravan settlement.
- `game/campaign/herds_market.gd`: `_take_offer`, `_pot_buys`, `butcher_day`,
  `_products` and `on_sack` reject away records. This closes stale-offer sale,
  slaughter and home-output paths in addition to the draft's existing skips.

Existing seeded integration in `caravans.gd`, `families.gd`, `herds_views.gd`
and `economy.json` is retained. Poultry moult/slaughter feathers feed the existing
counted feather good; all six native fletcher recipes require that good.
The legacy farm-feather stand-in returns immediately when herd records exist.
Donkey draught feeds the existing crop-labour calculation; native caravan sail,
return purchasing, movement, homecoming and loss call the pack paths.

## Authored regressions — all UNRUN

`game/tests/test_no_herd_dogs.gd` now forwards to the new
`game/tests/test_domestic_animals_v086.gd` so existing runner lists exercise the
replacement contract. The new test generates Normal once, advances one history
day, then uses detached controlled economies and native methods. No battles or
long world/season waits, and no save-file cleanup. Intended budget <60 seconds;
180 seconds remains the hard cap; neither duration is measured here.

Coverage: actual predator/thief head losses and corresponding carcass/carry/use/
spoil debits; fed versus absent/unfed/hungry/unrelated-owner/dead/young/sick/expired
dogs; dead-dog replacement and buyer feeding; owned-business protection; no free
predator feeding after total deterrence; food, scraps, coin, retained meal kg and
human reserve conservation; starvation; no dog carcass or butcher/home slaughter;
opening culture mix and generated herd ledger closure; native age/female-share/
sire-coverage/season breeding gates; counted poultry feathers and no stand-in
duplication; every fletcher recipe's feather input; actual draught labour;
pack purchase, hay, capacity, stale offers, daily idempotence, excess cargo,
loss and healthy return; two JSON/native herd restores of pack custody and two
full `Game.load_game` calls preserving herd identities, feed receipts and coin.

Controller-only Test Bridge commands (from the candidate root; NOT executed):

```text
godot --headless --path game res://tests/runner.tscn -- --test=res://tests/test_domestic_animals_v086.gd --watchdog=180
godot --headless --path game res://tests/runner.tscn -- --tests=res://tests/test_no_herd_dogs.gd,res://tests/test_herd_totals_v043.gd --watchdog=180
```

The second command independently exercises the retained entry point and existing
cache contract; it need not be repeated if the controller's chosen block covers
both. The old `test_herds.gd` year-long simulation was not expanded or run.

## Limits for acceptance

The corrected source has the requested native paths, but no runtime pass is
claimed. Breeding retains the existing aggregate `fem`/`fpm` sex-share model,
including the later horse lifecycle; it does not introduce individually sexed
animal identities. The feather check verifies actual flock output plus native
recipe requirements; a complete fletcher production turn is not executed by this
new test. Pack capacity extends returning goods; outgoing wagon loads retain
their existing capacity. The controller must compile/test the returned source,
confirm runtime conservation and timing, and own integration/delivery.

Exact files changed in this recovery:

1. `v086/game/campaign/domestic_animals.gd`
2. `v086/game/campaign/herds.gd`
3. `v086/game/campaign/herds_market.gd`
4. `v086/game/campaign/herd_raids.gd`
5. `v086/game/tests/test_no_herd_dogs.gd`
6. `v086/game/tests/test_domestic_animals_v086.gd` (new)
7. `v086/REPORT_v086.md` (new)
