# v0.096 UI readability review — every page

Scope: the owner asked for every UI page to be reviewed for walls of text, font problems, font differentiation,
readability, playability of all text and layout. Each page below was screenshotted at 1600x900 in a cloud
container (Xvfb, `game/tests/ui_pages_v096.gd`: 70 pages in one run (all 8 Guide pages), plus the 5 Company tabs in an `--only=army` run; no test on the owner's PC), reviewed, fixed and
screenshotted again. Status: FIXED = changed and checked in the after-screenshot; OK = reviewed, no change needed;
NOT FIXED = seen but left for a later version (reason given).

## Changes that apply to every page

| Problem | Status | Change |
|---|---|---|
| Dark ink on parchment cards was being lifted to a light colour by the global contrast guard (light-on-light, unreadable) | FIXED | `core/sound.gd` `surface_behind()` finds the real panel/button surface; `UiTheme.readable()` picks dark ink on light surfaces and light text on wood. `keep_color` meta still opts out. |
| The selected choice in a toggle row looked greyed out (disabled) | FIXED | `RowOn`/`TabOn` keep their selected look when disabled; `UiKit.mark_choice()`; ordinary disabled buttons read as disabled. |
| Raw numbers such as `23323.31` and `103210` | FIXED | `UiKit.coins()` / `UiKit.decimal()` group digits and keep cents; `RecKit.num()` groups whole numbers; records cells and summary cards group bare whole numbers for display only (records metadata keeps the raw value). |
| Old-style (descending) figures in body text; ragged number columns | FIXED | Body font uses lining figures; records cells use tabular lining figures (`UiTheme.numeric_font()`). |
| Headings, lead lines and captions looked alike | FIXED | New `Lead` (larger, light) and `Caption` (bold small brass) styles; label and rich-text line spacing raised to 5 px. |

## Pages

| Page | Status | Notes |
|---|---|---|
| Title, New game, Settings | OK | Reviewed; no change needed. |
| Guide (title screen and map) | FIXED | Each guide page is a title, a lead sentence and short bullet points; every original fact kept. |
| Begin your bloodline (house choice, 5 steps) | FIXED | Colour pickers show a swatch and plain names instead of `#hex` codes. |
| Campaign map | FIXED | Ruler card shows the full house name ("House ..." cut-off fixed); the event log line has a dark backing and sits clear of the ruler card and nav bar; hidden when empty. |
| Ambitions | OK | Reviewed. |
| House (Your bloodline) | FIXED | Coin amounts grouped with cents kept. |
| Laws | FIXED | Current law shows as the selected choice. |
| Court & marriages, Relations | OK | Reviewed. |
| Treasure room | OK | Reviewed. |
| Politics | FIXED | Levy, tax, defence, tribute and governance text split one fact per line; coins grouped; the defence order in force shows as selected. |
| Population | FIXED | Lead line in the Lead style; counts grouped. |
| Dragons & eggs (list, detail, catalog) | FIXED | List/Roost and Your house/realm/All toggles show the selected choice. |
| Dragon roost | FIXED | Fact panel split under captions: Condition, Bond, Daily care, Last care. |
| Army (muster) | FIXED | Mounts has its own heading; horse prices grouped. |
| Company (overview, mind, skills, gear, health) | FIXED | Roster names were cut to "Ingish Stoneb..."; names use a smaller size on desktop; the row tooltip already gives the full name. The five detail tabs were reviewed. |
| Baggage | FIXED | Totals on two Lead lines with grouped numbers; row values grouped. |
| Town: Market | FIXED | Table headers bold and readable; quality coloured; quantity and coin columns in the number font. |
| Town: Provisions, Recruits, Healer, Buildings | OK | Reviewed. |
| Town: Contracts | FIXED | Offer panel was light text on a light panel (unreadable); now wood panel, bold job title, brass pay, grouped numbers. |
| Town: Town tab (Overview, People, Work, Stores, Land, Accounts, Prices, Orders, Research) | FIXED | Trend badges (Up/Down/Steady) are compact readable tags; prices grouped with one decimal kept; coin facts grouped. |
| Records: town tabs (Overview, Census, Market, Businesses, Treasury, Books, Land & homes, Roads, Sickness, Hardship, Garrison) | FIXED | Numbers grouped in tables and summary cards; civic links read "Open: Politics → / Population →"; crest chip fits the realm name. |
| Records: world tabs (Towns, Factions, Rulers, Census, Goods, Food flows, Merchants, Mines & land, On the move, Fights) | FIXED | Same number grouping and fonts. |
| Victory | FIXED | Lead line, four stat cards, Ambitions card with ✔/○ lines; scrolls. |
| Game over | FIXED | Lead line and grouped coins. |

## Not fixed in v0.096

| Item | Reason |
|---|---|
| Battle screen and battle aftermath | Not in the screenshot tour (needs a live battle); unchanged apart from the global contrast, figure and selected-state changes. |
| Very long records tables are still dense | Sorting, search and paging already exist; splitting them further would change records behaviour beyond a readability pass. |
| Town market "Stock" column in the Town tab prices list shows raw counts | Left as raw text because existing tests read it; values there are rarely four digits. |
| Phone layout (720x1280) | Checked with the same tour (`--mobile --size=720x1280`, 63 pages before the Guide pages were added): no new clipping or overlap from v0.096. The phone layout itself (for example the roost facts column beside the yard, the small guide box) is unchanged and left for a phone-specific pass. |

Tests and review: see `test-results/v0.096_ui_tests.txt` (75 UI tests one at a time in the cloud; every failure also fails the same way on main `951cf2d`) and the Sol 6.1 max read-only reviews recorded in `CHANGES.txt`.
