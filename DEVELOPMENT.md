# AI Radio Hunt - Development Notes

Developer-facing companion to `README.md`. This mod is a sibling to
**DispatchAI** (`../dispatch_ai/`) and reuses its architecture wholesale -
read `../dispatch_ai/DEVELOPMENT.md` first if you haven't; this doc only
covers what's different here.

## Status: vertical slice

A short hardcoded chain of five survivors (Mara, Jonah, Ellis, Nadia, Reyes -
see `Config.Hunts`), no relocation, no lying about core location, no
branching survivor network (the chain is a fixed linear sequence, not a
graph). Built to prove the new mechanics (proximity tiers, world item
spawning, structured "found" LLM output, a readable note, and chaining to a
next survivor via a found-note frequency) end to end - not the full design
doc. See "Known rough edges / next steps" below for what's deliberately not
built yet.

**Archetypes, from the original design doc's list** - Mara and Jonah are
both "Friendly" (want to be found, don't mislead). The three added after
them give some personality variety while staying inside the same mechanics
(still static, still honest about core facts, still a straight line, not a
graph):

- **Ellis - Paranoid.** Guarded and suspicious of anyone new over the radio;
  meets questions with questions early on, warms up slowly across the
  conversation rather than upfront.
- **Nadia - Lonely Survivor.** Starved for company, warm and eager,
  genuinely doesn't want the call to end - the one persona allowed a
  slightly longer reply cap (three sentences instead of two, via
  `buildSystemPrompt`'s optional `dialogueLengthLine` param) to reflect how
  much she talks.
- **Reyes - Military Survivor.** Ex-service background, clipped and
  transactional - treats information/help as something with a cost, no idle
  comfort talk.

None of these get an actual trust-gate, relocation, or trade mechanic (those
layers aren't built - see "Known rough edges" below) - the archetype is
expressed entirely through `systemPrompt` personality, same as Mara/Jonah
already were.

## Chaining to the next survivor

`Config.Hunts` (`mod/.../AIRadioHunt/Config.lua`) is an ordered array, not
a single hardcoded location - each entry has its own `personaName`,
`targetX/Y/Z`, `channel`, and `nextChannel`. `HuntState` tracks each
character's position in that array (`activeHuntIndex`, in
`AIRadioHunt_State` ModData) and advances it by one every time
`HuntState.completeHunt` finishes a hunt that has a next entry - resetting
`started`/`found`/`itemsSpawned` so the newly-active hunt behaves like a
fresh one (new target square, new channel gate, new persona).

The companion mirrors this with a `personas` array in `config.json`
(`mod/.../Config.lua`'s `Config.Hunts` and the companion's `personas` must
stay index-aligned - `personas[0]` is `Config.Hunts[1]`, etc.). Every
request now carries `context.huntIndex` (read directly out of
`AIRadioHunt_State` in `Context.build`, not via a module dependency on
`HuntState.lua` - see that function's comment for why), and
`handleRequest` uses it to pick the right persona and to key memory as
`` `${characterId}-${persona.id}` `` instead of just `characterId` - so
Jonah never inherits Mara's conversation history (or vice versa) even
though they share the same PZ character and memory-file directory.

Adding a third survivor: append one more entry to `Config.Hunts` (giving
the previous last entry a real `nextChannel`), and one more entry to
`config.json`'s `personas` at the same index - that's the whole extension
point.

**Grounding who the player is, once there's a previous survivor** -
testing surfaced Jonah mistaking the player for Mara. His prompt only said
he was "talking to someone over a walkie-talkie... the same person who
just tracked down Mara" - phrasing loose enough for a small model to read
as "you are Mara" rather than "you are the person who found Mara." Fixed in
`baseMessages` (`companion/index.js`): whenever `huntIndex > 1`, an
explicit system message names the previous persona
(`config.personas[huntIndex-2]`) and states plainly that they are not the
current persona, and the player is not them either - just the same living
person who found their note. This is derived purely from `huntIndex` +
`config.personas` ordering on the companion side; no new field needed from
the mod.

## How it works

Same file-bridge pattern as DispatchAI: the Lua mod can't make network
calls, so it writes a request to `~/Zomboid/Lua/AIRadioHunt_request.json`
and polls `AIRadioHunt_response.json`, while `companion/index.js` (a
separate Node process) does the actual talking to Ollama. See
`../dispatch_ai/DEVELOPMENT.md`'s "How it works" section for the full
diagram - it's identical here, just with different bridge filenames and
six request `kind`s instead of two:

- `"chat"` - the player typed something.
- `"start"` - the player was just detected carrying a radio tuned to Mara's
  channel for the first time; Mara keys in unprompted.
- `"sound"` - a real, audible conditional-speech-style reaction the
  player's own character just had (moodle/fire/weapon trigger - see
  `MOODLE_TRIGGERS` in `AIRadioHunt.lua`). Framed to the LLM as genuinely
  the player's own voice overheard through an open mic, **not** ambiguous
  ambient noise of unknown origin - it's clearly them, just not said to Mara
  on purpose.
- `"near"` - proximity crossed into the `NEAR` tier. Mara actually spots the
  player visually for the first time (not just a felt sense) - `Lua`'s
  `findSpottedItem` picks one real, visually-obvious equipped item (a
  wielded weapon, or a non-accessory piece of worn clothing - see the
  curated `VISIBLE_BODY_LOCATIONS` table) and passes it as
  `context.spottedItem`, so she can say something like "I can see someone
  wearing a hat" - always real game data, never guessed by the LLM.
- `"very_near"` - proximity crossed into `VERY_NEAR` (15 tiles). She's
  decided, right then, that she has to leave - the reply here is actually
  **note text** (`persona.notePrompt`/`SHARED_NOTE_PROMPT`), not spoken
  dialogue, and is never shown to the player. `HuntState.spawnLeaveItems`
  uses it to spawn the reward + note at the hunt's target square
  immediately, well before the player physically arrives - see "Item
  spawning must happen server-side" below.
- `"found"` - the player reached the exact square. The reward/note are
  already sitting there (spawned earlier, at `very_near`) - this is just
  the short spoken reveal (`persona.revealPrompt`/`SHARED_REVEAL_PROMPT`):
  why she had to leave, and regret at not meeting face to face.
  `HuntState.completeHunt` marks the hunt done and may advance the chain.

`FAR` is deliberately **not** one of these: Mara has no real way to sense
distance from that far out, so it shows a fixed local line
(`Config.NoiseReplyText`) with no LLM call and no Bridge round trip at all -
see `onPlayerUpdate` in `AIRadioHunt.lua`.

Both `very_near` and `found` are now plain-text completions, same as every
other kind (no JSON/structured-output request to Ollama at all) - splitting
note-writing and the spoken reveal into two separate, differently-timed
calls removed the need for a single call to return two different pieces of
content at once. `Bridge.pollResponse()` still returns the whole decoded
`{id, reply}` table rather than just the reply string (unlike DispatchAI's
version), mostly so `AIRadioHunt.lua`'s `onTick` can branch on
`pendingRequestKind` (tracked client-side, not part of the wire payload) to
know how to interpret a given reply.

## Filepath where the mod is developed

`mod/AIRadioHunt` in this repo is the source of truth, same Build-42
versioned-folder structure as DispatchAI (`mod/AIRadioHunt/mod.info` +
`mod/AIRadioHunt/42/{mod.info,media/...}` - see DispatchAI's dev notes for
why the `42/` folder is required).

Deploy with a real copy, **not a symlink** - a symlinked mods folder does
not reliably show up in PZ's mod list (confirmed for DispatchAI on
42.20.4), so this mod follows the same real-copy convention:

```
rsync -a --delete mod/AIRadioHunt/ ~/Zomboid/mods/AIRadioHunt/
```

## The target squares

`mod/AIRadioHunt/42/media/lua/client/AIRadioHunt/Config.lua`'s
`Config.Hunts[n].targetX/targetY/targetZ` (`6021, 5364, 0` for Mara;
`6119, 5257, 0` for Jonah) are real occupation spawn-point squares inside
houses in Riverside, pulled directly from the installed game's own
`maps/Riverside, KY/spawnpoints.lua` (`poor_houses`/`police_station`
entries) rather than picked by hand - spawn points are always valid,
loaded, walkable interior tiles, so both are guaranteed good without
needing to hand-verify a square in-game first. If you want a different
location later, the same trick works for any town: check that town's own
`maps/<Town>/spawnpoints.lua` in the installed game and reuse one of its
coordinates rather than guessing. No item is pre-spawned at either square -
finding a survivor is purely a matter of the player's proximity tier
reaching `SAME_SQUARE` there (see Proximity.lua); the only physical
evidence left behind is the found-note (see below), not a second
discoverable radio.

Debug helper: type `aicoordinates` in chat (no leading slash - see the
comment on this check in `AIRadioHunt.lua` for why; never forwarded to the
active survivor) to print the *currently active* hunt's persona/channel/
target square into the chat panel, instead of having to look it up in
`Config.lua` every time.

(On macOS, the installed game's own `media/` tree - useful for verifying
any other vanilla API - lives inside the app bundle, not at the Steam
install root: `~/Library/Application Support/Steam/steamapps/common/
ProjectZomboid/Project Zomboid.app/Contents/Java/media`.)

## Item spawning must happen server-side

Even in a Host game (embedded server + client, same process), client and
server Lua run as **separate states with separate object graphs**. Every
vanilla example of adding an item to a player's inventory or a world square
lives under `media/lua/server/`, and inventory adds additionally call
`sendAddItemToContainer(container, item)` right after `AddItem` (confirmed
pervasively - e.g. `server/Fishing/BuildingObjects/FishingNet.lua`,
`server/ClientCommands.lua`). An item added purely client-side (e.g. via
`player:getInventory():AddItem(...)` called from `media/lua/client/`)
exists only in that client's own local snapshot - the server never actually
owns it, so any action requiring server validation (equip, drop, pick up,
read a note) silently fails or gets reverted.

This bit the mod directly: an earlier version called `AddItem`/
`AddWorldInventoryItem` straight from client-side `HuntState.lua`, which
added the starting radio/note and the found-reward/note to the UI, but none
of them could actually be equipped, dropped, picked up, or read - because
none of it was real as far as the server was concerned.

Fix: `mod/AIRadioHunt/42/media/lua/server/AIRadioHunt/ServerCommands.lua`
is a real server-side script (`if isClient() then return end` isn't even
needed - PZ only loads `media/lua/server/` on the server, `media/lua/client/`
on the client) that does the actual `AddItem`/`sendAddItemToContainer`/
`AddWorldInventoryItem` calls, registered against
`Events.OnClientCommand` - the standard vanilla client->server RPC pattern
(see `server/ClientCommands.lua`'s own dispatcher for another example of
the same mechanism; this mod adds its own independent handler rather than
piggybacking on vanilla's `Commands` table). `HuntState.lua`'s
`ensureStartingItems`/`spawnLeaveItems` now just call
`sendClientCommand(player, "AIRadioHunt", "<command>", args)` with plain
data (item type strings, note text, channel numbers) - never a `Config`
reference, since the server-side script runs in a separate Lua state that
never loaded the client's `AIRadioHunt/Config.lua` and can't see
`AIRadioHunt.Config` at all.

## The note item

`ServerCommands.lua`'s `spawnFoundItems` command spawns `Config.NoteItem`
(`Base.Notepad` by default, passed in via `args` from
`HuntState.spawnLeaveItems`) and writes the note into it via real vanilla
`InventoryItem` methods - `item:addPage(1, text)`, `item:setName(...)`,
`item:setCustomName(true)`, `item:setLockedBy("AIRadioHunt")`. Setting
`LockedBy` to a sentinel that will never equal a real player's username
forces vanilla's own inventory context menu to always offer **"Read Note"**
(never "Write Note"), so no custom UI or context-menu hook is needed -
confirmed against `media/lua/client/ISUI/ISInventoryPaneContextMenu.lua`'s
own notebook-writing flow in the installed game. Both items spawn at the
hunt's own `targetX/Y/Z` (passed as `args.x/y/z`, resolved server-side via
`getCell():getGridSquare(...)`) - not the player's current square - since
this now happens at `VERY_NEAR` range, up to 15 tiles before they actually
arrive.

**Item naming.** The starting torn note (`HuntState.ensureStartingItems`) is
always titled `Config.StartingNoteTitle` ("Mara's letter") - it's onboarding
for `Config.Hunts[1]` specifically, always from Mara regardless of how many
hunts follow. The found-note is titled `"<personaName>'s notes to
<player name>"` (e.g. "Mara's notes to Jane Doe") - the player's real
character name, not their Steam username, via
`player:getDescriptor():getForename()/getSurname()` (confirmed against
`client/ISUI/PlayerStats/ISPlayerStatsUI.lua`'s own usage) - `getDescriptor`
lives on the character itself, so it works from server-side Lua the same
way it does client-side.

The note's text is the companion's `kind:"very_near"` note-writing response
**plus** a fixed postscript appended in `HuntState.spawnLeaveItems`
(`nextFrequencyPostscript`) naming the completed hunt's `nextChannel`
(84.0 MHz for Mara, pointing at Jonah; omitted entirely for the last hunt in
the chain, which has `nextChannel = nil`). The frequency is deliberately
never left to the LLM to write itself: it's game truth (something the next
hunt actually gates on), not a real conversation event, so it's appended in
Lua the same way raw coordinates are kept out of `Context.build` entirely -
the LLM only ever sees/writes what it's actually told.

**Note-writing and the spoken reveal are two separate calls, at two
different moments** - originally this was one structured `{reply, note}`
JSON completion at the moment the player arrived. Per direct user feedback,
it's now split: `kind:"very_near"` (`SHARED_NOTE_PROMPT`) writes the note
and spawns it ahead of arrival, entirely silently (no chat line); later,
`kind:"found"` (`SHARED_REVEAL_PROMPT`) generates just the short spoken "I
had to go" line once the player actually reaches the square. This also
removed the only place in this mod that asked Ollama for JSON-structured
output - both are plain-text completions now, same as every other kind (the
`format: "json"` request param and its defensive parsing fallback were
removed from `companion/index.js` entirely, no longer needed).

**Survivors may now name their city, nothing finer.** Every persona's
location-ignorance rule previously banned any place name outright. Per
direct user feedback, this was loosened by exactly one fact: each
`Config.Hunts` entry now has a `city` field (`"Riverside"` for all five
hunts currently, since they're all real spawnpoints on the same loaded
map), threaded through unchanged - `Context.build` reads it off the active
hunt, the companion's `baseMessages` turns it into a plain system message
("You're currently in/near Riverside..."), and every `systemPrompt`
explicitly permits stating it if directly asked. Real coordinates, street
names, landmarks, and distance/direction are all still off-limits exactly
as before - this is Lua handing over one specific fact, not the model
deciding what's safe to reveal.

**Grounding the LLM-written half of the note** - the note prompt alone
wasn't enough in testing: on a fresh character with zero day-summaries and
only two real player messages, `llama3.2:3b` still invented "I've been
hiding for 7 days" and claimed the player had repeatedly promised to come
for her, neither of which happened (checked directly against that
character's `memory-<id>.json`). The prompt's "only reference what really
happened" instruction is not enforced anywhere in code, and this model
doesn't reliably follow it. Partial mitigation in `callOllama`'s
`kind === 'found'` branch: when `dailySummaries.length === 0`, an extra
system message explicitly states there's no history before today and bans
stating a specific day/hour count unless it was actually given. This isn't
a full fix (nothing stops other kinds of invention, like an imagined
promise) - if this keeps happening, the next lever to pull is a
better-instruction-following model, not more prompt text.

**A concrete example in the prompt gets copied verbatim, even when false.**
An earlier version of `SHARED_NOTE_PROMPT` illustrated "reference something
real" with a worked example: *"if they offered medicine and disinfecting
wipes, thank them specifically for offering medicine and disinfecting
wipes."* In testing, both Mara's and Jonah's notes thanked the player for
"medicine and disinfecting wipes" verbatim - on characters where the player
never said any such thing in that persona's own conversation. Since
`notePrompt` is shared across every persona (`SHARED_NOTE_PROMPT`), this
wasn't confined to one character - Jonah's note additionally confabulated
"like Mara said she would," pulling in the persona-grounding system message
(which does mention Mara by name) to rationalize an item that was never
actually promised to Jonah, or even real to begin with. Concrete
illustrative examples are exactly what a small model latches onto and
imitates literally instead of treating as a template - the fix was to
remove the concrete item example entirely, replacing it with an explicit
two-step instruction (re-read the real message history first, then quote
only what's genuinely found there) and an express ban on substituting any
invented detail when nothing specific is present.

**The reveal's "asterisk is never the whole reply" rule needed a code-level
backstop, not just prompt wording.** `SHARED_REVEAL_PROMPT` already states
explicitly that an asterisk action can never be the entire reply - it must
always be followed by real spoken words - and the model still violated this
twice independently (Jonah: `"*I'm not here anymore*"`; later Mara: `"*I'm
nowhere to be seen, only my radio remains*"`), both times with nothing
outside the asterisks. Since the same explicit instruction failed twice on
two different personas, `callOllama`'s `kind === 'found'` branch now checks
the raw reply with `isAsteriskOnlyReply` (strips all `*...*` spans and
checks whether anything real is left) and, if it's empty, retries once with
the model's own bad reply appended to context plus a direct correction
asking for the missing spoken line. Same lesson as the note-example bug
above: for a 3B model, a known failure shape is worth catching in code
rather than trusting a prompt rule to hold indefinitely.

## The channel gate + starting items

Earlier versions of this slice treated *any* switched-on two-way radio as
pre-tuned to the active survivor. It's now gated on the radio's actual
tuned channel: `isTunedToChannel` in `AIRadioHunt.lua` additionally
requires `device:getChannel()` (real vanilla `DeviceData` method, raw units
- divide by 1000 for the MHz value shown in the in-game radio UI, confirmed
against `RadioCom/RadioWindowModules/RWMGeneral.lua`'s own frequency
display) to be within `Config.ChannelTolerance` of whichever hunt is
currently active (`HuntState.getActiveHunt(player).channel` - `76000` for
Mara, `84000` for Jonah, and so on up the chain). Carrying an on, two-way
radio tuned to any other station no longer triggers anything.

**Every hunt channel is on the real 0.2 MHz tuning grid, inside 75-150 MHz,
clear of every real vanilla station.** Confirmed against the installed
game's own files, not guessed: the in-game radio UI's preset slider
(`RadioCom/RadioWindowModules/RWMChannel.lua`, via
`ISUIRadio/ISSliderPanel.lua:setCurrentValue`) rounds to a `0.2` MHz step,
so every `Config.Hunts[...].channel`/`nextChannel` is a multiple of `200`
raw units - reachable by a player actually turning the in-game dial, not
just by typing an arbitrary number. All five are also kept inside
`75000-150000` (75.0-150.0 MHz) and several MHz clear of every real vanilla
broadcast in that band (`media/radio/RadioData.xml`: Hitz FM 89.4, Civilian
Radio 91.2, LBMW 93.2, USR 94.2, Classified M1A1 95.0, NNR Radio 98.0,
KnoxTalk Radio 101.2, Unknown Frequency 107.6) - so scanning around the dial
never crosses actual vanilla station content.

`HuntState.ensureStartingItems` (idempotent per character via the same
ModData pattern as the rest of `HuntState.lua`) gives every brand-new
character `Config.StartingRadioItem` (`Base.WalkieTalkie3`, "Premium Tech.
Walkie Talkie") already switched on via `setIsTurnedOn(true)`, tuned to a
deliberately-wrong channel (`Config.StartingRadioInitialChannel`, 250 MHz -
well outside the 75-150 MHz band above) via `setChannel(...)`, plus a note
(`Config.StartingNoteItem`, same `addPage`/`setLockedBy` mechanism as the
found-note) hinting at the real frequency. `WalkieTalkie3` is specifically
picked because its real `MinChannel`/`MaxChannel` (`25000`/`300000`,
confirmed in the installed game's `scripts/generated/items/radio.txt`)
comfortably brackets the whole 75-150 MHz hunt-channel band. If you swap
`StartingRadioItem` for a different radio later, check that item's own
`MinChannel`/`MaxChannel` in `radio.txt` still brackets whichever hunt's
`channel` you're using - not every radio item can reach every frequency
(e.g. `WalkieTalkie1`/`2`/`WalkieTalkieMakeShift` can't go below 50-75 MHz
at all).

**`ensureStartingItems` retries until the item is actually confirmed
present - a fixed delay wasn't enough.** An earlier version called it
directly from `Events.OnCreatePlayer` (where you'd naturally reach for it -
confirmed real usage in vanilla: `ISUI/PlayerData/ISPlayerData.lua`,
`Tutorial/TutorialSetup.lua`). In testing, the resulting
`sendClientCommand` call completed with no Lua-level error, but the
underlying packet never actually reached the server - confirmed by
checking the server-side debug log directly: zero `OnClientCommand`
traffic for it, ever, across multiple fresh characters. Moving the call to
fire from a regular `OnPlayerUpdate` tick instead (every other
`sendClientCommand` in this mod, sent from ordinary ticks once the player
is fully in-game, always showed up reliably) turned out to still be too
early on its own - even tick 1 of a brand-new connection's own
`OnPlayerUpdate` failed the same way. There's no known event/flag that
reliably signals "this player's `ClientCommand` channel is ready," so
guessing a single safe delay isn't robust.

Fix: `ensureStartingItems` now retries every `STARTING_ITEMS_RETRY_TICKS`
(~5 real seconds) and only marks itself done once `Base.WalkieTalkie3` is
*actually confirmed present* in the inventory (`playerHasItemType`, using
the real vanilla `ItemContainer:contains(shortType)` - confirmed against
`client/ContextMenuCode.lua`'s own usage; note it wants the short type,
module prefix stripped, not the full type string) - not merely "we
attempted a send once." This is also a **self-healing migration** for any
character whose `startingItemsGiven` flag got stuck `true` by the older,
non-verifying version of this function (marked "given" the instant a send
was attempted, regardless of whether it actually arrived) - the function
now detects that mismatch (flag true, item absent) and resumes retrying
rather than requiring a brand-new character to recover.

## Narration style: third person in asterisks, first person outside

Mara's `systemPrompt` allows a brief action/emotion description in asterisks
before her spoken line (a radio-drama stage direction, e.g.
`*Mara's voice cracks* Thank you...`) but requires it stay in third person
(by name or "she/her") - never "I/my/myself" inside the asterisks, even
though the actual spoken dialogue outside them is naturally first person.
This exists because testing surfaced exactly the wrong output -
`*my voice cracks with emotion...*` - which reads as the character
narrating herself in first person, confusing who's supposedly "speaking" the
stage direction versus the dialogue. An earlier version of this prompt
instead banned stage directions/parentheticals outright (matching
DispatchAI's own systemPrompt) - `llama3.2:3b` didn't reliably follow that
either, so this prompt now accommodates the style it actually produces and
just fixes the person/perspective within it, rather than fighting the
model on suppressing it entirely.

**Two more pronoun/formatting bugs found in testing, both fixed the same
way (prompt wording, not code-level filtering):**
- The player was described as "they/them" throughout the instructional
  text (a gender-neutral convention for referring to them internally), and
  that habit leaked directly into spoken dialogue - a `"near"` reply said
  "Oh my God, they're real" instead of "you're real", despite Mara
  obviously speaking directly *to* the player. Fixed by adding an explicit
  rule to both `systemPrompt`s: the player is always "you" in actual spoken
  dialogue, never "they/them", regardless of how the surrounding
  instructions phrase it.
- A `"found"` reveal once came back as just `*I'm not here anymore*` -
  first person inside the asterisks (already banned) AND no actual spoken
  line outside them at all, so the whole reply was just a stage direction
  with nothing said. Fixed by adding an explicit rule that the asterisk
  part is never a complete reply by itself - real spoken words must always
  follow it.

## Survivors aren't physically at their target square

The `"found"` trigger (`SAME_SQUARE`) does **not** mean the player caught
the current survivor in person - she'd already had to leave before they
arrived, and the `reply` is her explaining that live over the radio with a
grounded excuse, not "you found me." This was a deliberate reframing: the
design doc's own "the walkie-talkie IS the character" principle (see the
design doc's section 2) never actually required a literal physical NPC to
be standing there, so narrating her as caught in person was more presence
than the mod ever delivers - what's real is that the *location* was found
and she'd moved on, having left the reward/note behind (spawned earlier, at
`VERY_NEAR` - see "Item spawning must happen server-side" above). This also
gives the `nextChannel` postscript (see "The note item" above) a coherent
in-fiction reason to exist: she's still out there somewhere, reachable on
the next frequency - which is now a literal next hunt in `Config.Hunts`,
not just a narrative gesture.

## The single in-flight request guard

DispatchAI's `Bridge` only ever tracks one `pendingRequestId` at a time, and
accepts that a same-tick trigger collision silently drops one of them (an
accepted rough edge there, since it only affects rare simultaneous moodle
triggers). This mod's `start`/`near`/`very_near`/`found` triggers fire on
their own from `Events.OnPlayerUpdate` far more often, so `AIRadioHunt.lua`
explicitly waits for `pendingRequestId` to clear before sending another
ambient request - otherwise the opening "Hello? Is anyone there?" line
would almost always get silently overwritten by the very next tick's
proximity check before the companion's (much slower) Ollama round trip
ever completed. Player-typed chat intentionally does **not** wait, matching
DispatchAI's existing documented behavior (no rate-limit on typed chat).

## Host mode has two separate mod lists - both need the mod added

Found via a real Windows Workshop-install test that otherwise looked
correctly set up (mod loaded client-side, printed its own "mod loaded, chat
hook installed" line, appeared enabled in the main menu's Mods screen) but
never responded to anything - not even the synchronous `aicoordinates` debug
command. The actual cause was in the **server**'s own debug log:
`required mod "AIRadioHunt" not found`.

Host mode runs its own separate embedded server with its own independent
mod configuration (`Mods=`/`WorkshopItems=` in the selected server settings
preset - see "The channel gate + starting items" above, and the real UI
navigation confirmed in `README.md`'s install steps: **Host -> Manage
settings... -> Edit**). That editor has **two separate pages** - a "Mods"
page and a "Steam Workshop" page - and using **"Choose Mods..."** to enable
the mod does not reliably populate both. If the mod ends up listed on the
Mods page but missing from the Steam Workshop page, the server can't
resolve where to actually find/download its content, even though the
client-side game happily loads its own copy and everything else *looks*
enabled.

Fix: on the Steam Workshop page specifically, add it via **"Add an
installed Workshop item to the list"**, or manually by ID if it doesn't
show up in that picker:
- Mod ID: `AIRadioHunt`
- Workshop Item ID: `3809785412`

## Testing

**PZ doesn't hot-reload mod Lua, server scripts included** - after
`rsync`-ing an updated mod, fully quit and relaunch the game (not just exit
to the main menu and re-host) before testing, especially after any change
under `media/lua/server/`. Also: a character created *before*
`ServerCommands.lua` existed already has `startingItemsGiven = true` stuck
in its save (and whatever broken, un-interactable items it got from the
old client-only code) - `ensureStartingItems` is idempotent and won't retry
for that character. Test with a **new** character, not by reloading an
old one.

1. `rsync -a --delete mod/AIRadioHunt/ ~/Zomboid/mods/AIRadioHunt/`.
2. Start the companion (`cd companion && npm start`, or
   `Start AIRadioHunt.command`/`.bat` if built) - it should print
   `AIRadioHunt companion watching: .../Zomboid/Lua/AIRadioHunt_request.json`.
   **Make sure only one companion process is running** (same corruption
   risk as DispatchAI - see its dev notes).
3. Confirm Ollama is running with the configured model pulled
   (`ollama pull llama3.2:3b`).
4. Host (not Solo) a game with a **new** character (starting items are only
   given via `Events.OnCreatePlayer`, i.e. character creation, not on
   loading an existing one) - confirm the starting radio + note appear in
   inventory immediately. Open the radio and tune it to **76.0 MHz**
   (`Config.Hunts[1].channel`) - confirm Mara keys in unprompted within a
   second or two of the channel actually landing on 25.
5. Type `aicoordinates` in chat (no leading slash) - confirm it prints the
   active hunt's persona/channel/target square locally and is never
   forwarded to the companion (check the companion's terminal shows no new
   request for it).
6. Walk toward that target square from beyond 200 tiles out - confirm the
   fixed `Config.NoiseReplyText` line shows with **no** new entry in the
   companion's terminal (no LLM call at all) while still `FAR`.
7. Cross into `NEAR` (within 60 tiles) - confirm a `kind:"near"` request
   shows up in the companion's terminal and Mara's reply references an
   actual equipped item of yours (a wielded weapon if you're holding one,
   otherwise a real piece of worn clothing - check the request's
   `context.spottedItem` in the companion log matches what you're actually
   wearing/carrying).
8. Cross into `VERY_NEAR` (within 15 tiles) - confirm a `kind:"very_near"`
   request fires in the companion's terminal, but **nothing shows in chat
   or as an overlay** (this is silent by design - the note is being written
   and spawned ahead of your arrival, not revealed yet). Walk to the exact
   target square and confirm the reward item and a note ("Mara's Note") are
   already sitting there waiting, before you've triggered anything else.
9. Trigger a real conditional-speech reaction (e.g. let Hungry/Thirst/Pain
   rise, or empty a ranged weapon's clip) - confirm a grey "player" bubble
   shows your character's own muttered phrase immediately, and a `kind:
   "sound"` request shows up in the companion's terminal, with Mara
   reacting to it as clearly your own voice (not mysterious ambient noise).
10. Step onto the exact target square - confirm the `found` flow fires
    once, the overlay bubble shows in the gold "found" style, and Mara's
    spoken line explains why she had to leave and expresses regret at not
    meeting face to face (not "you found me" - and it doesn't need to
    mention leaving something behind again, since you can already see it
    from step 8).
11. Check any asterisk-wrapped action text in her replies uses third person
    ("*Mara's voice...*"/"*she...*"), never "*my voice...*"/"*I...*".
12. Right-click the notepad, confirm it offers **"Read Note"** (not "Write
    Note") **immediately**, even before picking it up (the other bug fixed
    alongside item-spawning: configure the item's name/pages *before* the
    first sync call, not after), and shows the generated note text ending
    with the fixed "try 84.0MHz next" postscript regardless of what the LLM
    wrote.
13. **Chaining**: retune your radio to **84.0 MHz** (`Config.Hunts[2].channel`)
    - confirm Jonah keys in unprompted (a distinct persona/name from Mara,
      not a repeat of her opening line), `aicoordinates` now reports
      `Jonah` and his own target square (`6119, 5257, 0`), and the
      companion creates a *new* memory file (`memory-<id>-jonah.json`) -
      check `memory-<id>-mara.json` still has Mara's full conversation
      untouched, proving the two survivors' histories didn't merge. Repeat
      steps 6-12 for Jonah, then again for Ellis (112.0 MHz), Nadia
      (128.0 MHz), and Reyes (144.0 MHz - last in the chain, so his own note
      has no postscript) - each should feel like a distinct personality
      (Ellis guarded, Nadia chatty and warm, Reyes clipped and transactional)
      while still behaving mechanically identically end-to-end.
14. Save and reload, re-approach a completed hunt's target square - confirm
    nothing re-spawns and the found dialogue doesn't repeat (ModData
    idempotency flags survive save/reload).
15. Watch the companion's terminal output - same diagnostic value as
    DispatchAI's: logs every request/reply including the raw completion
    text, useful for debugging "nothing shows up" issues for any kind.

## Known rough edges / next steps

- **Starting items only reach brand-new characters.** `Events.OnCreatePlayer`
  doesn't fire for a character that already existed before this feature was
  added (or before the mod was enabled) - such a character never gets the
  auto-given radio/note. Workaround for testing on an existing character:
  if they're already carrying any switched-on two-way radio, just open it
  and retune it to 76.0 MHz by hand - the channel check doesn't care how
  the radio got there.
- **Five hardcoded survivors/locations, still a fixed linear chain** - no
  procedural placement, no relocation, no remaining un-tried archetypes
  (liar, coward, trickster, hostile, mysterious from the design doc), no
  survivor network (survivors don't yet know about or reference each other
  beyond the "you found the previous one's note" grounding message). This
  slice exists to prove the mechanics, not to be the finished mode.
- **`Config.RewardItem` (`Base.Bandage`) is a placeholder** - the design
  doc envisions richer, escalating rewards (vehicle keys, safehouse
  locations, etc.); swap this out once there's more than one hunt to
  reward.
- No relocation means the "heat"/cat-and-mouse system from the design doc
  isn't implemented at all - `Proximity.lua`'s tiers are purely
  informational (dialogue flavor + the found trigger), not something Mara
  ever reacts to by moving.
- Same companion limitations as DispatchAI apply here unchanged: no
  cooldown/rate-limit on typed chat spam, and a small local model can get
  "anchored" repeating a prior short reply verbatim (see DispatchAI's dev
  notes for the full writeup) - no code-level retry was added here either,
  for the same reasoning (silently re-rolling model output hides what
  actually happened).
