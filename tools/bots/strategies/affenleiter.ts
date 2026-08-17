// Bot-Strategie „Affenleiter" (Sortieren, GAME-DESIGN §2.4): Skill ∈ [0,1] steuert
// die Sortier-Güte — Könner legen die perfekte Leiter (×1,5 + Speed-Bonus),
// Mittelfeld vertauscht einen Nachbarn (2 von 4 richtig = Teilpunkte), Chaoten
// würfeln doppelt. Die Bots senden erst einen Zwischenstand (sortierung), dann
// loggen sie ein — außer Wackel-Willi auf Frage 1: er gibt NIE ab und beweist
// damit „keine Abgabe = aktueller Stand zählt" (§2.4, Runde läuft bis 30 s).
//
// Lauf:  npx tsx tools/bots/strategies/affenleiter.ts [--port 8093] [--seed 13] [--fragen 3]
import { setTimeout as delay } from "node:timers/promises";
import { affenleiterPlugin } from "../../../server/minigames/affenleiter/index";
import { AFFENLEITER_ID } from "../../../shared/minigames/affenleiter.meta";
import { createRng, type Rng } from "../../../shared/rng";
import {
  parseLaufArgs,
  runBotLauf,
  type BotProfil,
  type Strategie,
} from "./_runner-uhr-tresor-leiter";

function nachbarSwap(reihenfolge: number[], rng: Rng, verboten?: number): number {
  let i = rng.int(3);
  if (verboten !== undefined && i === verboten) i = (i + 1) % 3;
  [reihenfolge[i], reihenfolge[i + 1]] = [reihenfolge[i + 1], reihenfolge[i]];
  return i;
}

function leiterStrategie(skill: number, rng: Rng, gibtNieAbAufFrage1: boolean): Strategie {
  return async (ktx) => {
    const v = ktx.playerView as { yourStart?: number[]; timerMs?: number };
    const timerMs = Number(v.timerMs ?? 30_000);
    const zettel = await ktx.spickzettel();
    const korrekt = zettel.korrektReihenfolge as number[];

    // Ziel-Sortierung: perfekt, 1 Nachbar-Swap (2 richtig) oder 2 Swaps (Chaos).
    const ziel = [...korrekt];
    const wurf = rng.next();
    if (wurf >= skill) {
      const erster = nachbarSwap(ziel, rng);
      if (wurf >= skill + (1 - skill) * 0.5) nachbarSwap(ziel, rng, erster);
    }

    // Denk-/Zieh-Zeit: Könner sind nach ~10–20 % fertig (Speed-Bonus!), Chaoten
    // brauchen bis ~60 % des 30-s-Fensters.
    const anteil = Math.min(0.75, 0.1 + (1 - skill) * 0.45 + rng.next() * 0.1);
    const halbzeit = Math.round((timerMs * anteil) / 2);

    // Zwischenstand nach halber Denkzeit: Start-Reihenfolge mit erstem Griff.
    const zwischen = [...(v.yourStart ?? [0, 1, 2, 3])];
    nachbarSwap(zwischen, rng);
    await delay(halbzeit);
    if (!ktx.aktiv()) return;
    await ktx.sende("sortierung", { reihenfolge: zwischen });

    await delay(halbzeit);
    if (!ktx.aktiv()) return;
    if (gibtNieAbAufFrage1 && ktx.frageNr === 1) {
      await ktx.sende("sortierung", { reihenfolge: ziel });
      ktx.log(`sortiert [${ziel.join(",")}], gibt aber NIE ab (Stand zählt trotzdem)`);
      return;
    }
    await ktx.sende("einloggen", { reihenfolge: ziel });
    const richtige = ziel.filter((e, i) => e === korrekt[i]).length;
    ktx.log(
      `loggt die Leiter [${ziel.join(",")}] nach ${halbzeit * 2} ms ein` +
        ` (${richtige}/4 richtig${richtige === 4 ? " — PERFEKT" : ""})`,
    );
  };
}

async function main(): Promise<void> {
  const args = parseLaufArgs(process.argv.slice(2));
  const seed = args.seed ?? 13;
  const skills = [
    { name: "Blitz-Berta", skill: 0.92, avatar: "gelb", nieAb: false },
    { name: "Solide-Susi", skill: 0.6, avatar: "rot", nieAb: false },
    { name: "Chaos-Carlo", skill: 0.2, avatar: "gruen", nieAb: false },
    { name: "Wackel-Willi", skill: 0.5, avatar: "blau", nieAb: true },
  ];
  const profile: BotProfil[] = skills.map((s, i) => ({
    name: s.name,
    skill: s.skill,
    avatar: s.avatar,
    strategie: leiterStrategie(s.skill, createRng(seed * 31 + i), s.nieAb),
  }));

  await runBotLauf({
    spielName: "Affenleiter",
    minigameId: AFFENLEITER_ID,
    plugin: affenleiterPlugin,
    port: args.port ?? 8093,
    seed,
    fragen: args.fragen ?? 3,
    profile,
  });
}

main().catch((err: unknown) => {
  console.error("[affenleiter-bots] Abbruch:", err);
  process.exit(1);
});
