# targetcursor

An Ashita v4 addon that replaces FFXI's target cursor with your own art, anchored
at the correct height on every model.

A fork of `customtarget`, written by
[Jyouya](https://github.com/Jyouya/Ashita-Stuff/tree/master/addons/customtarget)
and extended by
[yzyii](https://github.com/yzyii/xiconfig/tree/main/extra/customtarget), whose
v0.6 this started from.

## Features

- **Correct height on every model** — derived from the model's own render scale,
  so no per-race, per-model or per-zone tuning
- **No sideways drift** — horizontal position tracks the model's render base
  rather than a skeleton bone
- **Range colors** — the sub cursor is tinted blue / yellow / red by whether the
  selected action actually reaches. The defaults are sampled from the game's own
  cursor; all three are editable
- **Animated** — all six frames at the game's own 15fps
- **Three art styles included**, each with a hi-res sheet
- **Doors and NPCs handled** — including moghouse doors, which have no entity
- **Tint and opacity** — optional recolor of the main cursor, separate opacity
  for each

<img width="2560" height="600" alt="targetcursor-banner" src="https://github.com/user-attachments/assets/0a9dee67-026e-4b7c-b892-640006cb6068" />


## Install

1. Copy the `targetcursor` folder into `Ashita4/addons/`
2. `/addon load targetcursor`

To load it every time, add that line to your Ashita script (usually
`Ashita4/scripts/default.txt`).

## Requirement: hide the game's own cursor

**This addon draws a cursor; it does not hide FFXI's.** Without this you will see
two. `hideparty` ships with Ashita — nothing to download:

```
/addon load hideparty
/hideparty hide
```

Add both to your Ashita script to persist. If you want the party list visible but
the target cursor hidden, see [DETAILS.md](DETAILS.md#keeping-some-frames-visible).

## Configuration

Everything is set at the top of `targetcursor.lua`, in the block marked
`* Edit this part to match your custom cursor *`. Each setting is documented
where it sits, with its default. Reload with `/addon reload targetcursor`.

The settings you are most likely to touch:

| Setting | What it does |
|---|---|
| `filepathForCursor` / `filepathForCursorSub` | which art to use |
| `cursorWidth` / `cursorHeight` | frame size — **must match the art**, see below |
| `cursorScaleFactor` | on-screen size |
| `cursorOpacity` / `subCursorOpacity` | transparency, 1.0 = art as-is |
| `colorMainCursor` | optional `{r,g,b}` recolor of the main cursor |
| `rangeColors` | set to `false` to disable range tinting entirely |
| `colorInRange` / `colorNearRange` / `colorOutOfRange` | the three range colors, as `{r,g,b}` |

### Included art

`cursorWidth` and `cursorHeight` differ per style — set them to match:

| Style | `cursorWidth` | `cursorHeight` | `cursorScaleFactor` |
|---|---|---|---|
| `default_` — FFXI's own cursor | 20 | 32 | 1.0 |
| `horizon_` — HorizonXI's art | 20 | 32 | 1.0 |
| `alt_` — winged arrow | 42 | 46 | 0.7 |
| any `_hires` variant | see [DETAILS.md](DETAILS.md#included-art) | | |

`default` and `horizon` are the real target cursor, lifted from each client's own
`51.DAT` with all six animation frames.

If your **menu** and **background** resolutions differ, `cursorScaleFactor` is
`background height ÷ menu height`. If they match — the common case —
`1.0` is correct at any resolution.

## Commands

Live tuning, session-only. Anything you want to keep goes in the config block.

```
/tc height <n>     nudge the cursor up or down
/tc bone <n>       anchor bone; -1 uses the model base
/tc smooth <0-1>   height smoothing, 0 = off
```

## Compatibility

Reads the target and entity structures and draws with its own sprite. It does not
write to game memory, send packets, or alter anything the server sees. See
[DETAILS.md](DETAILS.md#what-this-addon-reads-and-does).

## Credits

**Jyouya** wrote `customtarget`. **yzyii (Rag)** wrote the v0.6 this started from,
which added the sub cursor, factored out `getPos`, and replaced the art. Both gave
permission for this fork. Full attribution, including what survives unchanged, is
in [DETAILS.md](DETAILS.md#credits).

Cursor art is extracted from the game's own data and is not original work: the
`default_` and `alt_` sets are © Square Enix, the `horizon_` set is HorizonXI's
replacement art. Included only for use with the game.

## License

MIT — see [LICENSE](LICENSE).
