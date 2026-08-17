# MONKEY MONEY — Credits & Lizenzen

Alle Dritt-Assets in diesem Projekt sind frei lizenziert. Es werden KEINE
synthetisch generierten Sounds verwendet — alle Sounds stammen aus den unten
genannten, echten Quellen. Generierte Bilder (Texturen/Illustrationen) sind
als solche im jeweiligen Ordner gekennzeichnet.

## Sounds (SFX)

| Ordner | Quelle | Autor | Lizenz | Link |
|---|---|---|---|---|
| `assets/audio/kenney/interface-sounds/` | Kenney — Interface Sounds | Kenney | CC0 1.0 | https://kenney.nl/assets/interface-sounds |
| `assets/audio/kenney/ui-audio/` | Kenney — UI Audio | Kenney | CC0 1.0 | https://kenney.nl/assets/ui-audio |
| `assets/audio/kenney/music-jingles/` | Kenney — Music Jingles | Kenney | CC0 1.0 | https://kenney.nl/assets/music-jingles |
| `assets/audio/kenney/digital-audio/` | Kenney — Digital Audio | Kenney | CC0 1.0 | https://kenney.nl/assets/digital-audio |
| `assets/audio/kenney/impact-sounds/` | Kenney — Impact Sounds | Kenney | CC0 1.0 | https://kenney.nl/assets/impact-sounds |
| `assets/audio/kenney/casino-audio/` | Kenney — Casino Audio | Kenney | CC0 1.0 | https://kenney.nl/assets/casino-audio |
| `assets/audio/kenney/sci-fi-sounds/` | Kenney — Sci-Fi Sounds | Kenney | CC0 1.0 | https://kenney.nl/assets/sci-fi-sounds |

## Beschaffte Einzel-Sounds (Trommelwirbel/Riser · Buzzer-Familie · Kassenlade)

Alle Dateien liegen als Quelle unter `assets/audio/extern/` und (identisch) als
ausgespielte Kopie unter `client/public/audio/sfx/`. „Änderungen":
geschnitten/gefadet/auf −16 LUFS normalisiert durch uns (ffmpeg loudnorm) —
CC-BY verlangt diesen Hinweis; genutzt wird IMMER die normalisierte Fassung.

| Datei | Verwendung | Quelle | Autor | Lizenz | Link | Änderungen |
|---|---|---|---|---|---|---|
| `trommelwirbel_kurz_ccby_macleod.ogg` | Auflösungs-Dreiklang (Spannung) | Wikimedia Commons „Kevin MacLeod assorted rimshots – 4-second roll.wav" | Kevin MacLeod (incompetech.com) | CC BY 3.0 | https://commons.wikimedia.org/wiki/File:Kevin_MacLeod_assorted_rimshots_-_4-second_roll.wav | geschnitten (2,8–4,55 s), Fade-in, −16 LUFS |
| `trommelwirbel_lang_cc0_iwan.ogg` | Siegerehrungs-Trommelwirbel | Wikimedia Commons „Drum Roll Intro.ogg" | Iwan Sounds and DIY | CC0 | https://commons.wikimedia.org/wiki/File:Drum_Roll_Intro.ogg | 5.1→Stereo-Downmix, −16 LUFS |
| `riser_ccby_tritachyon.ogg` | Auflösungs-Dreiklang (Spannung, Round-Robin) | OpenGameArt „Riser 42 (Medieval/Witcher)" | Tri-Tachyon | CC BY 4.0 | https://opengameart.org/content/riser-42-medieval-witcher | geschnitten (14,3–16,05 s), Fades, −16 LUFS |
| `buzzer_hupe_cc0_bsb.ogg` | Standard-Buzzer Slot 1 / Shop | BigSoundBank #0258 „Recent Car Horn" | Joseph SARDIN (BigSoundBank.com) | CC0 | https://bigsoundbank.com/recent-car-horn-2-s0258.html | −16 LUFS |
| `buzzer_klingel_cc0_bsb.ogg` | Standard-Buzzer Slot 2 / Shop | BigSoundBank #0275 „Bell bike" | Joseph SARDIN (BigSoundBank.com) | CC0 | https://bigsoundbank.com/bell-bike-2-s0275.html | −16 LUFS |
| `buzzer_quaek_cc0_bsb.ogg` | Standard-Buzzer Slot 3 / Shop | BigSoundBank #0417 „Mallard duck plush" | Joseph SARDIN (BigSoundBank.com) | CC0 | https://bigsoundbank.com/mallard-duck-plush-s0417.html | geschnitten (erste 1,3 s), −16 LUFS |
| `buzzer_glocke_cc0_bsb.ogg` | Standard-Buzzer Slot 4 / Shop | BigSoundBank #0479 „Counter bell" | Joseph SARDIN (BigSoundBank.com) | CC0 | https://bigsoundbank.com/counter-bell-s0479.html | geschnitten (erste 2,2 s), Fade-out, −19 LUFS (Transienten-Limit) |
| `buzzer_boing_cc0_bsb.ogg` | Standard-Buzzer Slot 5 / Shop | BigSoundBank #2284 „Boing Cartoon" | Joseph SARDIN (BigSoundBank.com) | CC0 | https://bigsoundbank.com/boing-cartoon-8-s2284.html | −17 LUFS (Transienten-Limit) |
| `buzzer_pfeife_cc0_bsb.ogg` | Standard-Buzzer Slot 6 / Shop | BigSoundBank #1017 „Plastic Whistle" | Joseph SARDIN (BigSoundBank.com) | CC0 | https://bigsoundbank.com/plastic-whistle-s1017.html | geschnitten (erste 1,0 s), −16 LUFS |
| `buzzer_wecker_cc0_bsb.ogg` | Standard-Buzzer Slot 7 / Shop | BigSoundBank #2814 „Mechanical Alarm Clock, Ringtone" | Joseph SARDIN (BigSoundBank.com) | CC0 | https://bigsoundbank.com/mechanical-alarm-clock-ringtone-11-s2814.html | geschnitten (erste 2,0 s), Fade-out, −16 LUFS |
| `buzzer_airhorn_cc0_bsb.ogg` | Standard-Buzzer Slot 8 / Shop | BigSoundBank #1829 „Pneumatic horn, simple" | Joseph SARDIN (BigSoundBank.com) | CC0 | https://bigsoundbank.com/pneumatic-horn-simple-3-s1829.html | −17 LUFS (Transienten-Limit) |
| `kasse_kaching_pd_wikimedia.ogg` | Money-Kling MITTEL (Kassenlade) | Wikimedia Commons „Cash register.ogg" (via SoundBible) | Uploader Myoung8 („Me") | Public Domain | https://commons.wikimedia.org/wiki/File:Cash_register.ogg | −16 LUFS |

Geprüft und verworfen: „Paukenwirbel auf einer Wiener Pauke …" (Wikimedia,
CC BY-**SA** 4.0 — Share-Alike ist nicht in unserer Lizenz-Whitelist).

## Publikum / Applaus

| Datei | Quelle | Autor | Lizenz |
|---|---|---|---|
| `assets/audio/crowd/applause_gross_ccby_RHumphries.ogg` | Wikimedia Commons „Applause-2.ogg" | RHumphries | CC BY 3.0 |
| `assets/audio/crowd/applause_kurz_pd_thore.ogg` | Wikimedia Commons „Applause i.ogg" | thore | Public Domain |
| `assets/audio/crowd/applause_mittel_pd_thore.ogg` | Wikimedia Commons „Applause ii.ogg" | thore | Public Domain |
| `assets/audio/crowd/applause_anlaufend_pd_stephan.ogg` | Wikimedia Commons „Slow starting applause.ogg" | stephan | Public Domain |
| `assets/audio/crowd/applause_jubel_pd_starlite.ogg` | Wikimedia Commons „Clapping hurray.ogg" | starlite | Public Domain |

## Musik

Alle Tracks: Kevin MacLeod (incompetech.com), Lizenz **CC BY 4.0**
(https://creativecommons.org/licenses/by/4.0/).

| Datei | Track |
|---|---|
| `assets/audio/music/MonkeysSpinningMonkeys.mp3` | "Monkeys Spinning Monkeys" |
| `assets/audio/music/FluffingADuck.mp3` | "Fluffing a Duck" |
| `assets/audio/music/SneakySnitch.mp3` | "Sneaky Snitch" |
| `assets/audio/music/LocalForecastElevator.mp3` | "Local Forecast - Elevator" |
| `assets/audio/music/MerryGo.mp3` | "Merry Go" |
| `assets/audio/music/QuirkyDog.mp3` | "Quirky Dog" |

Attributions-Formel (in-App im Credits-Screen eingeblendet):
"Music: Kevin MacLeod (incompetech.com), Licensed under Creative Commons: By Attribution 4.0"

## Song-Packs (Musik-Minigames)

Die Rate-Snippets der Musik-Minigames (Demo-Pack „starter": 78er-/Klassiker-
Originale von archive.org + die 6 Kevin-MacLeod-Tracks) führen ihre Credits
in **`content/musik/CREDITS-SONGS.md`** — automatisch gepflegt von
`tools/musik/import.mjs` (Titel/Artist/Jahr/Quelle-URL/Abruf-Datum, Cover
sind markiert). Privates Freundes-Projekt: nur kurze Snippets (0,1–10 s),
Volldownloads werden nicht aufbewahrt; Details `docs/MUSIK-PACKS.md`.

## Fonts

| Datei | Font | Lizenz |
|---|---|---|
| `assets/fonts/bungee.ttf`, `bungeeshade.ttf` | Bungee / Bungee Shade (David Jonathan Ross) | SIL OFL 1.1 (`assets/fonts/OFL-Bungee.txt`) |
| `assets/fonts/rubik.ttf`, `rubikitalic.ttf` | Rubik (Hubert & Fischer u. a.) | SIL OFL 1.1 (`assets/fonts/OFL-Rubik.txt`) |

## Bilder

Generierte Bilder (KI) für Texturen/Kulissen/Frage-Bilder liegen unter
`assets/img/generated/` und sind im Manifest `assets/img/generated/MANIFEST.md`
gelistet. Wikimedia-Bilder für Frage-Medien führen ihre Attribution im
jeweiligen Fragen-JSON (`media.attribution`) und werden in-App angezeigt.
