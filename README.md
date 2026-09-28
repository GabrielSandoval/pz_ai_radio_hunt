# AI Radio Hunt

AI Radio Hunt turns your Project Zomboid radio into a scavenger hunt.
Somewhere out there, a survivor has a walkie-talkie of her own. Talk to
her, listen for how close you're getting, and track down where she's
hiding, powered by an AI model running locally on your own PC. Reach her,
and the hunt pays off with a reward and a handwritten note - written from
your real conversation, never invented.

> This is a vertical-slice build: a short fixed chain of survivors, fixed
> locations, no relocation yet. See `DEVELOPMENT.md` for what's still ahead.

## How to Install

No coding involved - just two things, once, and you're ready:

**1. Set up the Companion app.** Download it, unzip it, run it. It handles
installing everything else (the AI engine, and the AI model) for you
automatically.

**2. Install the mod.** Subscribe on the Workshop, turn it on, hit play.

### 1. Set up the Companion app

1. Download the `.zip` for your OS from the
   [**Releases page**](https://github.com/GabrielSandoval/pz_ai_radio_hunt/releases/latest)
   (`AIRadioHunt-Companion-Windows.zip` or `AIRadioHunt-Companion-macOS.zip`),
   then unzip it.
2. Double-click the file for your system:
   **Windows:** `Start AIRadioHunt.bat` &nbsp;|&nbsp; **macOS:** `Start AIRadioHunt.command`
3. A text window pops up - **leave it open** while you play (minimize it,
   don't close it). The first time you run it, it'll automatically walk you
   through installing the free local AI engine it needs and downloading the
   AI model - just follow what it says on screen, no commands to type.

<details>
<summary><i>macOS says it can't be opened / more detail on first-time setup</i></summary>

> If macOS refuses to open `Start AIRadioHunt.command` ("unidentified
> developer"), right-click (or Control-click) it instead of double-clicking,
> choose **Open**, then **Open** again on the popup - only needed once.
>
> On first run, the Companion window checks whether **Ollama** (the free
> local AI engine) is installed. If it isn't, it opens Ollama's download
> page for you automatically - install it like any normal app (Next ->
> Next -> Finish), open it once, then go back to the Companion window: it
> detects Ollama and downloads the AI model itself (one-time, a few minutes
> depending on your connection). No terminal, no commands.

</details>

### 2. Install the mod

1. Subscribe to **AI Radio Hunt** on the Steam Workshop.
2. Launch Project Zomboid -> **Mods** -> enable **AI Radio Hunt**.
3. **Host** -> **Manage settings...** -> pick/edit your settings preset ->
   **Choose Mods...** -> enable **AI Radio Hunt** there too -> **NEXT**.
4. **Important:** in the settings editor's left-hand list, check **both**
   the **Mods** page and the **Steam Workshop** page - confirm **AI Radio
   Hunt** shows up on both (the step above doesn't always add it to the
   Workshop page automatically). If it's missing from the Steam Workshop
   page, add it yourself using **"Add an installed Workshop item to the
   list"** (or by ID, if needed - see below), then **SAVE**.
5. **START** (restart first if it's an existing save).

<details>
<summary><i>Why enable it twice, and why Host instead of Solo?</i></summary>

> Project Zomboid's chat window - how survivors' replies actually reach you
> - only exists in Host or multiplayer, not Solo. Host still plays exactly
> like Solo (still just you), it just needs to be started that way.
>
> Host mode also runs its own separate built-in server with its own
> independent mod list, which doesn't automatically match whatever's
> checked in the main menu's Mods screen - so it needs enabling in both
> places, or the mod won't actually load.
>
> There are actually **two separate lists** inside the server settings
> editor itself - a "Mods" page and a "Steam Workshop" page - and enabling
> it via "Choose Mods..." doesn't reliably populate both. If you skip this,
> the server log will say `required mod "AIRadioHunt" not found`, and
> nothing will work even though the mod appears enabled everywhere else. If
> you ever need to add it manually by ID instead of picking it from a list:
> - Mod ID: `AIRadioHunt`
> - Workshop Item ID: `3809785412`

</details>

That's it - as long as the Companion window is open, you're ready to play.
See "How to use it in-game" below for what happens next.

## How to use it in-game

Every new character starts with a working two-way radio (already switched
on) and a torn note in their inventory:

> *"please... if anyone out there can hear this... tune in to Channel
> [X]MHz."*

The frequency is different every playthrough - the note itself always has
the real number to dial in. Open the radio (right-click it -> **Set
Frequency**, or however your radio UI exposes it) and dial in whatever
channel the note gives you. Any working two-way radio -
walkie talkie or ManPack, not a listen-only portable radio or a stationary
HAM set - switched on and tuned to that exact channel counts, whether it's
your starting radio or one you find later. It can be in your hand, worn, or
just sitting in a bag or pocket - it doesn't need to be equipped, just
carried, on, and on the right channel.

Once you're in a Host game with the mod enabled, the companion app running,
and a radio like that on you, the survivor will key in on her own within a
few seconds: *"Hello? Is anyone there?"*

Type back like you'd text a friend, and she'll reply in character. She has
no real way to sense how far away you are at long range, so unexplained
static plays over the line while you're still far out. Once you're getting
near, she'll actually catch sight of you for the first time - she might
mention something you're visibly wearing or carrying. Keep closing the
distance, and the hunt builds toward its payoff: a reward and a handwritten
note, grounded in what you actually talked about, waiting for you at the
exact spot.

Real, audible reactions your own character has - pain, hunger, cold, a
jammed weapon, and the like - can come through too, the same way they would
if you were actually holding an open mic: she clearly hears your own voice
come through, even if you didn't mean to say anything to her.

When you finally reach the exact spot, the hunt reaches its conclusion -
what happens plays out live over the radio. The note - written from your
actual conversation, not made up, and hinting at the next frequency to try
- is there for you to find and read.

A couple of things worth knowing:
- The floating line above your character only shows if your radio's volume
  is turned up - if it's muted, she still hears and replies to you, you
  just won't see the floating bubble (it still shows in chat either way).
- Commands (anything starting with `/`) are ignored and won't trigger a
  reply.
- She keeps replies short - a sentence or two, like a real radio exchange.
