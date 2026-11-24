# CraftLink

A WoW: Forever addon that shares your professions and the recipes you know with your guild and
friends, so Crafting Order players can find you without you installing Crafting Order.

Get it on CurseForge: https://www.curseforge.com/wow/addons/craftlinknetwork

Commands: `/craftlink` (one status line), `/craftlink global` (join the global CraftLink channel),
`/craftlink global off` (leave it). By default CraftLink only talks to your guild and your friends,
and it writes nothing in chat unless you type `/craftlink`. Open each profession window once: that's
where it reads your recipes.

CraftLink doesn't take orders. If Crafting Order 1.53 or older is installed next to it, CraftLink
pauses and leaves the sharing to Crafting Order.

## Translations

CraftLink is written in French and comes in English, German and Spanish. To fix a line, open the
`CraftLink_Locale_<language>.lua` file on GitHub and change the text after the `=`; the key on the
left is the French original and stays as it is. Pull requests are welcome.

## The library

The `CraftLink-1.0` folder is also a LibStub library, which Crafting Order still embeds until it
depends on this addon. It holds the recipe catalogue and the per-profession data, the hex codec of
the known-recipes registry, the network protocol and its transports. LibStub keeps one copy at run
time, and at the same version number the first one loaded wins, so the addon and an embedded copy
share a single instance.

- `CraftLink-1.0/` and `LibStub/`: the library, the one source of truth. `sync-libs.ps1` copies it
  into host addons (`Libs/`), loaded by one `.toc` line, `Libs\CraftLink-1.0\lib.xml`.
- `CraftLink*.lua`: the addon (directory, presence, recipe scan, `/craftlink`).
- `tools/`: offline generation of `CraftLink-1.0/Data/<flavor>/*.lua` from the game client's tables
  and cached Wowhead pages (see `tools/README.md`).
- `docs/specs/addon-partage.md`: why and how CraftLink left Crafting Order (in French).

Only WoW: Forever (Interface 16001, Mainline API) is targeted. The Vanilla, TBC and Wrath data sets
stay as frozen catalogues.
