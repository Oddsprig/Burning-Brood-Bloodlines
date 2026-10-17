CURRENT DESIGN CORRECTION 2026-10-09: Ordinary recruitment, visible descendant relationships, and personal memory of family members killed by your company. Future planning only; not implemented in v0.037. This supersedes the old special descendant recruitment proposal below.

# AI clashes in the real sim (Douglas, 2026-10-04 19:02-19:05)
Decision (as read by the integrator, Douglas may correct): every AI-vs-AI clash on the campaign map is fought
in the real combat sim, every unit of both forces, headless, sliced across frames so the player never lags.
Results flow back: wounds, deaths, kills, kill renown, promotions/succession, family losses, town workers.

Measured on the laptop (current sim, full logging): 5v5 38 ms, 10v10 56 ms, 20v20 175 ms,
100v100 2.6 s (1.9 ms/tick), 300v300 29 s (8.7 ms/tick). Phones ~3-5x slower.
Plan:
- Frame budget (~2 ms/frame) stepping a queue of AI battles; bands shown locked "in battle" with progress.
- AI battles skip story text (rebuild from seed on demand).
- Spatial grid for targeting (cost currently grows ~quadratically).
- Large battles split into fronts (separate sims on one field) with reserves feeding in.
- Worker thread option for phones once slicing is measured on a device.
Order: after economy specs 1/2.

## Aftermath flow, retirement, wages (proposed 19:06, awaiting Douglas's pick; recommended "all of it, with pensions")
- After any AI engagement record each unit: dead / maimed (permanent loss) / wounded / fine. Dead leave their family row (history line, lost earner, lost pay). Maimed go home as disabled members (lighter work, care costs). Wounded heal at home and return if fit. Officer deaths/retirements open posts filled by the faction rank rule.
- Company "Retire" button: unit goes home to its family row; optional pension (standing +), dismissing a maimed veteran without one costs standing and company morale. Retirees stay as named people in their town; retired officers keep renown and may become town heads or militia leaders.
- Company wages (and pensions) go into the man's family purse in his home town (economy spec 2 rule applies to the company too): paid families pay tax, clear debt, keep homes, buy goods/land; unpaid or bereaved families slide into debt/confiscation and feed the recruit pool.
- Family tab on every company unit's sheet: purse, debt, home, land, wealth chart over the campaign, household, what wages bought (history lines), tap through to the family record in town.
- Recruitment uses ordinary rules for real people. Descendants of former company recruits receive no special recruitment chance, guaranteed appearance or teaching bonus. Whenever encountered, their person/recruit details show the actual son/daughter/grandchild/etc. relationship and prior company service, even if they never join.
- Real people remember when your company killed their family member. Extend existing identities, kinship, dated person/family events and backstories with the actual victim and company responsibility. Preserve ancestry/service links and loss memories across household moves and save/load, beyond short recent-history limits; the remembered fact does not prescribe forced revenge.
