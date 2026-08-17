// Bungee/Rubik aus dem Repo-Font-Bestand (SIL OFL, s. CREDITS.md).
// Bewusst NICHT @remotion/fonts/loadFont: dessen URL-basierter FontFace-Load
// hängt auf der VM sporadisch bei Seiten-Neustarts (delayRender-Timeout).
// Stattdessen: fetch → ArrayBuffer → FontFace (lädt synchron) mit Retries.
import { continueRender, delayRender, staticFile } from "remotion";

const ladeFont = async (family: string, file: string): Promise<void> => {
  const url = staticFile(`material/fonts/${file}`);
  let letzterFehler: unknown = null;
  for (let versuch = 0; versuch < 5; versuch++) {
    try {
      const res = await fetch(url);
      if (!res.ok) throw new Error(`HTTP ${res.status} für ${url}`);
      const buf = await res.arrayBuffer();
      const face = new FontFace(family, buf);
      document.fonts.add(face);
      return;
    } catch (e) {
      letzterFehler = e;
      await new Promise((r) => setTimeout(r, 400 * (versuch + 1)));
    }
  }
  throw new Error(`Font ${family} konnte nicht geladen werden: ${String(letzterFehler)}`);
};

if (typeof document !== "undefined") {
  // retries: hängt der Tab (VM-Flakiness), schließt Remotion ihn und
  // wiederholt den Frame mit frischem Tab statt den Render abzubrechen.
  const handle = delayRender("Fonts laden (Bungee/Bungee Shade/Rubik)", {
    retries: 3,
    timeoutInMilliseconds: 30000,
  });
  Promise.all([
    ladeFont("Bungee", "bungee.ttf"),
    ladeFont("Bungee Shade", "bungeeshade.ttf"),
    ladeFont("Rubik", "rubik.ttf"),
  ]).then(() => continueRender(handle));
}
