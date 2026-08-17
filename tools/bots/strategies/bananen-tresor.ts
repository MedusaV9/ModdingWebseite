// Bot-Strategie „Der Bananen-Tresor" (Schätzrunde, GAME-DESIGN §2.3): Skill ∈ [0,1]
// steuert den relativen Schätzfehler (Könner ±5 %, Chaoten bis ±50 %); Blitz-Berta
// landet gelegentlich den Volltreffer (Jackpot-Pfad). Die Bots „schieben" den
// Slider wie Menschen: mehrere tipp-Gesten Richtung Ziel, dann einloggen.
// Edge-Case eingebaut: Zauderer-Zilli loggt NIE ein — ihr letzter Slider-Stand
// zählt trotzdem (§2.3), und die Runde läuft deshalb bis zum Timer-Ende (20 s).
//
// Lauf:  npx tsx tools/bots/strategies/bananen-tresor.ts [--port 8092] [--seed 11] [--fragen 3]
import { setTimeout as delay } from "node:timers/promises";
import { bananenTresorPlugin } from "../../../server/minigames/bananen-tresor/index";
import { BANANEN_TRESOR_ID } from "../../../shared/minigames/bananen-tresor.meta";
import { createRng, type Rng } from "../../../shared/rng";
import {
  parseLaufArgs,
  runBotLauf,
  type BotProfil,
  type Strategie,
} from "./_runner-uhr-tresor-leiter";

function tresorStrategie(skill: number, rng: Rng, zaudert: boolean): Strategie {
  return async (ktx) => {
    const v = ktx.playerView as { eingabeMin: number; eingabeMax: number; einheit: string };
    const zettel = await ktx.spickzettel();
    const richtwert = Number(zettel.richtwert);

    // Relativer Fehler ~ (1 − Skill); Vorzeichen zufällig; Volltreffer-Chance
    // für echte Könner (zeigt den 1.000-MM-Jackpot-Pfad im Log).
    let ziel: number;
    if (skill >= 0.85 && rng.next() < 0.3) {
      ziel = richtwert;
    } else {
      const relFehler = (1 - skill) * (0.05 + rng.next() * 0.45);
      const vorzeichen = rng.next() < 0.5 ? -1 : 1;
      ziel = Math.round(richtwert * (1 + vorzeichen * relFehler));
    }
    ziel = Math.min(v.eingabeMax, Math.max(v.eingabeMin, ziel));

    // Menschliche Slider-Geste: von der Mitte in 2–3 Schüben aufs Ziel zu.
    let stand = Math.round((v.eingabeMin + v.eingabeMax) / 2);
    const schuebe = 2 + rng.int(2);
    for (let s = 1; s <= schuebe; s++) {
      stand = Math.round(stand + ((ziel - stand) * s) / schuebe);
      await delay(700 + rng.int(1400));
      if (!ktx.aktiv()) return;
      await ktx.sende("tipp", { wert: stand });
    }

    if (zaudert) {
      ktx.log(`lässt den Slider bei ${stand} ${v.einheit} stehen und loggt NIE ein`);
      return;
    }
    await delay(400 + rng.int(1100));
    if (!ktx.aktiv()) return;
    await ktx.sende("einloggen", { wert: ziel });
    ktx.log(
      `loggt ${ziel} ${v.einheit} ein` +
        (ziel === richtwert ? " — VOLLTREFFER-Versuch!" : ` (Richtwert wäre ${richtwert})`),
    );
  };
}

async function main(): Promise<void> {
  const args = parseLaufArgs(process.argv.slice(2));
  const seed = args.seed ?? 11;
  const skills = [
    { name: "Blitz-Berta", skill: 0.9, avatar: "gelb", zaudert: false },
    { name: "Solide-Susi", skill: 0.6, avatar: "rot", zaudert: false },
    { name: "Bauch-Bodo", skill: 0.35, avatar: "gruen", zaudert: false },
    { name: "Zauderer-Zilli", skill: 0.5, avatar: "blau", zaudert: true },
  ];
  const profile: BotProfil[] = skills.map((s, i) => ({
    name: s.name,
    skill: s.skill,
    avatar: s.avatar,
    strategie: tresorStrategie(s.skill, createRng(seed * 31 + i), s.zaudert),
  }));

  await runBotLauf({
    spielName: "Der Bananen-Tresor",
    minigameId: BANANEN_TRESOR_ID,
    plugin: bananenTresorPlugin,
    port: args.port ?? 8092,
    seed,
    fragen: args.fragen ?? 3,
    profile,
  });
}

main().catch((err: unknown) => {
  console.error("[bananen-tresor-bots] Abbruch:", err);
  process.exit(1);
});
