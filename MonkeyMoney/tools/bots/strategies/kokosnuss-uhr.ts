// Bot-Strategie „Stopp die Kokosnuss-Uhr" (GAME-DESIGN §2.2): Der Sack schrumpft
// in 50-MM-Ticks — wer früh stoppt, friert viel ein, riskiert aber Fehler.
// Skill ∈ [0,1] steuert BEIDES: Stopp-Zeitpunkt (Könner früh, Träumer spät)
// und Trefferquote (0.25 Ratebasis → ~0.97). Der Spickzettel kommt aus dem
// GM-View, denn Spieler-Bots sehen die Lösung nicht (Leak-Schutz).
//
// Lauf:  npx tsx tools/bots/strategies/kokosnuss-uhr.ts [--port 8091] [--seed 7] [--fragen 3]
import { setTimeout as delay } from "node:timers/promises";
import { kokosnussUhrPlugin } from "../../../server/minigames/kokosnuss-uhr/index";
import { KOKOSNUSS_UHR_ID } from "../../../shared/minigames/kokosnuss-uhr.meta";
import { createRng, type Rng } from "../../../shared/rng";
import {
  parseLaufArgs,
  runBotLauf,
  type BotProfil,
  type Strategie,
} from "./_runner-uhr-tresor-leiter";

const BUCHSTABEN = ["A", "B", "C", "D"] as const;

function uhrStrategie(skill: number, rng: Rng): Strategie {
  return async (ktx) => {
    const view = ktx.playerView as { timerMs?: number };
    const timerMs = Number(view.timerMs ?? 15_000);
    // Stopp-Zeitpunkt: Könner nach ~8–20 % des Timers (fetter Sack), Träumer
    // grübeln bis ~60–75 % (der Sack ist dann fast leer) — nie über 90 %.
    const anteil = Math.min(0.9, 0.08 + (1 - skill) * 0.55 + rng.next() * 0.12);
    const wartezeit = Math.round(timerMs * anteil);

    const zettel = await ktx.spickzettel();
    const richtig = Number(zettel.correctIndex);
    const trifft = rng.next() < 0.25 + 0.72 * skill;
    let choice = richtig;
    if (!trifft) {
      const falsche = [0, 1, 2, 3].filter((i) => i !== richtig);
      choice = falsche[rng.int(falsche.length)];
    }

    await delay(wartezeit);
    if (!ktx.aktiv()) return; // Runde schon vorbei (GM-Skip o. Ä.) — nichts senden.
    await ktx.sende("answer", { choice });
    ktx.log(
      `stoppt die Uhr nach ${wartezeit} ms (${Math.round(anteil * 100)} % des Timers)` +
        ` und tippt ${BUCHSTABEN[choice]}${trifft ? "" : " (verzockt!)"}`,
    );
  };
}

async function main(): Promise<void> {
  const args = parseLaufArgs(process.argv.slice(2));
  const seed = args.seed ?? 7;
  const skills = [
    { name: "Blitz-Berta", skill: 0.9, avatar: "gelb" },
    { name: "Solide-Susi", skill: 0.65, avatar: "rot" },
    { name: "Zocker-Zeno", skill: 0.4, avatar: "gruen" },
    { name: "Traeumer-Theo", skill: 0.15, avatar: "blau" },
  ];
  const profile: BotProfil[] = skills.map((s, i) => ({
    ...s,
    strategie: uhrStrategie(s.skill, createRng(seed * 31 + i)),
  }));

  await runBotLauf({
    spielName: "Stopp die Kokosnuss-Uhr",
    minigameId: KOKOSNUSS_UHR_ID,
    plugin: kokosnussUhrPlugin,
    port: args.port ?? 8091,
    seed,
    fragen: args.fragen ?? 3,
    profile,
  });
}

main().catch((err: unknown) => {
  console.error("[kokosnuss-uhr-bots] Abbruch:", err);
  process.exit(1);
});
