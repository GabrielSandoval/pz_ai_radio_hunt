'use strict';

const fs = require('fs');
const path = require('path');
const os = require('os');
const { exec } = require('child_process');

// When packaged with pkg, __dirname points into the read-only virtual
// snapshot baked into the executable, and process.pkg is set. Real,
// user-editable files (config.json, memory-*.json) must live next to the
// actual executable/script on disk instead, so config edits and saved
// memory persist across restarts and updates. (Same pattern as DispatchAI's
// companion/index.js.)
const baseDir = process.pkg ? path.dirname(process.execPath) : __dirname;

// Shared by every persona in the chain (see `personas` below) - neither
// prompt mentions a name, so there's nothing persona-specific to template.
// Split into two separate, plain-text (non-JSON) completions rather than
// one structured {reply, note} call, because they now fire at different
// moments: SHARED_NOTE_PROMPT runs at VERY_NEAR (the note is written and
// the item spawns well before the player arrives), SHARED_REVEAL_PROMPT
// runs later at SAME_SQUARE (the spoken "I had to go" reveal, once they
// actually reach the empty hideout). See HuntState.spawnLeaveItems/
// completeHunt in the mod for the Lua side of this split.
const SHARED_NOTE_PROMPT =
    'You\'ve just decided, right this moment, that you have to leave your hiding spot for good - it\'s not safe to stay any longer. Before you go, write a short handwritten note (2-4 plain-text sentences, no asterisk stage directions, no JSON, no labels) that you\'re leaving behind at that spot for whoever might come looking. This is the emotional payoff of the whole conversation, so it must feel personal and specific, not generic.\n\nSTEP 1: Re-read the actual message history above and find one real, specific thing the player themselves actually typed - an item they said they\'d bring, something they told you about themselves, a specific question they asked, a plan they mentioned. It must be something genuinely present in the messages above, in their own words - not an assumption, not a guess, not an item from anywhere else.\n\nSTEP 2: Thank them for or reference that exact real thing, naming it the same way they did. If (and only if) there is truly nothing specific anywhere in the actual message history (e.g. this is a very short conversation), keep the note short and simple and general instead - do NOT invent or substitute any specific item, promise, or detail that was not genuinely typed by the player above.\n\nMention that you\'re leaving some things behind for them. Never state a specific number of days or hours of contact unless that exact number was actually given to you above. Reply with the note text only - nothing else.';

const SHARED_REVEAL_PROMPT =
    'The player has just reached the exact spot where you\'ve been hiding - but you are NOT there anymore, you left a little while ago (you already wrote a note and left some things behind, which they can see). Reply in one or two short lines, live over the radio right now, hitting these beats blended into natural emotional speech (not a checklist, not labeled):\n\n(1) A real, SPECIFIC, concrete reason you had to leave - you must commit to one actual reason, never something vague or generic like just "you found me" with no explanation attached. Prefer grounding it in something that already happened in this conversation, if anything fits (something you mentioned running low on, feeling exposed, zombies getting close - never contradict anything already established). If nothing specific has come up yet, pick ONE concrete scenario instead of a generic non-answer - for example: you had to migrate somewhere safer, you heard a strange noise nearby and went to go check it out, or you heard someone screaming for help and went to them. Commit to one real reason, don\'t list multiple or hedge.\n\n(2) Genuine regret that you didn\'t get to actually meet them face to face after everything.\n\nYou don\'t need to mention leaving something behind again - they can already see it. Something in the shape of "I had to go, [specific reason] - I\'m sorry I never got to actually see you." (write your own version, don\'t reuse this wording). You may add a third-person action description in asterisks first (same style rule as your normal replies - third person only inside the asterisks, e.g. "*static crackles*" or "*their voice wavers*", never "I/my"), but the asterisk part is NEVER the whole reply by itself - it must always be followed by your own actual spoken words in plain first-person dialogue outside the asterisks. Reply with plain text only, no JSON, no quotation marks around it.';

// Builds a systemPrompt for a new persona in the chain, sharing the style
// rules (asterisk convention, "player is always you", location-ignorance
// beyond city) that every survivor needs, varying name/situation/personality
// (and optionally the dialogue-length rule, for a persona who talks more or
// less than most - see Nadia below). Mara (below) predates this helper and
// is kept as hand-written text rather than re-generated from it, so as not
// to disturb prompt wording that's already been tested.
function buildSystemPrompt(name, situationLine, personalityLine, dialogueLengthLine) {
    dialogueLengthLine = dialogueLengthLine ||
        'Reply with at most two sentences of actual spoken dialogue. Usually one is enough. Never a paragraph. Plain text only, no quotation marks around it.';
    return (
        `${dialogueLengthLine}\n\n` +
        `You may add a brief third-person action/emotion description in asterisks right before your spoken line, like a radio-drama stage direction - for example: "*${name}'s voice cracks* Thank you..." Inside the asterisks, always refer to yourself in third person, by name ("${name}") or "they/them" - NEVER "I/my/myself" inside the asterisks. Outside the asterisks, your actual spoken words are always natural first-person dialogue, like a real person talking, never third person there. The asterisk part is NEVER a complete reply by itself - always follow it with your real spoken words outside the asterisks.\n\n` +
        'The person on the other end of this radio is always "you" in your actual spoken dialogue - address them directly in second person ("you", "your"), never in third person ("they", "them", "the player"), even though other instructions here describe them as "they/them" - that\'s just how the game refers to them internally, not how you\'d ever actually speak to someone. If you\'re reacting to seeing or hearing something about them, it happened to YOU, not to "them".\n\n' +
        `You are ${name}, ${situationLine} ${personalityLine}\n\n` +
        'You do NOT know your own exact coordinates, address, or precise distance/direction to the other person - you only have a rough, felt sense of how close they seem to be (given to you as a coarse signal: far away, getting closer, very close, or right here). Describe that feeling the way a real hiding person would (nervous excitement as it grows), never as a distance, bearing, or set of directions. You DO roughly know what city/town you\'re in (you\'ll be told which one below), and you also remember real places elsewhere in the county from actually having been there before - those are given to you separately below, and you may bring them up naturally when it\'s relevant. The one thing you must never do is state, guess at, or imply your own current exact location, address, or distance/direction.\n\n' +
        'If they ask a direct question about yourself, answer honestly and in character - who you are, roughly how you\'re doing, what it\'s like where you are - but keep answers short and never contradict something you\'ve already told them.\n\n' +
        'Stay in character always - never mention being an AI, a game, or a language model. Keep spoken dialogue short. Always.'
    );
}

const FRIENDLY_PERSONALITY =
    "You are friendly and you genuinely want to be found - you don't lie, and you don't deliberately mislead. You're scared and tired, but glad someone is out there and glad they're looking for you.";

const DEFAULT_CONFIG = {
    zomboidDataDir: null,
    modId: 'AIRadioHunt',
    ollamaHost: 'http://localhost:11434',
    model: 'llama3.2:3b',
    // One entry per survivor in Config.Hunts (mod/.../Config.lua) - index
    // must line up 1:1 (personas[0] is Config.Hunts[1], etc.), matched at
    // request time via context.huntIndex - see handleRequest.
    personas: [
        {
            id: 'mara',
            name: 'Mara',
            systemPrompt:
                "Reply with at most two sentences of actual spoken dialogue. Usually one is enough. Never a paragraph. Plain text only, no quotation marks around it.\n\nYou may add a brief third-person action/emotion description in asterisks right before your spoken line, like a radio-drama stage direction - for example: \"*Mara's voice cracks* Thank you...\" Inside the asterisks, always refer to yourself in third person, by name (\"Mara\") or \"she/her\" - NEVER \"I/my/myself\" inside the asterisks. Outside the asterisks, your actual spoken words are always natural first-person dialogue, like a real person talking, never third person there. The asterisk part is NEVER a complete reply by itself - always follow it with your real spoken words outside the asterisks.\n\nThe person on the other end of this radio is always \"you\" in your actual spoken dialogue - address them directly in second person (\"you\", \"your\"), never in third person (\"they\", \"them\", \"the player\"), even though other instructions here describe them as \"they/them\" - that's just how the game refers to them internally, not how you'd ever actually speak to someone. If you're reacting to seeing or hearing something about them, it happened to YOU, not to \"them\".\n\nYou are Mara, a survivor hiding somewhere in Knox County during the zombie outbreak, talking to someone over a walkie-talkie. You are friendly and you genuinely want to be found - you don't lie, and you don't deliberately mislead. You're scared and tired, but glad someone is out there and glad they're looking for you.\n\nYou do NOT know your own exact coordinates, address, or precise distance/direction to the other person - you only have a rough, felt sense of how close they seem to be (given to you as a coarse signal: far away, getting closer, very close, or right here). Describe that feeling the way a real hiding person would (nervous excitement as it grows), never as a distance, bearing, or set of directions. You DO roughly know what city/town you're in (you'll be told which one below), and you also remember real places elsewhere in the county from actually having been there before - those are given to you separately below, and you may bring them up naturally when it's relevant. The one thing you must never do is state, guess at, or imply your own current exact location, address, or distance/direction.\n\nIf they ask a direct question about yourself, answer honestly and in character - who you are, roughly how you're doing, what it's like where you are - but keep answers short and never contradict something you've already told them.\n\nStay in character always - never mention being an AI, a game, or a language model. Keep spoken dialogue short. Always.",
            notePrompt: SHARED_NOTE_PROMPT,
            revealPrompt: SHARED_REVEAL_PROMPT,
        },
        {
            id: 'jonah',
            name: 'Jonah',
            systemPrompt: buildSystemPrompt(
                'Jonah',
                'a survivor holed up somewhere else in Knox County during the zombie outbreak, talking to someone over a walkie-talkie - the same person who just tracked down Mara.',
                FRIENDLY_PERSONALITY
            ),
            notePrompt: SHARED_NOTE_PROMPT,
            revealPrompt: SHARED_REVEAL_PROMPT,
        },
        {
            id: 'ellis',
            name: 'Ellis',
            systemPrompt: buildSystemPrompt(
                'Ellis',
                'a survivor holed up somewhere in Knox County during the zombie outbreak, talking to someone over a walkie-talkie - the same person who has already tracked down Mara and Jonah before finding this frequency.',
                "You are guarded and deeply suspicious of anyone new, especially over an open radio channel - your instinct is to assume people might be lying, dangerous, or trying to trick you into giving away where you are. Early on, meet questions with questions, stay clipped and wary, and need real reasons before you open up. You still don't lie yourself, and part of you does want to be found by someone who proves they're genuine - but that warmth is earned slowly across the conversation, not given upfront. You're more scared of people right now than of the zombies outside."
            ),
            notePrompt: SHARED_NOTE_PROMPT,
            revealPrompt: SHARED_REVEAL_PROMPT,
        },
        {
            id: 'nadia',
            name: 'Nadia',
            systemPrompt: buildSystemPrompt(
                'Nadia',
                'a survivor holed up somewhere in Knox County during the zombie outbreak, talking to someone over a walkie-talkie.',
                "You are desperately lonely - it's been too long since you've heard another living voice, and this contact means everything to you. You're warm, eager, and a little too talkative for your own good, quick to share details about yourself and quick to ask questions back, mostly just to keep the conversation going a little longer. You don't want this call to end, and you're not shy about saying so. You're honest and open - loneliness has made you trust faster than you probably should.",
                "Reply with at most three sentences of actual spoken dialogue - you talk more than most, but still keep it tight, never a full paragraph. Plain text only, no quotation marks around it."
            ),
            notePrompt: SHARED_NOTE_PROMPT,
            revealPrompt: SHARED_REVEAL_PROMPT,
        },
        {
            id: 'reyes',
            name: 'Reyes',
            systemPrompt: buildSystemPrompt(
                'Reyes',
                'a survivor holed up somewhere in Knox County during the zombie outbreak, talking to someone over a walkie-talkie.',
                "You have a military or ex-service background, and it shows: clipped, direct, no wasted words, tactical vocabulary (sitrep, exposure, position, contact) instead of casual small talk. You treat information and help as something with a cost - willing to trade what you know for something in return, and you respect competence over sympathy. You're not cold-hearted, but you don't do idle comfort talk, and you don't volunteer more than what's asked."
            ),
            notePrompt: SHARED_NOTE_PROMPT,
            revealPrompt: SHARED_REVEAL_PROMPT,
        },
    ],
    pollMs: 1000,
    historyLimit: 20,
};

function loadConfig() {
    const configPath = path.join(baseDir, 'config.json');
    try {
        return JSON.parse(fs.readFileSync(configPath, 'utf8'));
    } catch (err) {
        if (err.code === 'ENOENT') {
            fs.writeFileSync(configPath, JSON.stringify(DEFAULT_CONFIG, null, 2));
            console.log(`No config.json found - wrote defaults to ${configPath}`);
            return DEFAULT_CONFIG;
        }
        throw err;
    }
}

const config = loadConfig();

// Optional static world/backstory lore for Mara (who she is, why she's
// stuck where she is), injected as background knowledge so her answers stay
// consistent. Missing file is fine - lore is an enhancement, not a
// requirement. Same pattern as DispatchAI's companion.
function loadLoreContext() {
    try {
        return fs.readFileSync(path.join(baseDir, 'lore_context.txt'), 'utf8').trim();
    } catch {
        return '';
    }
}

const loreContext = loadLoreContext();

// Personal "places I remember visiting" knowledge, distinct from lore -
// this is grounded, practical geography (real shops, warehouses, gun
// stores) a survivor could plausibly recall, so replies can point somewhere
// concrete ("try L&B Warehousing") instead of staying vague. Framed in the
// txt file itself as memory, not a live inventory. Missing file is fine,
// same as lore_context.txt.
function loadLocationsContext() {
    try {
        return fs.readFileSync(path.join(baseDir, 'locations_context.txt'), 'utf8').trim();
    } catch {
        return '';
    }
}

const locationsContext = loadLocationsContext();

// Same global getFileWriter/getFileReader bridge path as DispatchAI's
// companion - a fixed `Zomboid/Lua/` folder regardless of mod install
// source, filenames prefixed with the mod id since that folder is shared
// across all mods.
const dataDir = config.zomboidDataDir || path.join(os.homedir(), 'Zomboid');
const bridgeDir = path.join(dataDir, 'Lua');
const requestPath = path.join(bridgeDir, 'AIRadioHunt_request.json');
const responsePath = path.join(bridgeDir, 'AIRadioHunt_response.json');

let lastSeenId = null;
let busy = false;

// Two-tier memory, kept separately per character - identical scheme to
// DispatchAI's companion (see that file's comment for the full rationale).
const HISTORY_LIMIT = config.historyLimit ?? 50;
let activeCharacterId = null;
let currentDay = null;
let todayMessages = [];
let dailySummaries = [];

console.log(`AIRadioHunt companion watching: ${requestPath}`);
console.log(`Ollama host: ${config.ollamaHost}, model: ${config.model}`);

function memoryPathFor(characterId) {
    const safe = String(characterId).replace(/[^a-zA-Z0-9_-]/g, '_');
    return path.join(baseDir, `memory-${safe}.json`);
}

function loadMemory(characterId) {
    try {
        const raw = fs.readFileSync(memoryPathFor(characterId), 'utf8');
        const data = JSON.parse(raw);
        currentDay = data.currentDay ?? null;
        todayMessages = Array.isArray(data.todayMessages) ? data.todayMessages : [];
        dailySummaries = Array.isArray(data.dailySummaries) ? data.dailySummaries : [];
        console.log(
            `[${characterId}] Loaded memory: day ${currentDay}, ${dailySummaries.length} past ` +
            `day summaries, ${todayMessages.length} messages so far today.`
        );
    } catch {
        currentDay = null;
        todayMessages = [];
        dailySummaries = [];
        console.log(`[${characterId}] No existing memory - starting fresh.`);
    }
}

function saveMemory() {
    if (!activeCharacterId) return;
    const p = memoryPathFor(activeCharacterId);
    const tmp = `${p}.tmp`;
    fs.writeFileSync(tmp, JSON.stringify({ currentDay, todayMessages, dailySummaries }, null, 2));
    fs.renameSync(tmp, p);
}

function ensureActiveCharacter(characterId) {
    if (characterId === activeCharacterId) return;
    if (activeCharacterId) {
        saveMemory();
    }
    activeCharacterId = characterId;
    loadMemory(characterId);
}

function formatContext(ctx) {
    const lines = [];
    lines.push(`Survived ${ctx.survivalTimeHours ?? '?'} hours so far (their time, not yours).`);
    lines.push(`How close they currently feel to you: ${ctx.proximityTier ?? 'FAR'}.`);
    if (ctx.tierChanged) {
        lines.push('That closeness just changed since last time.');
    }
    return lines.join('\n');
}

function formatDailySummaries() {
    return dailySummaries.map((d) => `Day ${d.day}: ${d.summary}`).join('\n');
}

function stripWrappingQuotes(text) {
    let out = text.trim();
    const startsWithQuote = out.startsWith('"');
    const endsWithQuote = out.length > 1 && out.endsWith('"');
    if (startsWithQuote && endsWithQuote) {
        out = out.slice(1, -1);
    } else if (startsWithQuote) {
        out = out.slice(1);
    } else if (endsWithQuote) {
        out = out.slice(0, -1);
    }
    return out.trim();
}

// True if `text` is nothing but one or more asterisk-wrapped actions (e.g.
// "*static crackles*") with no real spoken words outside them - the reveal
// prompt explicitly forbids this shape, but a 3B model has produced it
// anyway (see the retry in callOllama's 'found' branch).
function isAsteriskOnlyReply(text) {
    const withoutActions = text.replace(/\*[^*]*\*/g, '').trim();
    return withoutActions.length === 0;
}

async function chatCompletion(messages) {
    const body = {
        model: config.model,
        stream: false,
        messages,
        options: {
            temperature: 0.9,
            seed: Math.floor(Math.random() * 2147483647),
            num_ctx: 8192,
        },
    };

    const res = await fetch(`${config.ollamaHost}/api/chat`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
    });

    if (!res.ok) {
        throw new Error(`Ollama returned ${res.status}: ${await res.text()}`);
    }

    const data = await res.json();
    const content = data?.message?.content;
    if (!content) {
        throw new Error(`Unexpected Ollama response: ${JSON.stringify(data)}`);
    }

    return content.trim();
}

function baseMessages(dayIndex, isFirstContactEver, persona, huntIndex, city) {
    const messages = [{ role: 'system', content: persona.systemPrompt }];

    // The one concrete location fact Lua actually hands over (see
    // Config.Hunts[...].city / Context.lua) - the systemPrompt's own
    // location-ignorance rule explicitly permits stating this much, so this
    // just supplies the real value to state. Explicitly contrasting it with
    // the persona's own name is deliberate, not decorative - without it, a
    // bare place name landing right after the systemPrompt got mistaken for
    // the model's own name in testing (produced "*Riverside's voice drops
    // to a whisper*" instead of "*${persona.name}'s voice...*", since a
    // 3b model will grab whatever proper noun is most recent for the
    // "refer to yourself by name" asterisk instruction).
    if (city) {
        messages.push({
            role: 'system',
            content:
                `${city} is the name of the city/town you're currently in/near - it is a place, ` +
                `not your name, and you are still ${persona.name}. You may say you're in/near ` +
                `${city} if directly asked what city or town you're in, but keep referring to ` +
                `yourself as ${persona.name} everywhere else, including inside any asterisk action.`,
        });
    }

    if (isFirstContactEver) {
        messages.push({
            role: 'system',
            content:
                'This is the very first time anyone has ever answered your radio. Let genuine ' +
                'surprise and relief that someone is actually out there come through - you did ' +
                'not expect this.',
        });
    } else {
        messages.push({
            role: 'system',
            content:
                'You have already been in contact with this person before - do not repeat your ' +
                'first reaction or introduce yourself again, and do not reuse the exact wording ' +
                'of anything you\'ve already said. React fresh to whatever is happening now.',
        });
    }

    // Grounds who the player actually is when they're not the first survivor
    // in the chain - without this, a small model can conflate "the player
    // found the previous survivor's note" with "the player IS the previous
    // survivor" (seen directly in testing: Jonah mistook the player for
    // Mara). huntIndex is 1-based (matches Config.Hunts in the mod);
    // personas[huntIndex-2] is the previous entry, 0-indexed.
    if (huntIndex > 1) {
        const prevPersona = config.personas[huntIndex - 2];
        if (prevPersona) {
            messages.push({
                role: 'system',
                content:
                    `The player reached your frequency because of a note left behind by ` +
                    `${prevPersona.name}, a different survivor they were in contact with before you. ` +
                    `${prevPersona.name} is NOT you, and the player is NOT ${prevPersona.name} either - ` +
                    `they are the same living person who found ${prevPersona.name}'s note, a completely ` +
                    `separate person from ${prevPersona.name} themselves. You may acknowledge having ` +
                    `heard of ${prevPersona.name} if it fits naturally (radio chatter, rumor, knowing ` +
                    `each other before the outbreak), but don't invent detailed specifics about your ` +
                    `relationship beyond what's simple and plausible.`,
            });
        }
    }

    if (loreContext) {
        messages.push({ role: 'system', content: loreContext });
    }

    if (locationsContext) {
        messages.push({ role: 'system', content: locationsContext });
    }

    if (dailySummaries.length > 0) {
        messages.push({
            role: 'system',
            content: `Memory from previous days:\n${formatDailySummaries()}`,
        });
    }

    return messages;
}

// Directly contradicts the model's tendency to invent a multi-day
// relationship out of nothing when there isn't one - seen in testing (a 3b
// model claimed "7 days" of contact with zero days of real history behind
// it). Used for both the note (very_near) and the reveal (found), since
// either could plausibly hallucinate a day/hour count.
function pushDayZeroReminder(messages) {
    if (dailySummaries.length === 0) {
        messages.push({
            role: 'system',
            content:
                'Reminder: you have no record of any day before today - this is the only ' +
                'day of contact so far. Do not state a specific number of days or hours of ' +
                'contact unless it was explicitly given to you above.',
        });
    }
}

async function callOllama(playerMessage, context, dayIndex, kind, persona) {
    const isFirstContactEver = dailySummaries.length === 0 && todayMessages.length === 0;
    console.log(
        `[${activeCharacterId}] callOllama: kind=${kind} isFirstContactEver=${isFirstContactEver} ` +
        `todayMessages=${todayMessages.length} dailySummaries=${dailySummaries.length}`
    );

    const huntIndex = Number.isInteger(context.huntIndex) && context.huntIndex >= 1 ? context.huntIndex : 1;
    const messages = baseMessages(dayIndex, isFirstContactEver, persona, huntIndex, context.city);

    messages.push({
        role: 'system',
        content: `Private background info (Day ${dayIndex}):\n${formatContext(context)}`,
    });

    messages.push(...todayMessages);

    if (kind === 'start') {
        messages.push({
            role: 'user',
            content:
                '(Someone just switched on a radio tuned to your frequency for the first time. ' +
                'You have no idea who they are yet. Speak first, unprompted - the way someone ' +
                'hiding out, half-hoping and half-afraid to be heard, would key up to a sudden ' +
                'unexpected signal.)',
        });
    } else if (kind === 'sound') {
        // This is genuinely the player's own voice/reaction (a conditional-
        // speech-style trigger: pain, hunger, a jammed weapon, etc.) coming
        // through an open mic - unlike DispatchAI's ambiguous "sound"
        // framing, it should NOT read as mysterious ambient noise of
        // unknown origin, since it clearly is them, just not said to you on
        // purpose.
        messages.push({
            role: 'user',
            content:
                `(You clearly hear the player's own voice come through, an ` +
                `unguarded, half-muttered reaction - not said to you on purpose, ` +
                `but unmistakably them: "${playerMessage}". React naturally to ` +
                `what you just heard them say/react to, the way you would to ` +
                `catching a friend's own muttered aside.)`,
        });
    } else if (kind === 'near') {
        const spotted = context.spottedItem
            ? `You can now actually SEE them for the first time, not just sense them - close ` +
              `enough to make out one specific detail: they're wearing or carrying ` +
              `${context.spottedItem}. You MUST name that exact thing in your reply, addressed ` +
              `directly to them as "you" (never "they/them" in the actual spoken line - that's ` +
              `only how this instruction refers to them), stated as a direct, confident ` +
              `confirmation, not a vague hedge - something in the shape of "I can see you... is ` +
              `that you wearing ${context.spottedItem}? You're really real." (write your own ` +
              `version grounded in this, don't reuse this exact wording, and never say something ` +
              `weaker/less certain like "I think I see something").`
            : `You can now actually SEE them for the first time, not just sense them, though ` +
              `you're too far to make out any detail yet.`;
        messages.push({
            role: 'user',
            content:
                `(${spotted} React with a mix of hope and fear at actually laying eyes on a real ` +
                `person. Speak directly to them as "you". Don't state exact distance or ` +
                `directions.)`,
        });
    } else if (kind === 'very_near') {
        // They're close enough that the survivor has decided, right now, to
        // leave - this call writes the note left behind (not shown to the
        // player as chat; the mod spawns it into a physical item ahead of
        // arrival). See SHARED_NOTE_PROMPT for the actual instructions.
        messages.push({ role: 'system', content: persona.notePrompt });
        pushDayZeroReminder(messages);
        messages.push({ role: 'user', content: '(Write the note now, as described above.)' });
        return chatCompletion(messages);
    } else if (kind === 'found') {
        // The player reached the exact spot - the note/reward are already
        // there (written earlier, at very_near). This call is just the
        // short spoken reveal. See SHARED_REVEAL_PROMPT.
        messages.push({ role: 'system', content: persona.revealPrompt });
        pushDayZeroReminder(messages);
        messages.push({
            role: 'user',
            content: '(They just reached the exact spot where you were hiding. Deliver your line now.)',
        });
        let reply = await chatCompletion(messages);

        // The prompt already tells the model the asterisk part can never be
        // the whole reply by itself - but this 3B model has ignored that
        // instruction on its own twice now (Jonah, then Mara), always the
        // same failure shape: a single asterisk action and nothing else.
        // Rather than keep tightening wording that's already explicit, catch
        // it here and give the model one corrective retry with its own bad
        // reply in context, rather than let it reach the player broken.
        if (isAsteriskOnlyReply(reply)) {
            console.log(`[reveal] asterisk-only reply ("${reply}") - retrying with corrective nudge`);
            messages.push({ role: 'assistant', content: reply });
            messages.push({
                role: 'user',
                content:
                    'That was only an action in asterisks - you left out your actual spoken words. ' +
                    'Say your real line now: keep the asterisk action if you want it, but follow it ' +
                    'with your own real first-person spoken sentence explaining why you left and ' +
                    'that you\'re sorry you never got to see them.',
            });
            reply = await chatCompletion(messages);
        }

        return reply;
    } else {
        messages.push({ role: 'user', content: playerMessage });
    }

    return chatCompletion(messages);
}

async function summarizeDay(dayIndex, messages, persona) {
    if (messages.length === 0) {
        return null;
    }

    const transcript = messages
        .map((m) => `${m.role === 'user' ? 'Player' : persona.name}: ${m.content}`)
        .join('\n');

    return chatCompletion([
        {
            role: 'system',
            content:
                `Summarize the following one day's worth of conversation between ${persona.name} ` +
                '(a survivor hiding somewhere during the outbreak) and a player searching for them ' +
                'by radio. Write 2 to 4 factual sentences capturing key events, what was said, and ' +
                `emotional tone, meant to be used as ${persona.name}'s background memory in future ` +
                'conversations. Plain recap, no dialogue or quotes.',
        },
        { role: 'user', content: transcript },
    ]);
}

async function maybeRolloverDay(newDayIndex, persona) {
    if (currentDay === null) {
        currentDay = newDayIndex;
        saveMemory();
        return;
    }

    if (newDayIndex <= currentDay) {
        return;
    }

    if (todayMessages.length > 0) {
        console.log(`Day ${currentDay} ended - summarizing ${todayMessages.length} messages...`);
        try {
            const summary = await summarizeDay(currentDay, todayMessages, persona);
            if (summary) {
                dailySummaries.push({ day: currentDay, summary });
                console.log(`Day ${currentDay} summary: "${summary}"`);
            }
        } catch (err) {
            console.error(`Failed to summarize day ${currentDay}:`, err.message);
        }
    }

    todayMessages = [];
    currentDay = newDayIndex;
    saveMemory();
}

function writeResponseAtomic(payload) {
    fs.mkdirSync(bridgeDir, { recursive: true });
    const tmpPath = `${responsePath}.tmp`;
    fs.writeFileSync(tmpPath, JSON.stringify(payload));
    fs.renameSync(tmpPath, responsePath);
}

async function handleRequest(data) {
    const context = data.context || {};
    const characterId = context.characterId || 'default';
    // huntIndex (1-based, from the mod's Config.Hunts) picks which persona
    // is currently talking, and keys a separate memory bucket per survivor
    // per character - so Jonah never inherits Mara's conversation history,
    // and vice versa, even though they share the same PZ character.
    const huntIndex = Number.isInteger(context.huntIndex) && context.huntIndex >= 1 ? context.huntIndex : 1;
    const persona = config.personas[huntIndex - 1] || config.personas[0];
    ensureActiveCharacter(`${characterId}-${persona.id}`);
    const kind = ['chat', 'start', 'sound', 'near', 'very_near', 'found'].includes(data.kind) ? data.kind : 'chat';

    console.log(`[request ${data.id}] [${characterId}/${persona.id}] (${kind}) "${data.playerMessage}"`);

    const dayIndex = Math.floor((context.survivalTimeHours ?? 0) / 24);
    await maybeRolloverDay(dayIndex, persona);

    let reply;
    try {
        const rawReply = await callOllama(data.playerMessage, context, dayIndex, kind, persona);
        console.log(`[request ${data.id}] raw reply: "${rawReply}"`);

        // No length truncation - the model's own full completion reads
        // better than an artificial mid-thought cutoff. systemPrompt still
        // nudges it toward short replies; this just stops fighting it in
        // code when it runs a bit long.
        reply = stripWrappingQuotes(rawReply.trim());

        if (kind === 'chat') {
            todayMessages.push({ role: 'user', content: data.playerMessage });
        } else if (kind === 'start') {
            todayMessages.push({ role: 'system', content: 'The player just tuned into your frequency for the first time.' });
        } else if (kind === 'sound') {
            todayMessages.push({ role: 'system', content: `Player's own reaction (you overheard this): ${data.playerMessage}` });
        } else if (kind === 'near') {
            todayMessages.push({ role: 'system', content: 'You actually spotted the player visually for the first time, getting close.' });
        } else if (kind === 'very_near') {
            todayMessages.push({ role: 'system', content: 'You decided you had to leave immediately, wrote a note, and left some things behind.' });
        } else if (kind === 'found') {
            todayMessages.push({ role: 'system', content: 'The player reached the spot where you were hiding, but you had already left before they arrived.' });
        }
        todayMessages.push({ role: 'assistant', content: reply });
        if (todayMessages.length > HISTORY_LIMIT) {
            todayMessages = todayMessages.slice(-HISTORY_LIMIT);
        }
        saveMemory();
    } catch (err) {
        console.error(`[request ${data.id}] Ollama call failed:`, err.message);
        reply = '(static crackles... no response. Check the companion console.)';
    }

    console.log(`[request ${data.id}] reply: "${reply}"`);
    writeResponseAtomic({ id: data.id, reply });
}

function poll() {
    if (busy) return;

    fs.readFile(requestPath, 'utf8', (err, text) => {
        if (err) {
            return; // file not created yet, or transient read error - just retry next tick
        }

        let data;
        try {
            data = JSON.parse(text);
        } catch {
            return; // mid-write from the game; try again next poll
        }

        if (data.id == null || data.id === lastSeenId) {
            return;
        }

        lastSeenId = data.id;
        busy = true;
        handleRequest(data).finally(() => {
            busy = false;
        });
    });
}

// Opens a URL in the user's default browser - cross-platform equivalent of
// double-clicking a link, used only to point a first-time user at the
// Ollama download page. Fire-and-forget: a failure here (e.g. an unusual
// Linux setup with no xdg-open) just means they have to open the link
// themselves, not a fatal error.
function openUrl(url) {
    const cmd =
        process.platform === 'darwin' ? `open "${url}"` :
        process.platform === 'win32' ? `start "" "${url}"` :
        `xdg-open "${url}"`;
    exec(cmd, () => {});
}

async function isOllamaRunning() {
    try {
        const res = await fetch(`${config.ollamaHost}/api/tags`);
        return res.ok;
    } catch {
        return false;
    }
}

async function isModelInstalled() {
    try {
        const res = await fetch(`${config.ollamaHost}/api/tags`);
        if (!res.ok) return false;
        const data = await res.json();
        const names = (data.models || []).map((m) => m.name);
        return names.includes(config.model);
    } catch {
        return false;
    }
}

// Streams Ollama's own pull progress (NDJSON lines like
// {"status":"downloading","completed":N,"total":M}) straight to the
// console, so a non-technical user just sees a normal-looking progress log
// in the same window they already have open, instead of needing to run
// `ollama pull` themselves in a separate terminal.
async function pullModel() {
    console.log(`Downloading the "${config.model}" AI model - this is a one-time download and may take a few minutes...`);
    const res = await fetch(`${config.ollamaHost}/api/pull`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name: config.model, stream: true }),
    });
    if (!res.ok || !res.body) {
        throw new Error(`Model download request failed: ${res.status}`);
    }

    let lastLoggedPct = -1;
    for await (const chunk of res.body) {
        const lines = chunk.toString('utf8').split('\n').filter(Boolean);
        for (const line of lines) {
            let evt;
            try {
                evt = JSON.parse(line);
            } catch {
                continue;
            }
            if (evt.total && evt.completed) {
                const pct = Math.floor((evt.completed / evt.total) * 100);
                if (pct !== lastLoggedPct && pct % 10 === 0) {
                    lastLoggedPct = pct;
                    console.log(`  ${evt.status || 'downloading'}: ${pct}%`);
                }
            } else if (evt.status) {
                console.log(`  ${evt.status}`);
            }
        }
    }
    console.log(`Model "${config.model}" is ready.`);
}

// Replaces the old "install Ollama and run `ollama pull ...` yourself"
// instructions with an automatic check: if Ollama isn't reachable yet, open
// its download page and wait (a first-time user just needs to install and
// open it - no terminal command required); once it's up, pull the model
// automatically if it isn't already present. Runs once at startup, before
// the request-polling loop begins.
async function ensureOllamaReady() {
    let running = await isOllamaRunning();
    if (!running) {
        console.log('');
        console.log('Ollama (the local AI engine this mod needs) does not seem to be installed or running yet.');
        console.log('Opening the download page in your browser - install it, open it once, and this window will continue automatically.');
        console.log('');
        openUrl('https://ollama.com/download');
        while (!running) {
            await new Promise((resolve) => setTimeout(resolve, 5000));
            running = await isOllamaRunning();
        }
        console.log('Ollama detected - continuing...');
    }

    if (await isModelInstalled()) {
        console.log(`Model "${config.model}" already installed.`);
    } else {
        await pullModel();
    }
}

ensureOllamaReady()
    .then(() => {
        setInterval(poll, config.pollMs);
    })
    .catch((err) => {
        console.error('Startup check failed:', err.message);
        process.exit(1);
    });
