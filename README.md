# AI Radio Hunt

**GitHub:** [github.com/GabrielSandoval/pz_ai_radio_hunt](https://github.com/GabrielSandoval/pz_ai_radio_hunt)

**Companion downloads:** [Releases page](https://github.com/GabrielSandoval/pz_ai_radio_hunt/releases/latest)

AI Radio Hunt turns your Project Zomboid radio into a scavenger hunt. Somewhere
out there, a survivor - **Mara** - has a walkie-talkie of her own. Talk to
her, listen for how close you're getting, and track down where she's
hiding, powered by an AI model running locally on your own PC. By the time
you reach the spot, she's already had to move on - but she leaves behind a
reward and a handwritten note.

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
   **Choose Mods...** -> enable **AI Radio Hunt** there too -> **NEXT** ->
   **SAVE**.
4. **START** (restart first if it's an existing save).

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

</details>

That's it - as long as the Companion window is open, you're ready to play.
See "How to use it in-game" below for what happens next.

## How to use it in-game

Every new character starts with a working two-way radio (already switched
on) and a torn note in their inventory:

> *"please... if anyone out there can hear this... tune in to Channel
> 76.0MHz."*

Open the radio (right-click it -> **Set Frequency**, or however your radio
UI exposes it) and dial it to **76.0 MHz**. Any working two-way radio -
walkie talkie or ManPack, not a listen-only portable radio or a stationary
HAM set - switched on and tuned to that exact channel counts, whether it's
your starting radio or one you find later. It can be in your hand, worn, or
just sitting in a bag or pocket - it doesn't need to be equipped, just
carried, on, and on the right channel.

Once you're in a Host game with the mod enabled, the companion app running,
and a radio like that on you, Mara will key in on her own within a few
seconds: *"Hello? Is anyone there?"*

Type back like you'd text a friend, and she'll reply in character. She has
no real way to sense how far away you are at long range, so unexplained
static plays over the line while you're still far out. Once you're getting
near, she'll actually catch sight of you for the first time - she might
mention something you're visibly wearing or carrying. Once you're very
close, she quietly decides she can't stay any longer - you won't hear
anything about it yet, but a reward and a handwritten note are already
waiting at the spot by the time you actually get there.

Real, audible reactions your own character has - pain, hunger, cold, a
jammed weapon, and the like - can come through too, the same way they would
if you were actually holding an open mic: Mara clearly hears your own voice
come through, even if you didn't mean to say anything to her.

When you finally reach the exact spot, the hunt ends - but she's not there.
That's when she explains why she had to go, live over the radio, before the
line goes quiet. The note - written from your actual conversation, not made
up, and hinting at the next frequency to try - was left behind for you to
find and read.

A couple of things worth knowing:
- The floating line above your character only shows if your radio's volume
  is turned up - if it's muted, Mara still hears and replies to you, you
  just won't see the floating bubble (it still shows in chat either way).
- Commands (anything starting with `/`) are ignored and won't trigger a
  reply.
- Mara keeps replies short - a sentence or two, like a real radio exchange.
