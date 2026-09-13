# targetcursor — details

The long-form reference: why the anchoring works the way it does, how the range
colors were derived, where the art came from, and the full attribution record.

For installing and configuring, see [README.md](targetcursor/README.md).

---

## Why the height was wrong

Short version: **cursor height is a per-instance property, not a per-model one.**

FFXI stores a render scale on every creature at `actorPointer + 0x698`, and the
cursor hangs at the anchor bone's height **multiplied by that scale**:

```
anchor height = (bone 2 height − model render base height) × modelScale
```

This is easy to miss, because two creatures with the same name and the same
skeleton can have different scales. Any attempt to tabulate cursor height by
race, by bone count or by zone produces a table that works on your sample and
breaks in the next zone.

The evidence was four Yagudo in Tahrongi Canyon with an identical skeleton —
75 bones, bone 2 dz = −2.750 — where Scribe and Acolyte read `0.8500` and
Mendicant and Persecutor read `1.0000`. The two reading 0.85 were exactly the two
whose cursors were wrong. Reading the field per creature made every "race
constant" and every "zone-specific" quirk disappear at once.

Two other fixes came out of the same work:

- **Horizontal position** comes from the model's render base
  (`+0x678`/`+0x67C`/`+0x680`), not the bone. Taking all three axes from the bone
  drags in its model-space horizontal offset, which swings the cursor sideways as
  the model turns and as you rotate the camera.
- **Moghouse doors** report target index 0 — a null entity at the zone origin,
  which is why the cursor drew on the floor. Their real position lives in the
  target-actor struct at `+0x34`. World doors are different again and must use the
  entity position: for door-type objects `+0x678` is an *orientation* vector, not
  a position.

Verified against the game's own cursor on all five player races, on mobs and NPCs
across multiple zones, on child models, and on world and moghouse doors.

---

## Install

1. Copy the `targetcursor` folder into `Ashita4/addons/`.
2. `/addon load targetcursor`

To load it every time, add `/addon load targetcursor` to your Ashita script
(usually `Ashita4/scripts/default.txt`).

---

## Requirement: hiding the default target frame

**This addon draws a cursor; it does not hide the game's own.** You need
`hideparty` loaded alongside it, or you will see two cursors.

`hideparty` **ships with Ashita** — it is in `addons/hideparty/`, nothing to
download:

```
/addon load hideparty
/hideparty hide
```

Add both to your Ashita script to have it persist.

### Why the addon does not do this itself

FFXI's **target box and target arrow are a single UI primitive** — confirmed both
in `ROM/119/51.DAT` and by walking the live primitive tree. There is no way to
hide the box and keep the arrow, which is the reason this addon exists at all.

Hiding it means *writing* to the game's UI memory every frame. `hideparty` already
does that, correctly and with Ashita's blessing. Duplicating it here would make
this addon a memory writer for no functional gain, and two addons writing the same
visibility flag every frame would fight over it depending on load order. So this
addon stays **read-only** and leaves the hiding to the addon built for it.

### Keeping some frames visible

`hideparty` hides the party, both alliance frames and the target frame together —
it has a single flag for all four. To keep one of them, comment out its line in
the `d3d_present` handler at the bottom of `hideparty.lua`:

```lua
-- set_primitive_visibility(hideparty.ptrs.target, hideparty.show and 1 or 0);
```

That one keeps the game's target frame and cursor visible, which is useful for
comparing against this addon's cursor. Comment the `party0` / `party1` / `party2`
lines instead to keep the party or alliance frames.

Two caveats. `hideparty` has no `unload` handler, so unloading it while hidden
leaves your frames hidden until you reload it and show them. And it is a bundled
addon, so an Ashita update will overwrite your edit — copy it to a new folder
under a different `addon.name` if you want the change to survive updates.

### Overriding the DAT instead

If you would rather override the DAT directly, use
[XIPivot](https://github.com/Shirk/XIPivot) so the change is non-destructive —
do not patch `51.DAT` in place. Be aware that most of the obvious edits do not
work: a zero-size element leaves visible borders, removing the element changes
nothing, moving it off-screen still shows a sliver on the edge of the window, blanking the
texture relocates the whole window, and **setting the sprite index to `0xFFFF`
crashes the client**, because it is dereferenced unchecked.

---

## Configuration

Everything you would normally change is in one block at the top of
`targetcursor.lua`:

```lua
local filepathForCursor    = 'edit/default_cursor.png'
local filepathForCursorSub = 'edit/default_subcursor.png'
local cursorWidth          = 20   -- width of ONE frame in the sheet
local cursorHeight         = 32   -- height of ONE frame in the sheet
local animFrames           = 6    -- frames in the sheet, left to right (1 = static)
local animFPS              = 15   -- animation speed
local cursorScaleFactor    = 1.0  -- on-screen size multiplier
```

Reload with `/addon reload targetcursor` after editing.

### Included art

Three styles, each as a normal and a hi-res sheet. **`cursorWidth` and
`cursorHeight` differ per style — set them to match:**

| Style | Files | `cursorWidth` | `cursorHeight` | `cursorScaleFactor` |
|---|---|---|---|---|
| FFXI default | `default_cursor.png`, `default_subcursor.png` | 20 | 32 | 1.0 |
| FFXI default, hi-res | `default_cursor_hires.png`, `default_subcursor_hires.png` | 60 | 96 | 0.33 |
| HorizonXI | `horizon_cursor.png`, `horizon_subcursor.png` | 20 | 32 | 1.0 |
| HorizonXI, hi-res | `horizon_cursor_hires.png`, `horizon_subcursor_hires.png` | 60 | 96 | 0.33 |
| Winged arrow | `alt_cursor.png`, `alt_subcursor.png` | 42 | 46 | 0.7 |
| Winged arrow, hi-res | `alt_cursor_hires.png`, `alt_subcursor_hires.png` | 63 | 69 | 0.47 |

The hi-res sheets exist so the cursor stays clean when scaled up on a
high-resolution display: divide the suggested `cursorScaleFactor` by the upscale
factor to keep the same on-screen size. The `alt` hi-res sheets are 1.5×; the
`default` and `horizon` pairs are 3×.

**`default` and `horizon` are both the real target cursor** — the `anc_l` sprite
group lifted from each client's own `51.DAT`, all six animation frames, at the
20×32 the sprite data specifies.

**The table above assumes your menu and background resolutions match.** If they
do — which is the common case, and the default — `1.0` is correct at *any*
resolution and there is nothing to set.

If they differ, the rule is:

```
cursorScaleFactor = background height ÷ menu height
```

FFXI draws its menu layer at the **menu** resolution and stretches it up to the
**background** resolution. Its cursor is therefore that ratio larger than the
art's native size, while this addon draws at a fixed pixel size. Verified at
three points:

| Background | Menu | Factor | |
|---|---|---|---|
| 1920×1080 | 1920×1080 | **1.0** | verified |
| 2560×1440 | 1920×1080 | **1.333** | verified; the sub cursor measures 26×44 px against the sheet's native 20×32 — 1.30 and 1.375, bracketing 1.333 |
| 2560×1440 | 2560×1440 | **1.0** | verified |

The third row is what settles it. The background resolution is unchanged between
rows two and three, so resolution alone cannot explain the factor returning to
1.0 — only the ratio can.

Two things follow. **If your cursor looks too small, check your menu resolution
before touching this setting** — the mismatch is usually unintentional. And when
the menu layer *is* smaller than the background, the game is upscaling its own
cursor, so a hi-res sheet at the matching factor will draw a **sharper** cursor
than the game's original.

For the hi-res sheets divide by 3: 0.33 at matched resolutions, 0.44 for a
1080-tall menu layer on a 1440p background.

They differ because **HorizonXI ships its own cursor art**: a white-outlined
chevron, where the stock asset is a diamond above an arrowhead. `default_*` is
FFXI's own, `horizon_*` is Horizon's, and either works on any server — pick the
look you want. `alt` is a decorative alternative at an arbitrary size.

Each style also ships a `_neutral` sheet — `default_cursor_neutral.png`,
`horizon_cursor_neutral.png`, `alt_cursor_neutral.png` — used for range coloring
and for the optional main cursor tint. They are picked up automatically.

### Using your own art

A cursor sheet is **one horizontal row of frames**, every cell the same size:

```
+--------+--------+--------+--------+--------+--------+
| frame1 | frame2 | frame3 | frame4 | frame5 | frame6 |
+--------+--------+--------+--------+--------+--------+
      total width = cursorWidth × animFrames
```

PNG with alpha. Set `cursorWidth`/`cursorHeight` to **one cell**, not the whole
image, and `animFrames` to the number of cells. For a static cursor use a
single-cell image and `animFrames = 1`.

The cursor is drawn centerd horizontally on the anchor point, with its **bottom
edge** at that point — so leave whatever headroom you want as transparent pixels
at the top of the cell rather than adding an offset.

### Opacity

Both cursors draw at full opacity by default. To fade either one:

```lua
local cursorOpacity    = 1.0   -- main cursor;  0.0 invisible .. 1.0 as drawn
local subCursorOpacity = 1.0   -- sub cursor;   0.80 matches the game's own
```

This multiplies the art's own per-pixel alpha, so soft edges stay soft instead of
being clipped, and it composes with the tint and the range colors.

They are separate on purpose: you may want the main cursor faded back while the
sub cursor stays bright, since the sub cursor's color is carrying range
information and a faded red is easy to misread.

**Set `subCursorOpacity = 0.80` to match the game's own sub cursor.** The game
does not draw it fully opaque, and 0.80 is not a round number by coincidence:

| | |
|---|---|
| stored — `anc` in the client's own `51.DAT`, max alpha | 102/255 = **0.400** |
| drawn — sub cursor core, five independent plateau solves | **0.798 ± 0.005** |
| ratio | **1.995** |

**The client draws the cursor at exactly twice its stored alpha.** The mechanism
is not confirmed — a ×2 alpha op in the fixed-function texture stage
(`D3DTOP_MODULATE2X`) would do it, and so would drawing the sprite twice; reading
the texture-stage state at the cursor's draw call would settle which. The
measurement itself is solid: five of six plateau solves, across three colors and
four screenshots, agree to half a percent.

This is what was wrong with an earlier version of this section, which said
`cursorOpacity = 0.4` "restores how its source client actually draws it". **0.4
restores the file, which is half of what the client puts on screen** — hence the
washed-out look. The `default_*` sheet here is normalized ×2.5 off that file, so
2.5 × 0.80 = 2.0 and `subCursorOpacity = 0.80` reproduces the game exactly.

The DXT3 detail behind the stored figure: alpha is stored in 4-bit steps of 17,
and 102 is exactly 6/15, so the ceiling is an art choice rather than a decode
artifact. The other shipped style differs — `horizon_*` comes from a DAT that
stores full alpha (255 across 824 px), so on a client that doubles it would
simply clamp.

**0.80 and the range colors are per-client figures**, measured on Phoenix beta.
Another server, or a local install, may differ — re-measure rather than assuming
they travel. The main cursor's alpha has not been measured at all.
`cursorScaleFactor` is the exception: it turned out to follow a rule — the ratio
of your background and menu resolutions — rather than being a per-setup constant.
See above.

### Recoloring the main cursor

Off by default — the main cursor draws its art untouched. To tint it, set an RGB
triple at the top of the file:

```lua
local colorMainCursor = { 120, 255, 140 }   -- nil = leave the art alone
```

The tint is a color **multiply**, so it is applied to the neutral (gray) sheet
rather than the colored art — multiplying a tint into already-colored art gives
a muddy result. **You do not need to change `filepathForCursor`**: the neutral
sheet is derived from it automatically, so the tinted cursor keeps the shape of
whichever style you chose.

Note this recolors the main cursor unconditionally. The **sub** cursor ignores it
and stays driven by range, since its color carries information.

### Placement

These are measured against the game's own cursor and should not need changing:

```lua
local anchorBone      = 2      -- top of the body on every skeleton measured; -1 = model base
local anchorHeight    = 0.0    -- extra nudge in world units, positive raises
local anchorSmoothing = 0.04   -- how fast the damped height follows the bone
local objectPosOffset = 0x34   -- position offset for moghouse doors
```

`/tc` adjusts the first three live, which is handy for experimenting:

| Command | |
|---|---|
| `/tc height <n>` | vertical nudge, world units, positive raises |
| `/tc bone <n>` | anchor bone, `-1` = model base |
| `/tc smooth <n>` | `0`–`1`, how fast the height follows the bone |

**`/tc` changes are session-only** and are not written back to the file. Put
anything you want to keep in the block above and reload.

---

## Sub cursor range colors

When you select a spell or ability, the game tints its sub cursor by whether the
action can actually reach the target — red out of range, yellow almost, blue in
range. This addon reproduces that:

```
blue    if  sqrt(clientDistance) <= maxYalms + hitbox
yellow  if  <= maxYalms + hitbox + 0.95
red     otherwise
```

Every term is read live from the client, so there is **no spell table** and
nothing to maintain when a server rebalances an ability:

| Source | |
|---|---|
| `ITarget:GetActionTargetMaxYalms()` | the selected action's own range |
| `IEntity:GetModelHitboxSize(index)` | the target's hitbox |
| `IEntity:GetDistance(index)` | the client's own distance |

Three details cost real effort to establish, so they are worth stating plainly:

- **`GetDistance` returns the distance SQUARED**, and it is **horizontal only**,
  while the client's own check is three-dimensional. The height difference has to
  be added back by hand from `GetLocalPositionZ`, or the cursor stays blue well
  past the real edge whenever a target is above or below you.
- **A ranged attack gets no hitbox**, and `ITarget:GetActionId()` is the only way
  to know it is one — it reads 0, where every spell and ability carries its own
  id. `SubTargetFlags` cannot tell them apart (16 from a menu, 18 from a macro,
  the same for a spell) and neither can `ActionType`, which reads 71 for both.
- **`ModelHitboxSize` is already scaled.** It is the entity's live hitbox, not a
  per-model constant — the same Yagudo model reads 1.5 at model scale 1.00 and 1.2
  at 0.85. Multiplying it by the model scale double-counts.
- **The allowance is exactly the hitbox.** No constant, no per-race adjustment.
  Players are not a special case; they just have small hitboxes (a Mithra reads
  0.4, a Galka 0.8, a Savanna Rarab 1.1, a Yagudo 1.2–1.5, an NM 3.6).

Calibrated over seven walks against the game's own cursor, across three model
scales, two spells, players, mobs and an NM.

### Configuration

```lua
local rangeColors     = true
local colorInRange    = { 121, 107, 255 }
local colorNearRange  = { 255, 255, 103 }
local colorOutOfRange = { 255, 108,  97 }
local filepathForCursorRange = nil   -- nil = derive from filepathForCursor
```

Set `rangeColors = false` for a plain sub cursor.

All three colors are sampled from the game's own sub cursor rather than chosen
by eye. Each was shot twice in the same position, once against a dark surface and
once against a bright sky, which gives two equations per pixel and lets the
cursor's own alpha be solved instead of assumed:

```
observed_dark  = color * a + dark  * (1 - a)
observed_light = color * a + light * (1 - a)
```

Both are worth knowing because neither matches its name. The in-range blue is a
**violet at hue 247**, not the sky blue it reads as — an earlier `{ 130, 205, 255 }`
guess was wrong by 44° of hue and still looked plausible in play. The near-range
yellow is a **pure lemon**, R and G equal at hue 60, where a guessed amber
`{ 255, 225, 110 }` sat 12° away. Only the red was close: a guessed
`{ 255, 95, 95 }` was 3° off the measured hue of 4°.

The blue was measured twice. The first attempt, `{ 101, 86, 195 }`, got the hue
right and the brightness badly wrong: it averaged the brightest quartile of the
cursor and treated that core as opaque. The core is not opaque — its alpha is
0.80 — so part of what was measured was the dark wall behind it. Re-solved
against two different skies, which agreed on the color to within 3 levels, the
blue comes out **half again brighter** than that first figure.

All three were finally solved against the 0.80 drawn ceiling, anchoring each shot
on the fact that the brightest channel clips at 255. The implied plateau alpha
came out at 0.794, 0.801, 0.798, 0.805 and 0.798 across five of the six shots —
the agreement that established the ceiling in the first place. The sixth, red
over the dark wall, reads 0.745 because that frame's core never reaches full
coverage, which is also why red's two estimates differ by 6–11 levels where
yellow's agree to 1.

These are the measured colors **as-is**, with no headroom correction, and that
works only because of one change to the art. Each color solves to a
near-saturated core — 255 in the brightest channel for red and yellow, 249 for
blue — while `default_cursor_neutral.png` used to peak at 229. Since the tint is
a color multiply, that ceiling capped every range color about 10% below the
game's whatever went in the config. **The sheet has been rescaled by 255/229** so
its core reaches full; 24 of its 2055 visible pixels clip, which is what the
game's own art does at its core anyway. Relative shading inside the sprite is
untouched. The dimmer pre-rescale sheet is not shipped — it never matched what
the game draws.

With that in place the addon reproduces the game's sub cursor to **within 1.6
levels per channel**, checked against both skies of the calibration pair.

The other styles' neutral sheets have not been rescaled, so these numbers will
render differently under `horizon_*` or `alt_*` — `horizon_cursor_neutral`, for
one, is a dark interior with bright edges rather than a bright core.

The tinted art must be a **neutral (gray) sheet**: tinting is a color multiply,
so applying it to already-colored art muddies the result.

**`colorInRange` owns the sub cursor's color in every state**, not just the
in-range one. States with no action target — using an item, and the frame or two
entering stnpc/stpc — used to fall back to the pre-tinted `*_subcursor.png`,
which meant the blue lived in two places and could drift apart. It did: the
shipped art was 66° of hue away from the measured color, and the mismatch only
showed during item use. Now those states tint the neutral sheet with
`colorInRange` like every other, so changing that one value moves the whole sub
cursor. The name still fits — items are self-targeted, and the range logic
already treats self-only actions as in range.

`*_subcursor.png` is therefore only drawn when `rangeColors = false`, or when the
neutral sheet cannot be loaded.

You do not normally set `filepathForCursorRange`. Left at `nil` it **derives the
neutral sheet from `filepathForCursor`**, inserting `_neutral` before the
extension — so `edit/horizon_cursor.png` uses `edit/horizon_cursor_neutral.png`, and it
follows automatically when you switch styles. Every included style ships one. Set
it explicitly only for custom art that does not follow that naming.

If the neutral sheet cannot be loaded, the addon says so once in chat and leaves
the cursors untinted, rather than silently doing nothing.

`rangeYellowBand` (0.95) is the width of the yellow band, the one value measured
rather than read from the client; the seven runs ranged 0.88–1.04.

---

## Smoothing

Bone height is low-pass filtered so breathing and run cycles do not reach the
cursor. Filter state is keyed on target index, and **target indices are recycled**
as entities spawn, despawn and you change zones — so without a guard, targeting a
crab on the index a Yagudo just vacated starts the filter at the Yagudo's height
and crawls to the crab's over about a second, which looks like the cursor floating
into place.

Two guards prevent that. The addon remembers which actor each damped value
belongs to, and independently restarts the filter on any single-frame height jump
larger than `anchorSnapJump` (0.5 world units) — a creature's own animation moves
bone 2 by a fraction of a unit, while a different creature differs by whole units.
A new target snaps to the correct height on the first frame.

---

## Compatibility

Ashita v4. Developed and tested during Phoenix Beta; the memory offsets are from the
retail client, so it should work on retail and other private servers, but that is
untested — if `+0x698` moves, cursor heights will be wrong on scaled creatures.

### What this addon reads and does

| | |
|---|---|
| Reads | target index and action-target state; the target's position, model scale, hitbox and skeleton |
| Draws | one sprite over the current target and sub target |
| Writes | nothing — no files, no settings, no logs |
| Network | none |
| Input | none — it does not send commands, keys or packets |
| Memory | reads only the specific fields listed above, at fixed offsets |

There is **no memory scanning**, no pattern searching over process memory, and no
file I/O of any kind. It cannot act on your behalf; it draws a cursor and nothing
else. Every value it uses is one the client already computed to draw its own UI.

A separate development build exists with diagnostic tooling (struct dumps, memory
scanning, log files) which was used to work out the offsets. That build is
deliberately **not** distributed — this is the release build.

Can be installed alongside `customtarget` for comparison — different addon name,
different command prefix (`/tc` vs `/ct`), different event handles.

---

## Credits

This is a **fork**, not a new addon, and it has two upstream authors.

**Jyouya** wrote `customtarget`
([Ashita-Stuff/addons/customtarget](https://github.com/Jyouya/Ashita-Stuff/tree/master/addons/customtarget)).
**yzyii (Rag)** wrote the v0.6 that this fork actually started from
([xiconfig/extra/customtarget](https://github.com/yzyii/xiconfig/tree/main/extra/customtarget)).

The difference between them is why both are credited:

| | Jyouya, v0.5 | yzyii, v0.6 |
|---|---|---|
| sub cursor | none — one cursor for the active target | `subcursor.png`, drawn separately |
| `getPos` | absent, inlined | factored into a function |
| art | `me.png` | `cursor.png` + `subcursor.png` |
| size | ~180 lines | ~240 lines |

Every sub-cursor feature here descends from yzyii's work. Note that his copy
still carries `addon.author = 'Jyouya'` — he never added himself to it, so
crediting him by name goes beyond what his own file claims.

Still **unchanged** from upstream:

| Function | What it does |
|---|---|
| `loadCursorTex`, `loadSprite` | D3D8 texture and sprite creation |

Also upstream: the addon scaffolding, the D3D device setup, and the structure of
the `d3d_present` handler. `getPos` is shared work — a good part of the original
remains inside it. Two functions that were once unchanged have since been
rewritten for reasons unrelated to attribution: `matrixMultiply` now writes into
a scratch matrix, `worldToScreen` does four dot products in locals, `getBone`
became `getBoneOffsetZ`, and `vec4Transform` was deleted as unused.

Added in this fork, by **Hiken**:

| | |
|---|---|
| Anchoring | cursor height from the model's own render scale — correct on every race, mob, NPC and child model without per-model tuning |
| Horizontal tracking | render base rather than bone position, so the cursor no longer drifts as the camera turns |
| Doors | moghouse doors (no entity index) and world doors handled separately |
| Smoothing | filter restarts on a change of target instead of gliding between them |
| Range colors | sub cursor tinted red / yellow / blue by whether the action reaches, derived from the client's own range, hitbox and distance |
| Animation | all six frames of the cursor at the game's own 15fps |
| Tint and opacity | optional main cursor recolor, separate opacity for both cursors |
| Art | the real `anc_l` cursor extracted from `51.DAT` in three styles |

- Cursor art extracted from `ROM/119/51.DAT`. The `default_*` and `alt_*` sets are
  Square Enix's; the `horizon_*` set is **HorizonXI's own replacement art**, taken
  from their client. Neither is original work, and both are included only for use
  with the game.

---

## License

Released under the **MIT License** — see `LICENSE`.

Neither upstream project carries a license file, so both authors were asked
directly and both granted permission:

- **Jyouya** pointed at yzyii's v0.6 and said to use it as a starting point
- **yzyii (Rag)**: *"It has no license / feel free to take it and do whatever
  you want with it."*

Those grants cover the upstream code this fork is built on. The MIT license
above covers the fork as a whole.

Cursor art is extracted from the game's own data files and is not original work:
the `default_*` and `alt_*` sets are © Square Enix, and the `horizon_*` set is
HorizonXI's own replacement art, included with their client. It is bundled here only for use with
the game.
