// Event→Datei-Mapping EXAKT nach ART-SOUND-VIDEO-PLAN §4.1/§4.2 — die Dateien
// liegen in client/public/audio/** (kopierte Auswahl aus assets/audio/**).
// Varianten-Arrays laufen als Round-Robin (kein Zufall — Rng-Disziplin);
// Layer-Defs (L) spielen ALLE Dateien gleichzeitig (Plan-Notation „A + B").
import { SHOP_ITEMS } from "../../../shared/meta";

export interface SfxDef {
  dateien: string[];
  gain: number; // 0–1 relativ zum SFX-Bus
  /** true = dateien sind gleichzeitige Layer statt Round-Robin-Varianten. */
  layers?: boolean;
}

const S = (dateien: string[], gain = 1): SfxDef => ({
  dateien: dateien.map((d) => `/audio/sfx/${d}`),
  gain,
});
const L = (dateien: string[], gain = 1): SfxDef => ({
  dateien: dateien.map((d) => `/audio/sfx/${d}`),
  gain,
  layers: true,
});
const C = (datei: string, gain = 1): SfxDef => ({
  dateien: [`/audio/crowd/${datei}`],
  gain,
});

export const SFX: Record<string, SfxDef> = {
  // ---------- UI & Lobby ----------
  tap: S(["click_001.ogg"], 0.7),
  bestaetigen: S(["confirmation_001.ogg"], 0.8),
  zurueck: S(["back_001.ogg"], 0.7),
  fehler: S(["error_004.ogg"], 0.8),
  "join-plopp": S(["drop_002.ogg"]),
  "lockin-thunk": S(["impactPlank_medium_000.ogg"], 0.9),
  ticker: S(["scroll_001.ogg"], 0.4),
  toggle: S(["switch_001.ogg"], 0.7),
  // ---------- Frage-Dramaturgie ----------
  "frage-ein": S(["question_001.ogg"]),
  "karte-slide": S(["card-slide-1.ogg"], 0.9),
  tick: S(["tick_001.ogg"], 0.8),
  "tick-schnell": S(["tick_002.ogg"], 0.9),
  "zeit-um": S(["impactBell_heavy_000.ogg"]),
  richtig: L(["threeTone1.ogg", "chips-collide-1.ogg"]),
  falsch: S(["lowThreeTone.ogg"]),
  "reveal-zap": S(["glitch_002.ogg"], 0.8),
  // Auflösungs-Dreiklang (Plan §3.2/§4): Spannung → ECHTE Stille → Fanfare.
  // Beide Spannungs-Dateien sind exakt gleich lang geschnitten (1,75 s) —
  // der Round-Robin wechselt Trommelwirbel/Riser, das Timing bleibt konstant.
  "aufloesungs-spannung": S(
    ["trommelwirbel_kurz_ccby_macleod.ogg", "riser_ccby_tritachyon.ogg"],
    0.9,
  ),
  "trommelwirbel-lang": S(["trommelwirbel_lang_cc0_iwan.ogg"], 0.9),
  // ---------- Money & Casino (3 Kling-Stufen: Pling → Kassenlade → Münzregen) ----------
  "money-klein": S(["chip-lay-1.ogg", "chip-lay-2.ogg", "chip-lay-3.ogg"], 0.9),
  "money-mittel": L(["kasse_kaching_pd_wikimedia.ogg", "chips-handle-3.ogg"]),
  "money-gross": L(["chips-stack-4.ogg", "chips-collide-2.ogg", "chips-collide-3.ogg"]),
  "schein-landung": S(["card-place-2.ogg"], 0.5),
  "schein-faecher": S(["card-fan-1.ogg"], 0.9),
  "karten-mischen": S(["card-shuffle.ogg"], 0.9),
  wuerfel: S(["dice-throw-1.ogg"], 0.9),
  "joker-zuenden": S(["powerUp7.ogg"], 0.9),
  "jackpot-einzahlung": L(["chip-lay-3.ogg", "impactMetal_light_000.ogg"], 0.9),
  // ---------- Show-Momente ----------
  buzzer: S(["bong_001.ogg"]),
  klau: L(["phaserUp3.ogg", "card-shove-2.ogg"]),
  "stinkbanane-platzt": S(["slime_000.ogg"]),
  "matsch-treffer": S(["impactSoft_medium_001.ogg"], 0.9),
  "podium-riss": S(["impactWood_heavy_000.ogg"], 0.9),
  // Echter Ratschen-Tick statt 10-ms-Digital-Klick (Plan §4.1-Prüfauftrag):
  // impactWood_light = hölzerner Zungen-Klack wie am Jahrmarkt-Rad, 3 Varianten
  // im Round-Robin gegen Maschinengewehr-Monotonie. Engine taktet weiterhin.
  "rad-tick": S(
    ["impactWood_light_000.ogg", "impactWood_light_001.ogg", "impactWood_light_002.ogg"],
    0.55,
  ),
  "einlauf-schritt": S(
    ["footstep_wood_000.ogg", "footstep_wood_001.ogg", "footstep_wood_002.ogg"],
    0.8,
  ),
  stinger: S(["jingles_HIT02.ogg"], 0.9),
  "sieg-fanfare": S(["jingles_HIT14.ogg"]),
  // v2 Sudden-Death: Herzschlag = doppelter Soft-Thump (da-dumm, Regie taktet),
  // Kokosnuss-Knack = harter Holz-Schlag beim Shake-Ergebnis.
  herzschlag: S(["impactSoft_heavy_001.ogg"], 0.7),
  "kokosnuss-knack": S(["impactWood_heavy_000.ogg"]),
  "runden-sieg": S(["jingles_SAX10.ogg"], 0.9),
  fehlbuzz: S(["error_007.ogg"], 0.9),
  "konfetti-pop": S(["impactSoft_heavy_001.ogg"]),
  // ---------- Publikum (Stufe koppelt an Punkte-Delta, nie zufällig) ----------
  "applaus-kurz": C("applause_kurz_pd_thore.ogg", 0.8),
  "applaus-mittel": C("applause_mittel_pd_thore.ogg", 0.85),
  "applaus-gross": C("applause_gross_ccby_RHumphries.ogg", 0.9),
  "applaus-jubel": C("applause_jubel_pd_starlite.ogg"),
  "applaus-anlaufend": C("applause_anlaufend_pd_stephan.ogg", 0.9),
};

// META (§7.4 — Shop-Items wirken im Match): gekaufte Buzzer-Sounds direkt aus
// dem Katalog — SFX-Id = Item-Id, Datei aus ShopItem.datei (CC0-Packs).
for (const item of SHOP_ITEMS) {
  if (item.typ === "sound" && item.datei) SFX[item.id] = S([item.datei], 0.9);
}

// ---------- Standard-Buzzer-Familie (Plan §4.3 Lücke 3, GESCHLOSSEN) ----------
// 8 klanglich klar unterscheidbare Timbres (Hupe/Klingel/Quäk/Glocke/Boing/
// Pfeife/Wecker/Airhorn, alle CC0 BigSoundBank). Jeder Spieler-Slot bekommt
// automatisch einen ANDEREN Standard-Buzzer — ein gekaufter Shop-Buzzer
// (buzzerSoundAus) überstimmt den Slot-Standard. Die SFX-Ids sind die
// Shop-Item-Ids (die Familie ist zugleich im Shop wählbar).
export const STANDARD_BUZZER: readonly string[] = [
  "buzzer-hupe",
  "buzzer-klingel",
  "buzzer-quaek-hupe",
  "buzzer-glocke",
  "buzzer-boing",
  "buzzer-pfeife",
  "buzzer-wecker",
  "buzzer-airhorn",
];

/** Standard-Buzzer eines Spieler-Slots (0-basiert) — deterministisch, kein Zufall. */
export function standardBuzzer(slotIndex: number): string {
  const n = STANDARD_BUZZER.length;
  return STANDARD_BUZZER[((slotIndex % n) + n) % n];
}

// ---------- Auflösungs-Dreiklang-Timing (Plan §3.2: Riser → Stille → Stinger) ----------
/** Länge der Spannungs-Sounds (Trommelwirbel kurz + Riser, identisch geschnitten). */
export const AUFLOESUNG_SPANNUNG_MS = 1750;
/** ECHTE Stille zwischen Spannung und Fanfare (Plan-Regel: 0,5–1 s). */
export const AUFLOESUNG_STILLE_MS = 650;
/** Siegerehrung: Trommelwirbel (Datei auf 2,5 s geschnitten — P2-Befund
 * „Sieger-Landung + Konfetti bei +2,6 s, Fanfare erst +4,8 s": jetzt landet
 * Platz 1 EXAKT auf der Fanfare bei +3,3 s) + Stille davor. */
export const SIEG_TROMMELWIRBEL_MS = 2500;
export const SIEG_STILLE_MS = 800;
/** Fanfare-Moment der Siegerehrung — Podest-Landung/Konfetti/Awards koppeln hieran. */
export const SIEG_FANFARE_MS = SIEG_TROMMELWIRBEL_MS + SIEG_STILLE_MS;

/** Musik-Ebenen (Plan §4.2): eine Datei pro Show-Phase, alle als Loop. */
export const MUSIK: Record<string, string> = {
  lobby: "/audio/musik/MonkeysSpinningMonkeys.mp3",
  runde: "/audio/musik/QuirkyDog.mp3",
  schleich: "/audio/musik/SneakySnitch.mp3", // Klau-/Wett-/Schleich-Runden
  rad: "/audio/musik/MerryGo.mp3",
  news: "/audio/musik/LocalForecastElevator.mp3", // Zwischenstand „Börsen-News"
  erklaer: "/audio/musik/FluffingADuck.mp3", // Erklär-/Warte-Momente
};

/** Welche Musik-Ebene gehört zu welchem Minigame? (Schleich-Klassiker fürs Fiese.) */
export const MINIGAME_MUSIK: Record<string, string> = {
  taschendieb: "schleich",
  stinkbanane: "schleich",
  "bananen-tresor": "schleich",
  "alles-oder-banane": "schleich", // Wett-Runde (§4.2: Klau-/Wett-/Schleich)
};

/** Musik-Formate spielen ihr Song-Material über den Media-Kanal — das Bett
 * ist dort für die GANZE Runde STUMM (Eval 3: das weiterlaufende Bett
 * maskierte die Snippets mit SNR≈0 dB, der Duck griff ~1 s zu spät und
 * endete mitten im 5-s-Clip). „ALLE LAUSCHEN" heißt Stille — die Regie
 * schaltet hier auf Ebene null statt zu ducken (regie.musikEbene). */
export const MUSIK_STUMME_FORMATE: ReadonlySet<string> = new Set([
  "song-snippet",
  "song-rueckwaerts",
  "musikvideo-raten",
]);
