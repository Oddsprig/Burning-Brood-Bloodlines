# Map tokens spec (Direction A: one object per force type). Douglas picked A, 2026-10-04 20:30.
Replaces the world-map figures (party_icon.gd / creature_painter.gd on the map); battle sprites unchanged. One token per moving force: shape = type, colour = faction, pips = size and stance. Paint in code (polygons, circles, lines, arcs) and cache a texture per (type, faction, pips, stance). Static.

## Canvas and common rules
- 64x64 local box, origin top-left; (32,55) sits on the force's map position.
- On-screen size at 100% zoom: 52 px tall. Scales with zoom, min 40 px. Tap/hover hit circle r=30 screen px.
- Outline: INK #2b1d14, 2.2 px at 64-box scale (round joins), on every shape unless noted. BONE #f3ead2 for emblems and rims. WOOD #8a5a32, WOOD_D #5e3a1e.
- Shadow: ellipse at (cx,55), rx 15-26 (per type), ry 4.5, black at 28% alpha, drawn first.
- Faction colour: each faction's existing main colour, plus a dark variant (main x0.65).
- Draw order: sort tokens by map y. The player token is always drawn last (on top).

## Size + stance pips (all types except the player)
- A dark capsule (INK, fully rounded, height 8, width = n*6+4) centred at (cx,60), with n circles r=2.2 spaced 6 apart, the first at left+5.
- n = size band of headcount (beasts count as men): 1 = 1-5, 2 = 6-15, 3 = 16-30, 4 = 31-60, 5 = 61+.
- Pip colour = stance toward the company: hostile #e0392b, neutral #efe6cc, allied #52c35a (diplomacy thresholds). Monsters and bandits always hostile.

## 1. Player company
- Gold ring: unfilled ellipse at (32,55), rx 20, ry 6, #ffd34a, 2.6 px.
- Pole: line (16,1)-(16,55), WOOD_D, 3.6 px; gold knob r=3 at (16,1.5), #ffd34a.
- Banner polygon: (17,5) (54,5) (54,40) (45,34) (36,40) (27,34) (17,40), player colour; top band (17,5)-(54,11) dark variant; outline 2.4.
- Crest at (35.5,22), scale 1.15: copper coin r=7 #c87533 with outline, inner ring r=4 BONE 1.6 px, horizontal INK line across.
- No pips.

## 2. Faction warband / army
- Shadow centre x=30, rx 17.
- Pennant pole (46,4)-(46,54), WOOD_D, 3 px; gold knob r=2.2 at (46,4). Pennant (47,6) (62,6) (58,12) (62,18) (47,18) faction main, outline 1.6.
- Kite shield, outer (BONE rim, outline 2.4): (12,16) to (46,16), sides down to y=32, then quadratic from (46,32) via (46,47) to (29,56), ~8 points, mirrored.
- Inner field inset 3.5 px, faction main; top band y 19.5-24 dark variant.
- Emblem BONE at (29,35), ~16 px: Middle March upright sword; Northern clans double-bladed axe on a haft; Orcs two tusks under a bar; Goblins jagged three-point crown/ears with two INK dot eyes; Moon elves crescent moon plus a small star dot.
- Pips centred at x=29.

## 3. Town militia
- Shadow x=30, rx 15.
- Pitchfork behind: haft (14,54)-(48,6), WOOD_D, 3 px; three grey tines #9aa3a8 2.4 px: (43,13)-(50,3), (46,15)-(54,6), (40,11)-(46,1).
- Round shield r=17 at (30,36), WOOD fill, outline 2.4; dashed ring #c9b07a 1.6 px on the rim; horizontal band y 30-42 in the home town's faction main colour (clipped to the circle); outline redrawn on top.
- Emblem: BONE town tower (crenellated, INK door) at (30,36), scale 0.9.
- Pips centred at x=30.

## 4. Merchant caravan (same wagon for all; stripes and pennant in owner's colour)
- Shadow x=34, rx 26.
- Ox: body (2,38) (4,32) (14,31) (16,36) (16,46) (13,46) (13,41) (7,41) (7,46) (4,46) (4,41), #9a6b42, outline 1.6; two BONE horn strokes; yoke (15,38)-(22,40) WOOD_D.
- Wagon bed rect (20,34) 40x11, WOOD, outline 2.
- Canvas hood: (22,34) up to (22,26), arc over the top at y=12 (centre x=40), down to (58,26), (58,34); BONE fill. Three vertical stripes x=30, 40, 50 from bed to hood edge, 3.2 px, owner faction main; outline on top.
- Wheels r=6.5 at (28,47) and (52,47), WOOD_D, outline 1.8, BONE hub r=1.8.
- Pennant: pole (57,22)-(57,4) WOOD_D 2 px; triangle (58,4) (66,7) (58,10) faction colour.
- Pips centred at x=40 (escort + drivers band).

## 5. Bandits
- Shadow x=30, rx 15.
- Crooked pole polyline (26,56) (28,30) (25,4), WOOD_D, 3.4 px.
- Ragged flag (26,6) (56,8) (50,13) (57,17) (49,21) (55,26) (44,27) (40,31) (36,26) (27,28), fill #26201d, outline 1.8.
- Red skull #e64a2e at (40,17), scale 0.85: round cranium, jaw block, INK eye holes, two tooth lines.
- Crossed daggers: grey #b8c0c4 lines (10,52)-(24,38) and (24,52)-(10,38), 3 px, short WOOD_D grips at the lower ends.
- Pips centred at x=32 (always red).
- Deserters: army shield with the bandit's ragged black flag instead of the pennant, red pips.

## 6. Monsters
- Shadow x=32, rx 16.
- Spiked ring: 28-point star centred (32,32), radius 21/17, starting at top. Rim by tier: common #7a2d1c, EPIC #7b3fbf, LEGENDARY #e0a020. Outline 2.
- Inner disc r=14.5, parchment #e9d9ae, outline 1.6.
- Front-view head ~22 px: Wolf grey #6f6a66, pointed ears, long snout, black nose, yellow #ffd34a eyes. Bear brown #6b4226, round ears, tan muzzle #b08860, black nose/eyes. Boar dark #4a3528, wide head, pink snout #a07060, curved BONE tusks, orange-red eyes. Hydra (EPIC) three green #3f8a5a necks from a pale belly, wedge heads, yellow eyes, red tongues, 0.78 scale. Dragon (LEGENDARY) red #b8321f horned head, BONE horns, dark jaw, yellow slit eyes, small orange #ff9a2a flame. Wave-2 monsters each get their own head; never reuse.
- Pips centred at x=32, always red.

## Night and seasons
Day/night tint on tokens capped at 30%.

## Labels
No text on tokens. Tap shows name, faction, home town, headcount, make-up, stance.

## Acceptance
- Each type told apart by shape alone in greyscale at 100% zoom.
- A 16-man company is one banner.
- Cached textures; no per-frame painting.
