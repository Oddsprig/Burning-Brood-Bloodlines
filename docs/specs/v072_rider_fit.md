# v0.072 rider fit

The owner's screenshot (`docs/specs/v072_owner_rider_screenshot.png`) is a code-drawn blue wyvern with a human on its back. The person is small against the animal, sits in the open wing in front of the wing root, holds a chair pose with both legs on the near side, and has no readable saddle.

These notes record the cause and the rule. The drawing change is in the version folder at the same paths as the worktree. The worktree itself refused the write.

## Findings

Dragons keep two hind legs. Wings are their forelimbs. Source pixel proportions are unchanged. The released Copper Oath v0.053 on-foot humanoid heights are unchanged.

The rider is the code-drawn seated figure in `game/art/mounted_rider_art.gd`. `DragonView`, `DragonCard`, and `DragonMountPreviewArt` place it. Horses use the same figure from `HorseDoll`.

The socket was the neck. Each code-drawn breed stores `seat_px` at the base of the neck, ahead of both wing roots. That point is also the source origin, so the logical seat stays at the origin while the painted back is further toward the tail. The person hangs in the wing opening. Classic catalogue sockets sit forward of the higher wing root as well. `seat_px` stays where it is so the source origin, and the checks that lock that neck socket, do not move.

The scale was a fixed human. Battle drawing used `FigurePainter.PX` (2 pixels per logical unit) while the dragon's logical size follows its size class (`units_per_pixel` times `linear_scale`). A medium back is only a little taller than a 24-unit person. A huge or colossal wyvern keeps that same 24-unit person, so the rider becomes a speck. The card and the mount preview share one camera and show the same ratio. Horse riders were already near a horse-and-human ratio, because the horse frame is small. Their seat is already the mid-back hollow behind the withers (image x 37.5, withers near x 44.5).

The pose was a chair. Both thighs ran down and forward, so in a side view both legs are on the near side. The far layer drew a hip dot, not a far leg. An unarmed rider's hands do reach saddle handles. There is no head rope.

A saddle was already painted in the rider's middle layer (seat, cantle, pommel, handles, girth) and stacked under the near body. At the neck socket, under a tiny chair pose, it does not read as a saddle on the back. The horse frame also paints its own pad. The rider still draws a saddle layer on top of that, under the person.

## Scale rule

Rider standing height, divided by the mount's ground-to-saddle height:

- Dragon: target 1.00, band 0.90 to 1.10.
- Horse: target 1.12, band 1.02 to 1.22.

Standing height is the figure's native height (24 for a human, and the released race height for the others). It is not changed. The mounted composite's pixels-per-unit is chosen so the ratio hits the target. A larger dragon gets a larger seated drawing. An on-foot figure stays at the v0.053 size. Dragon source art is not stretched.

## Saddle anchor

Per breed, `RiderFit.FORM_ANCHOR` is a tailward step and a downward step from the higher wing root, measured on a 128-pixel canvas. Wider classic sources scale that step by image width / 128. The hip is placed on that point. The wingbeat bob is already in the frame's wing-root pixels, so the anchor follows the back. The six forms are spirewing, broadmantle, reedrunner, ironcrest, stormkeel, and duskfin.

Horse coats share one body. The anchor is the existing mid-back hollow, just behind the withers, for every coat and gait.

## Straddle

Facing right, y down. The near thigh goes down the near flank, only a little forward. The far thigh goes down and back, with the opposite x sign, and is drawn on the far layer so the mount covers it. Shins hang. An unarmed rider's hands stay on the pommel handles. A weapon or shield still occupies that hand. No head rope.

## Saddle layer

The code-drawn saddle stays its own layer: seat, cantle, pommel handles, and a girth strap. Draw order is far rider, mount, saddle, near rider. The saddle is under the rider and on the mount.

## Armour drawn in code (proposal only)

Not built here. On-foot people are already one `FigurePainter` frame. Body, clothing, and armour are baked together at the v0.053 race heights (`test_humanoid_art_import.gd` records those heights and pose counts). A later redesign would paint the body, then clothing, then armour, helm, and weapons as separate layers, the way the saddle is a layer under the rider. That would replace the baked battle frame. It would not replace the dragon sprites, and it is not this mount fit. The released heights, palettes, and pose frame counts stay until that work is scoped on its own.

## What changed

`game/art/rider_fit.gd` holds the ratio, the per-form anchor, and the placement used by the dragon battle view, the dragon card, the mount preview, and the horse doll. The seated rig's legs straddle. `game/tests/test_rider_fit_v072.gd` covers every dragon form and every horse coat.
