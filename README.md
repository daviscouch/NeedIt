# NeedIt

A World of Warcraft addon for **WoW Forever** (also works on Classic Era) that tells you whether to
**NEED**, **GREED** or **PASS** on gear, based on your class and spec.

Hover any armor, weapon, ring, trinket or relic and NeedIt adds a line to the tooltip:

```
NeedIt: NEED  Upgrade for Arms (+12% vs equipped)
Good: +12 Strength, +8 Stamina  |  two-hander suits Arms
```

It also:

- puts a small **green** (NEED) or **red** (PASS) dot on items in your bags and at vendors
- shows a hint above group-loot roll windows
- lets you force an item to always NEED or always PASS

## Install

1. On this page, click **Code → Download ZIP**.
2. Close the game, or be ready to `/reload`.
3. Unzip it into the AddOns folder for your client so you end up with `...\AddOns\NeedIt\NeedIt.toc`:

   | Client | AddOns folder |
   |---|---|
   | WoW Forever (beta) | `World of Warcraft\_classic_beta_\Interface\AddOns\` |
   | Classic Era | `World of Warcraft\_classic_era_\Interface\AddOns\` |

   On Windows the game is usually in `C:\Program Files (x86)\World of Warcraft\`. If `Interface\AddOns`
   doesn't exist yet, create it.

   If you used **Download ZIP** on GitHub, the folder is called `NeedIt-main`. Rename it to `NeedIt`.
   You only need `NeedIt.lua` and the `.toc` files. The `tests` folder can be deleted.

4. Start the game. On the character select screen, click **AddOns** (bottom left) and make sure
   **NeedIt** is ticked. If it says *Out of date*, tick **Load out of date AddOns**.
5. Log in. You should see `NeedIt: loaded.` in chat.

## Use

Just hover gear. Commands:

| Command | What it does |
|---|---|
| `/needit` | Show the class and spec NeedIt detected |
| `/needit spec` | List your specs with their numbers |
| `/needit spec 2` | Force a spec (if auto-detect picks the wrong one) |
| `/needit spec auto` | Go back to auto-detect |
| `/needit want <item>` / `unwant` | Always NEED this item (shift-click the item to insert its link) |
| `/needit ignore <item>` / `unignore` | Always PASS this item |
| `/needit bags` / `vendor` / `rolls` | Turn bag, vendor or roll markers on and off |
| `/needit debug` | Show what NeedIt detects on your client (handy for bug reports) |
| `/needit help` | List commands |

## How it decides

1. **Can you use it?** Checks armor type (mail and plate need level 40), weapon types, shields,
   relics and "Classes:" restrictions. If you can't use it, the verdict is **PASS**.
2. **Your spec:** the talent tree with the most points. On WoW Forever that means the three Classic trees
   shown side by side in the single talent window. Before level 10 it assumes a common leveling spec,
   and `/needit spec` overrides it.
3. **Score:** each stat is weighted for your spec (Strength for Arms, Spell Damage for Frost, and so on),
   plus weapon DPS and weapon-style preferences (daggers for Assassination, two-handers for Arms).
4. **Compare:** if it scores more than 2% above what you have equipped in that slot, it's **NEED**.
   For rings, trinkets and dual-wield weapons it compares with the weaker of your two. If one slot is empty,
   it says how the item compares with the one you already wear. If both are empty, it shows a score so you can
   compare candidates. Hovering something you're wearing shows **EQUIPPED**.
   Otherwise it's **GREED**.

The weights are rough rules of thumb, not a sim. Trinkets and on-use effects get a flat value, so read those yourself.

## Development

`tests/test_needit.lua` fakes the WoW API and runs hover scenarios through the addon outside the game:

```
lua tests/test_needit.lua NeedIt.lua
```
