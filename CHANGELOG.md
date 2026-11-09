# Changelog

## Unreleased

- The Target source is now off by default, so no Targeting sources are on in a new install or in the
  **Default** preset. Existing settings are unchanged; load the Default preset to apply it.
  `/tts target` and the *Read target* key binding still work while the source is off.

## 1.0.0

First public release.

- Text-to-speech through ClassicAPI's `C_VoiceChat` / `C_TTSSettings` (Windows SAPI). VanillaTTS works too.
- About 45 sources across chat, channels, NPCs, quests & dialog, targeting, and group & system.
- Per-source settings:
  - on/off
  - voice, rate and volume
  - interrupt
  - not in combat
  - cooldown
  - a template with `{tokens}`
- Built-in presets (Default, None, Local, Social, NPCs, Quests) and your own saved presets.
- A read button in the quest log.
- Speech queue:
  - a maximum length
  - repeat suppression
  - stop, skip and repeat
  - a fallback timer in case the speech engine never reports back
- Text cleanup:
  - strips links, colours and icons
  - expands chat abbreviations
  - reads `3/10` as "3 of 10"
  - says "link" instead of spelling out URLs
- Skips chat in languages your character doesn't speak; per-player mute list.
- The hidden `LFT` addon channel is never read.
- Settles target changes so nameplate and target-scanning addons don't cause spam.
- Slash commands (`/tts`) and key bindings.
