LAND MAP SPEC (Douglas 01:32: land owned shown as a clickable 2D map of simple square sprites, plot by plot, like the reference counting land in mu). Lives in the town screen's Land & Homes tab as a second view of the same data; also opens from a family page ("show my land"). Every tile is a real plot record; nothing is drawn that the sim does not hold.

1. SIM CHANGE: PLOTS (NEW SIM)
- A town's land stops being "acres by crop" totals and becomes PLOT records: id, grid x/y, acres (1 tile = 1 plot; default 5 acres [ours]; the unit is shown as acres), use, owner (family / state / business), worked by (persons), value, loan on it (id), history (bought, inherited, seized, sold, cleared).
- Uses: field (with crop), orchard, vineyard, pasture (with herd), woodland (dense / thinned / felled / regrowing), garden, home, business yard (with its business), mine or quarry (on a real deposit), wasteland, road, river or coast, wall.
- Totals in every other tab (Overview land, family acres, Land header, world Mines & land) are sums of plots, so the map and the numbers can never disagree.
- Land market and the forced-sale loop move whole plots. Clearing woodland turns it into field (labour + days); felling without clearing leaves it regrowing.
- World gen lays plots out in rings by real terrain: walls, homes and business yards at the centre; gardens, fields and orchards around; pasture beyond; woodland, hills, mines at the edge; rivers and coast cut through. Race culture changes the look (orc tents and pens, goblin burrows, elf living-wood halls).
- Perf: plots are a packed array per town (about 400-1,500 per town [ours]); the daily pass reads totals cached on change.

2. THE MAP (phone first)
- Square grid, one simple sprite per plot, 32 px art drawn at 48 px on phone so every tile is tappable. Pinch to zoom, drag to pan, "Centre" button. Own bright flat art: gold wheat, green pasture with a sheep, dark green trees, brown felled stumps, red roof for homes, a small anvil, mill wheel, tannery vat or kiln for business yards, grey pick for mines, blue water.
- Season shows on fields: sown, growing, ripe, stubble, bare in winter.
- Overlay chips across the top (one at a time): USE (default), OWNER (each of the 8 biggest landowning families its own colour, the rest grey, state land white, with a legend), VALUE (light to dark), FOR SALE / SEIZED (outlined), WORKED (tiles with workers today highlighted, idle land dim).
- Bottom summary strip updates with the overlay: e.g. OWNER shows "Harrow 120 acres, Cymbal 85, state 40 ...", tap a name to highlight only that family's plots.

3. TAP A PLOT -> plot card
- Use and crop or herd, acres, owner family (tap), worked by (persons, tap), yield last harvest and price it fetched, value and % of base, rent if let, loan on it (tap -> loans register), for sale price if listed, history lines ("Day 66, Y0: seized by the town from the Marbles for a missed loan; sold to the Cymbals for 3,100").
- Business yard -> its business page. Home -> the household on the Register.

4. BUSINESS ON THE MAP
- Every business owns or rents a yard plot and shows its trade sprite; health colour as a thin border (thriving green, steady white, struggling amber, failing red). Closed businesses leave an empty yard marked for sale.
- Farms are businesses too: a farm = its fields + its yard; the farm page lists its plots, crops, workers and harvest.

5. WORLD AND FACTION
- World and faction Mines & land tab: a small square per town on the world map sized by acres, coloured by its main use; tap -> that town's land map.

6. TESTS (headless)
- Sum of plot acres by use = every land total shown anywhere, on any day.
- A seizure moves the plot's owner, adds a history line, and the map's OWNER overlay changes the same day.
- Felled woodland regrows only over time; clearing needs real labour days.
- Map draws 1,500 plots at 60 fps on laptop; tap -> card < 16 ms.
