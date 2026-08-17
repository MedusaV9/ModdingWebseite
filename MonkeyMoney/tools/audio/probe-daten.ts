// Hilfs-Skript für tools/audio/probe.mjs: druckt das komplette Sound-Mapping
// (SFX + MUSIK + Standard-Buzzer) als JSON — läuft via tsx, damit die Probe
// KEINE Regex-Kopie des Mappings pflegen muss (eine Quelle der Wahrheit).
import { MUSIK, SFX, STANDARD_BUZZER } from "../../client/shared/fx/sound-map";

const daten = {
  sfx: Object.fromEntries(
    Object.entries(SFX).map(([id, def]) => [
      id,
      { dateien: def.dateien, gain: def.gain, layers: def.layers === true },
    ]),
  ),
  musik: MUSIK,
  standardBuzzer: [...STANDARD_BUZZER],
};

process.stdout.write(JSON.stringify(daten));
