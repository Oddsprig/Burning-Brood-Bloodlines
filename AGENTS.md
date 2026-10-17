# Burning Brood: Bloodlines

Read `HANDOFF.txt` for current locations/status, then `START_HERE.txt`,
`docs/DEV_NOTES.txt` and `docs/ROADMAP.txt`.
Read the original handoff or inherited specifications only as needed.

- This is a separate game based on Copper Oath v0.046. Change this project only.
- User authorized v0.002: succession, feudal ownership/loyalty/defection, common-folk
  majority with 10–20 tracked families per town, private wealth tax to local rulers,
  100–200-person armies, bronze recycling and temporary creature suspension.
- User authorized the next version after v0.002 Desktop delivery. v0.003 adds
  actual ruler budgets/tax/funding/defence orders and corrects cohort economy
  integration. Follow the active roadmap; court/marriage expansion comes later.
- v0.003 is delivered. User authorized v0.004 to import current Copper Oath
  character and weapon models; redesign comes later. Import only native art and
  necessary display adaptations. Keep campaign rules and combat stats unchanged.
- v0.004 and v0.005 are delivered. v0.005 added individual dragon/egg identities and a
  small roster. Dragons are original wyverns: two hind legs, wings as forelimbs,
  no separate front legs. Vary build/size/colour; eggs use gem colour names,
  including Ruby Egg, Sapphire Egg and Black Diamond Egg. Living gem types such
  as Sapphire Dragon are separate from personal names. Gem type sets tooth/claw
  hardness; body size, strength, bite force and tooth/claw geometry separately
  affect attack physics. Pure profiles exist; bind native bodies in v0.022.
  Care/riders/battles
  stay in later scoped milestones. Older no-wing dragon proposals are superseded.
- Delivered v0.006: source-matched animal sprites, head/jaw animation,
  bloody wound/mangle displays and actual unit saddle-fit preview. Generated
  portraits are allowed in-game as compact files; full portraits and unused
  whole-body drafts belong in Desktop/ASSET/Burning_Brood/. User rejected the
  flat capsule prototype and a single whole-body image as a fighting model.
  Latest steering supersedes the independently fitted part atlas: label cuts
  from one coherent source per form, preserving original pixel size/position.
  Body retains its original wings, legs and tail; head/upper neck and jaw are
  the only moving image cuts. Rest reconstruction must match source pixels.
  Mangled wings/limbs stay attached and get broad localized blood. Only head
  separation removes head/jaw at the neck; tiny teeth/claw tips may fly off.
  No claim of articulated leg gait. Scales/skin
  are living tissue; horns, claws and teeth use their dragon's gem colours and
  gem-like finish. Sapphire horns are sapphire blue, never preserved brown/gray
  keratin. Preserve only the original eyes; shape material masks follow anatomy,
  with no rectangular colour cutoff across the head. Rider holds the
  saddle mount handles; no rope or bridle to the dragon's head/neck.
- Delivered v0.007: user requested released Copper Oath v0.053 humanoid character,
  weapon and armour models for units AND portraits. Import exact native art
  after verified Desktop preservation. Existing weapon art already matches.
  Include the released closed_helm template and common metal armour pool once.
  User explicitly named the Moon glaive: import its released one-handed crescent
  definition (old Bloodlines retained a two-handed polearm). Preserve other item
  stats, the native material physics and Bloodlines economy.
  Actual bound ruler portraits use the unit's saved look/equipment; civilian
  portraits stay deterministic without generating Units. Dragons/teeth cleanup
  remain outside this pass. Care/growth is v0.008, bonds move to v0.021.
- Delivered v0.008: user authorized real daily feeding, shelter upkeep, health and
  bounded growth. Buy counted fresh/preserved meat and wood at the dragon's
  location market from its actual owning household; protect human food reserves.
  Require a living present keeper. Run once per explicit queued midnight after
  food/death/succession, with persisted guards and actual receipts. Growth changes
  size/mass/strength/bite/tooth/claw geometry; gem hardness remains fixed.
  Eggs receive shelter care, no meat or hatching. Bonds/combat remain later.
  No art replacement or images in chat. Save TXT evidence and deliver Desktop/icon.
- Delivered v0.009: user reported rapid slowdown and requested right-side ms/FPS,
  overall work and memory diagnostics plus an actual fix. Target fresh Normal/
  one-day worlds and continued play; user explicitly excluded save compatibility
  testing. Preserve native population/coin/gear/wound calculations while bounding
  realtime job backlog and autosave snapshots. Keep diagnostics bounded and
  visible across gameplay. No artwork/images in chat or routine phone QA.
- Current user direction (2026-10-11): user approved the recovery plan with
  "okay - go." v0.010 is delivered. User then requested no gameplay work while
  compiling notes, requested the revised roadmap, then approved v0.011 with
  "ok go." v0.011 is delivered. User approved v0.012 with "ok go"; ownership and
  sliced consistent saves are implemented and verified. Package and actual
  Desktop/icon receipts establish delivery. User explicitly requested "just do13
  and14 at the same time." Pace settings and compact expandable results are
  implemented/verified together for v0.014 delivery. No standalone toggle build.
  User now explicitly authorized v015 and v016 together: complete paused/end
  combat log with character filters plus actual both-side officer rally. Ship one
  substantive v0.016 release, then continue to v017 funded raising/stand-down.
  Combined v016 implementation and selected native checks are complete; dated
  package/Desktop receipts establish the verified delivered copy. Keep the full
  transient journal, actual command links and exact retained blood rendering.
  User now authorizes v017 FIRST, then v018, continuing until BOTH are done.
  Deliver each version in order with its own Desktop folder/icon. v017 owns
  funded muster, real home returns and unraised startup; only after17 completion
  implement18 records, bundled fonts and House -> Laws. No combined18 shortcut.
  v017 is now delivered:sourcee460f8b/delivery092a15b, verified Desktop/icon and
  dated receipts. Current18 owns readable records/actual bundled font surfaces
  and read-only House Laws; preserve17 muster ownership and unraised startup.
  Performance and a good game are
  top priority; retain v011 campaign repair and v012 save/ownership fences. Follow ROADMAP.txt's
  revised v0.011-v0.020 recovery/playability passes before dragon bonds v0.021.
  Full rendered frame cost matters, not headless FPS.
  Actual-play screenshots show poor performance, including2FPS in battle.
  See docs/specs/PERFORMANCE_RECOVERY_PLAN.txt for measured evidence and code leads.
  Do not automatically raise a player field army on house selection. Review the
  starting troops, equipment, separate army funds and immediate payroll.
  Add a readable chronological combat log during pause and after battle, with
  descriptions from actual native outcomes, full-fight access, bounded memory,
  paged UI and character filters. Existing event caps must not silently discard
  the requested full fight. End results need compact casualty totals and expandable
  fallen/injured/lessons/loot/log details. Slow motion defaults OFF; optional in
  Esc -> Settings -> Gameplay. Fighting officers rally their men on both sides.
  Scrap's current automatic nearest-market buyer ignores faction; audit/expose
  payer/stock/coin receipts. Transport-before-sale is a proposal, not a user quote.
- One main outcome per pass; use ROADMAP.txt scope/deferred/done criteria.
  Preserve all stated requirements there and do not ask the user to repeat them.
- Current status (2026-10-12): v017/v018/v019 are delivered with their own Desktop
  folders/icons. v019 is settlement -> visible map -> actual local house ->
  Customize -> Review -> Begin. User explicitly authorized "20 21 22, go":
  complete20 buyer/payments, then21 actual rider bonds, then22 native dragon
  autobattle combat, without stopping between deliveries. Each gets its own
  Desktop folder/icon and verified package.23 mounted rider presentation and24
  breath remain later. Delegate specified QA to Luna/low.
  20(source39c155a/deliveryb28ffe8) and21(sourcee87e326/deliveryc531565)
  are now delivered with actual Desktop/icon receipts.22 is also delivered
  (source daed554/delivery4d29328):native dragon bodies/combat. Handoff prepared
  2026-10-14; next planned23 is actual mounted character/native rider injuries.
  No23 gameplay work has started. Keep installed19/20/21/22 and source art intact.
- Campaign feel follows CK3/AGOT dynasty politics in an original setting. Keep
  native material/body-part/wound/blood-loss battle calculations; dragons and
  actual riders extend that same simulation in their later milestones.
- User clarification (2026-10-12): battles are AUTOBATTLE on the existing map.
  Show the actual bonded character riding at the dragon's saddle handles while
  it fights alongside other units. Use existing automatic movement/targeting/
  attacks and native body/material/tissue/size/force/geometry/armour/wound/blood/
  morale/death calculations for dragon and rider. Remove the flight milestone;
  no takeoff/landing/altitude simulation, manual tactical control or separate
  damage resolver. No full gait/flight conversion or mount/dismount UI is required.
  Follow corrected v021-v028 numbering in ROADMAP.txt.
- Player selects a settlement, sees its location on the map, then chooses a house
  within that settlement, with a Customize House option. This supersedes direct
  city/ruling-family selection. Succession presentation belongs under Laws.
  Redesign city records, fonts and menu hierarchy for readable rendered content.
  Support portrait and landscape from the first interface. Keep the ruler portrait
  near the map lower left, clear of navigation and touch controls.
- Phone export is much later (user estimates about 50 development passes).
  Preserve the orientation foundation; routine checks now cover desktop gameplay
  and simulation. Repeat phone QA only when requested or near the export milestone.
- Extend native people, property, ledgers, army and BattleSim identities. No
  duplicate population, market, money system or dragon combat resolver.
- Reuse stable GPT-6.1 Sol helpers at high reasoning: `dynasty_economy`,
  `combat_dragons`, `interface_release`, `population_economy`. Their small briefs live in
  `docs/specialists/`. Give each a bounded assignment and explicit write scope.
- User direction (2026-10-12): delegate bounded checks to `bounded_qa`, using
  GPT-6 Luna at low reasoning. Keep Sol/high specialists for implementation.
  Give QA exact files/checks, limits and pass criteria; no scope expansion.
  Coordinate one engine run at a time; root integrates fixes and owns delivery.
  See `docs/specialists/bounded-qa.txt`.
- Primary agent integrates changes and owns the current roadmap/dev notes.
- Every delivered version must be installed in its own folder on the user's
  actual Desktop, with a versioned Desktop shortcut using Bloodlines.ico,0.
  Resolve Windows Desktop; verify installed hashes, shortcut target and shell icon.
  A ZIP alone does not finish delivery. Preserve previous versions and their icons.
- Humans/dwarves use male-preference primogeniture with daughter fallback;
  elves use eldest child; orcs retain native strength contests. Every settlement
  has a lord and liege within its current faction. Taxes debit owned common-folk
  wealth and credit the actual local ruling family; private tribute passes upward.
- Common folk are native workforce pools, with businesses/land/herds owned by
  tracked families. Recruit/promote real population slots exactly once; preserve
  owned private coin, food/work/service obligations and individual battle bodies.
- Keep checks short, isolated, serial and low priority. Include rendered frame
  and visual checks for performance/UI changes; do not touch player foreground.
  Record actual results, duration and source in `test-results/*.txt`.
  Never mark skipped, failed, stopped or inherited tests as current passes.
- No old-save compatibility work or long benchmarks unless requested.
- User direction (2026-10-17): every test runs on the smallest world (Normal) with a
  one-day world history; those are also the game's defaults (WorldGen.WORLD_SIZE,
  CampaignWorld.PRESIM_DEFAULT_DAYS). Do not spend time on bigger worlds or longer
  histories unless the user asks.
- TEST TIME RULE (user, 2026-10-17; applies unless the user asks otherwise): each test
  must finish in under 1 minute; 3 minutes is the absolute cap. Design tests for it:
  start from the shared saved world (tests/fixture.gd, TestFixture.start) instead of
  generating a world; set up later-game states directly (or from a saved fixture)
  instead of simulating weeks or months; fight the smallest battle that proves the
  point; prefer headless logic tests over rendered ones. No long diagnostics or
  benchmarks, no repeated full-suite runs: run the tests the change touches, then
  the main checks once. Usage spent on tests must stay a small part of a version.
- Never touch the mouse, keyboard or foreground. Copper Oath source/archives may
  be read to import the authorized models; never modify or launch Copper Oath.
- Before replacing art, preserve its source/render/metadata in a unique entry
  in the user's Desktop archive; resolve that folder when art work starts.
- Preserve resource UIDs. Keep one working source tree, small active notes and
  role briefs. Put intermediate files in the chat's `work/` directory.
