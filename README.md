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

Don't worry - there's no coding involved. You're just installing two normal
programs (like installing any app on your computer) and turning on a mod.
Do these in order, once, and you're set up for good.

### Step 1 - Download and run the AI Radio Hunt Companion

This is a small program that connects the mod to a free, local AI engine
called **Ollama** (the "brain" the survivors use to talk to you - it runs
entirely on your own computer, nothing is sent over the internet). It has
to be running in the background every time you play. It also takes care of
installing/setting up Ollama for you - you don't need to do that separately.

1. Go to the [**Companion downloads page**](https://github.com/GabrielSandoval/pz_ai_radio_hunt/releases/latest)
   and download the `.zip` for your operating system (`AIRadioHunt-Companion-Windows.zip`
   or `AIRadioHunt-Companion-macOS.zip`).
2. Unzip the file you downloaded.
3. Open that folder and double-click the file for your system:
   - **Windows:** `Start AIRadioHunt.bat`
   - **macOS:** `Start AIRadioHunt.command`
4. A plain text window will pop up and stay open - **leave it open** the
   whole time you're playing. It's working correctly as long as that window
   stays open; if you close it, survivors will stop being able to reply. You
   can minimize it, just don't close it.
5. **If this is your first time**, that window will notice Ollama isn't
   installed yet and automatically open its download page in your browser.
   Install it like any other program (Next -> Next -> Finish) and open it
   once - you'll see a small llama icon appear in your system tray (Windows)
   or menu bar (Mac). Then just go back to the Companion window: it'll
   detect Ollama is ready and automatically download the AI model it needs
   (a one-time download, may take a few minutes depending on your internet
   connection) - no commands to type, just wait for it to say the model is
   ready.

> **macOS only:** the first time you double-click `Start AIRadioHunt.command`,
> macOS may say it can't be opened because it's from an unidentified
> developer. If that happens, right-click (or Control-click) the file
> instead of double-clicking, choose **Open**, then click **Open** again on
> the popup - you only need to do this once.

### Step 2 - Install the mod itself

1. Subscribe to **AI Radio Hunt** on the Steam Workshop.
2. Launch Project Zomboid.
3. From the main menu, click **Mods**, find **AI Radio Hunt** in the list,
   and switch it on.
4. From the main menu, click **Host** (not Solo - see below).
5. On the Host Game screen, click **Manage settings...**
6. Pick the settings preset you're about to play with (or create a new one),
   then click **Edit**.
7. A **"Mods used by this server"** window pops up - click **Choose Mods...**,
   find **AI Radio Hunt** in the list, and switch it on there too, then click
   **NEXT**.
8. In the settings editor that opens, check the left-hand list for a
   **Mods** page and a **Steam Workshop** page - confirm **AI Radio Hunt**
   shows up on both (it should have been added automatically by the step
   above). If it's missing from the Steam Workshop page, add it there too
   using **"Add an installed Workshop item to the list."**
9. Click **SAVE**, then back on the Host Game screen, click **START**
   (restarting the game first if this is an existing save, so the mod
   actually turns on).

> **Why do I have to add it twice (Mods screen *and* server settings)?** The
> main menu's **Mods** screen only affects your own game client. **Host**
> mode runs its own separate built-in server behind the scenes, and that
> server keeps its own independent mod list - it does not automatically
> pick up whatever's checked in the main menu. Both need AI Radio Hunt
> enabled, or the mod won't actually load.

> **Why Host and not Solo?** It looks and plays exactly like Solo - you're
> still the only one playing - but Project Zomboid's chat window (which is
> how survivors' replies actually reach you) only exists in Host or
> multiplayer games, not Solo. "Host" is just the setting that turns that
> chat window on.

That's it - as long as Ollama is running and the Companion window is open,
you're ready to play. See "How to use it in-game" below for what happens
next.

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
