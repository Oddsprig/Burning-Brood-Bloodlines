Source-only v091 completion. UNRUN: parsing, raster execution, PNG generation, timing and visual review all remain for root/TestBridge. No version, roadmap, geometry, socket, pose or anatomy changes.

Draft gaps corrected:

- `pixel_canvas.gd`: `begin_equipment`, `_equipment_mat`, `_put`, `end` now light declared metal colours only and preserve legacy edge shading elsewhere. Equipment streams normals through `ShadedLayer.shade_normal` without full image/depth/normal allocations. `rect` gains bevels on its unchanged mask. Equipment `bevel_normal` uses the nearest boundary, fixing inward crescent-mouth normals. Body `ShadedLayer.poly`, ramp generation, light vectors, Bayer order and default specular power 10 remain unchanged.
- `figure_painter.gd`: `metal` marks actual metal materials; `_shield` explicitly suspends the finish for heraldry/wood, including palette-colour collisions. Seeded bronze/iron/steel palettes and finish parameters are retained.
- `item_icon_art.gd::draw`: adds missed metal-face colour aliases and keeps bows on their legacy path. `weapon_art.gd::draw` also excludes bows from the metal scope.

Reauthored `test_shaded_equipment_v091.gd`: frozen legacy body-lighting equation; distinct six-stop and common-grey specular profiles; real template icons and equipped normals; alpha, clipping, grip/anchor, input purity, heraldry, wounds, quality and gem checks. Saves three task-owned `user://shaded_equipment_v091_*` CPU PNG sheets and prints paths/layouts. Comparison disables the finish on current geometry; it is not an archived v087 golden. Broader rider regression and measured performance remain unverified. No motion logic changed.

Root-only command from the v091 project root through TestBridge (goal <60s, hard 180s):

`godot --headless --path game res://tests/runner.tscn -- --test=res://tests/test_shaded_equipment_v091.gd --watchdog=180`
