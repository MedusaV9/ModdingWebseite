// V6/C3: v6-games.js (PLAN6 Wave C §C3 — the 6.0 minigame wave) — OWNED BY
// AGENT C3. Strings for the two new cozy games: Snail Mail („Schneckenpost",
// C2, games/snailMail.js) and Star Lantern („Sternenlaterne", C1,
// games/lanternFloat.js) — arcade-tile titles (registry level, C3) plus the
// in-game banner/floater keys handed off by C1/C2 per the appendix rule.
// Always EN + DE. No other agent may edit this module.

/** @type {Record<string, string>} */
export const EN = {
  // --- registry-level keys (C3) ---
  'mg.title.snailMail': 'Snail Mail',
  'mg.title.lanternFloat': 'Star Lantern',

  // --- C1 handoff block (lanternFloat — verbatim, appendix rule) ---
  'mg.lanternFloat.name': 'Star Lantern',
  'mg.lanternFloat.desc': 'Guide a glowing paper lantern up the night sky — through star rings, past gusts and curious fireflies.',
  'mg.lanternFloat.hint': 'Drag to steer · fly through the rings',
  'mg.lantern.hint': 'Drag to steer · fly through the rings',
  'mg.lantern.launch': 'Fly, little lantern!',
  'mg.lantern.gold': 'Golden ring!',
  'mg.lantern.gust': 'Wind gust!',
  'mg.lantern.bump': 'Cloud bump!',
  'mg.lantern.bumps': 'Bump {n}/{max}',

  // --- C2 handoff block (snailMail — verbatim, appendix rule) ---
  'mg.snailMail.name': 'Snail Mail',
  'mg.snailMail.desc': 'Draw a garden path and the little courier snail delivers the letter — around every puddle!',
  'mg.snailMail.hint': 'Draw a path from the mailbox to the glowing house · avoid puddles · flowers = bonus',
  'snail.drawHint': 'Draw a path from the mailbox!',
  'snail.startAtPost': 'Start at the mailbox!',
  'snail.wrongHouse': 'To the glowing house!',
  'snail.go': "Off you go, little snail!",
  'snail.delivered': 'Delivered!',
  'snail.dry': 'Dry delivery! +{n}',
  'snail.flower': 'Flower!',
  'snail.splash': 'Splash! Into the shell...',
  'snail.splashes': 'Splash {n}/{max}',
};

/** @type {Record<string, string>} */
export const DE = {
  // --- registry-level keys (C3) ---
  'mg.title.snailMail': 'Schneckenpost',
  'mg.title.lanternFloat': 'Sternenlaterne',

  // --- C1 handoff block (lanternFloat — verbatim, appendix rule) ---
  'mg.lanternFloat.name': 'Sternenlaterne',
  'mg.lanternFloat.desc': 'Lenke eine leuchtende Papierlaterne durch den Nachthimmel — durch Sternringe, vorbei an Böen und neugierigen Glühwürmchen.',
  'mg.lanternFloat.hint': 'Ziehen zum Lenken · flieg durch die Ringe',
  'mg.lantern.hint': 'Ziehen zum Lenken · flieg durch die Ringe',
  'mg.lantern.launch': 'Flieg, kleine Laterne!',
  'mg.lantern.gold': 'Goldener Ring!',
  'mg.lantern.gust': 'Windböe!',
  'mg.lantern.bump': 'Wolken-Rempler!',
  'mg.lantern.bumps': 'Rempler {n}/{max}',

  // --- C2 handoff block (snailMail — verbatim, appendix rule) ---
  'mg.snailMail.name': 'Schneckenpost',
  'mg.snailMail.desc': 'Zeichne einen Gartenweg und die kleine Kurier-Schnecke stellt den Brief zu — um jede Pfütze herum!',
  'mg.snailMail.hint': 'Zeichne einen Weg vom Briefkasten zum leuchtenden Haus · meide Pfützen · Blumen = Bonus',
  'snail.drawHint': 'Zeichne einen Weg vom Briefkasten!',
  'snail.startAtPost': 'Starte am Briefkasten!',
  'snail.wrongHouse': 'Zum leuchtenden Haus!',
  'snail.go': 'Los geht’s, kleine Schnecke!',
  'snail.delivered': 'Zugestellt!',
  'snail.dry': 'Trocken zugestellt! +{n}',
  'snail.flower': 'Blume!',
  'snail.splash': 'Platsch! Ab ins Haus…',
  'snail.splashes': 'Platscher {n}/{max}',
};
