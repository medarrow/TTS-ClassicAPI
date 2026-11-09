# TTS-ClassicAPI

A text-to-speech screen reader for **World of Warcraft 1.12.1** (Vanilla / TurtleWoW), built on the
text-to-speech API provided by [ClassicAPI](https://github.com/brues-code/ClassicAPI).

Pick what you want read aloud, such as chat, NPC dialogue, quest text, books or your target, and give each
source its own voice, speed, volume, cooldown and wording.

## Requirements

- **[ClassicAPI](https://github.com/brues-code/ClassicAPI)**, loaded through VanillaFixes. It provides
  `C_VoiceChat` / `C_TTSSettings` (speech through Windows SAPI) and the newer Lua features this addon uses.
  The standalone [VanillaTTS](https://github.com/brues-code/VanillaTTS) DLL provides the same speech API and
  works too.
- **Windows speech voices.** Add more under *Windows Settings → Time & Language → Speech*, then type
  `/tts voices` in game.

Without ClassicAPI the addon prints a warning at login and stays inactive.

## Installation

1. Download the latest `TTS-ClassicAPI-x.y.z.zip` from the [Releases](../../releases) page.
2. Extract it into `World of Warcraft\Interface\AddOns\`.
3. The folder must be named exactly **`TTS-ClassicAPI`**, so the path is
   `Interface\AddOns\TTS-ClassicAPI\TTS-ClassicAPI.toc`.

> GitHub's green **Code → Download ZIP** button extracts to `TTS-ClassicAPI-main`. Rename that folder to
> `TTS-ClassicAPI` or the game won't load it. The release zips already use the right name.

## Usage

Type **`/tts`** to open the options window.

- **Left list.** Every source, grouped by category. The checkbox turns a source on or off; click its name to
  edit its settings.
- **General settings.**
  - Default voice, rate and volume. These are ClassicAPI's shared `C_TTSSettings`, saved in `Config.wtf`.
  - Queue length, repeat suppression, maximum line length.
  - Abbreviation expansion, own-message reading, skipping unknown languages, silence in combat.
- **Each source** can have:
  - its own voice, rate and volume
  - **Interrupt**: cut in front of whatever is playing
  - **Not in combat**: stay quiet while you're fighting
  - **Cooldown**: the minimum time between lines from this source
  - a **template** that controls what's said, e.g. `{name} says: {msg}`
- **Presets.** Built-in presets switch groups of sources on or off. You can also save full snapshots of your
  own setup.

### Sources

| Category | Sources |
|---|---|
| Chat | Say, Yell, Emotes, Whispers (in/out), AFK/DND replies, Party, Raid, Raid Warning, Battleground, Guild, Officer |
| Channels | World, General, Trade, Looking For Group, Local/World Defense, other custom channels |
| NPCs | NPC say, yell, whisper, emotes, boss emotes |
| Quests & Dialog | Quest greeting, description, progress, completion, NPC gossip, books/letters/plaques, quest accepted, quest turned in, objective progress, quest log read button |
| Targeting | Target, mouseover, focus, soft target / interact, nameplates appearing |
| Group & System | Invites/duels/resurrects/ready checks, battleground announcements, system messages, error messages, loot, money, XP, reputation, skill ups, level up, zone & subzone changes |

The hidden `LFT` addon-communication channel is never read.

### Quest log button

A small faded note icon sits in the top-right of the quest log's detail pane.

- **Left-click** reads the selected quest: title, description, objectives and progress. Click again to stop.
- **Right-click** stops all speech.

Its look and wording come from the *Quest log read button* source, and that source's checkbox shows or hides
the icon.

### Templates

Each source's text is built from a template with `{tokens}`. Tokens with no value are dropped. The options
panel lists each source's tokens. Common ones:

- **Chat:** `{msg}` `{name}` `{channel}` `{language}` `{target}`
- **Units:** `{name}` `{level}` `{class}` `{race}` `{classification}` `{reaction}` `{health}` `{guild}` `{dead}`
- **Quests:** `{title}` `{msg}` `{objectives}` `{progress}` `{npc}`

### Presets

| Preset | Turns on |
|---|---|
| Default | The out-of-the-box selection (and re-enables *Stop when window closes*) |
| None | Nothing |
| Local | Say, Yell, Emotes |
| Social | Local + Party, Raid, Raid Warning, Guild, incoming Whispers |
| NPCs | All NPC speech, including boss emotes |
| Quests | All quest, gossip and book sources (and disables *Stop when window closes*) |

Built-in presets only change which sources are on. Saved presets restore every per-source setting.

### Slash commands

| Command | Action |
|---|---|
| `/tts` | Open options |
| `/tts on` / `off` / `toggle` | Enable or disable speech |
| `/tts stop` / `skip` / `repeat` | Playback control |
| `/tts say <text>` | Speak some text |
| `/tts target` | Read your target |
| `/tts voices` | Refresh and list installed voices |
| `/tts mute <name>` / `unmute <name>` / `muted` | Mute specific players |
| `/tts preset <name>` / `savepreset <name>` / `presets` | Load, save or list presets |
| `/tts debug` | Print each spoken line and its source to chat |

### Key bindings

Under *Key Bindings → TTS-ClassicAPI*: toggle speech, stop, skip, repeat last line, read target, open
options.

## Troubleshooting

- **Nothing is spoken.**
  - Check that *Speech enabled* is ticked and the status line shows at least one voice.
  - Run `/tts voices`.
  - Make sure ClassicAPI is actually loaded (launched through VanillaFixes).
- **Something unexpected is being read.** Turn on `/tts debug`. Each line is printed with its source key
  (e.g. `[TARGET]`), so you can find and disable or throttle that source.
- **Chat is too chatty.** Give busy sources (World, Trade, etc.) a **Cooldown**, or lower *Max queued lines*.

## Credits

- Text-to-speech and the modern API are provided by [ClassicAPI](https://github.com/brues-code/ClassicAPI)
  by brues-code.

## License

[MIT](LICENSE)
