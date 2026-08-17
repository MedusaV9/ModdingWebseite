// Sound-System (ART-PLAN §4): Audio-Unlock nach erster Geste (HTTP-tauglich —
// nur HTMLAudioElement, kein Secure-Context nötig), Event-SFX nach sound-map,
// Musik-Ebenen mit weichem Wechsel, Ducking (Musik leiser bei Stingern) und
// Lautstärke-Regler pro Rolle: Screen = laut, Handy = default STUMM mit Opt-in.
// ADDITIV (Musik-Welle 3): Bett-ROTATION statt fixer Ebene-Datei (BettQuelle
// aus musik-rotation.ts), Musik-Toggle getrennt vom SFX-Stumm, Skip + Ticker.
import { STANDARD_BETTEN, type BettQuelle } from "./musik-rotation";
import { MUSIK, SFX } from "./sound-map";

export interface SoundSystem {
  /** FxApi.sound() — Event-Sound abspielen (no-op vor Unlock/bei stumm).
   *  ADDITIV (Musik-Formate): akzeptiert auch Media-URLs ("/media/…",
   *  "http…") — sie laufen auf EINEM Media-Kanal (eine neue URL stoppt die
   *  vorige, Plattenspieler-Semantik) und ducken die Musik-Ebene kurz. */
  sound(sfxId: string): void;
  /** Media-Kanal anhalten (z. B. Snippet-Stopp beim Buzz). */
  stopMedia(): void;
  /** Musik-Ebene wechseln (null = Stille). Merkt sich Wünsche vor dem Unlock. */
  musik(ebene: string | null): void;
  /** Musik kurz absenken (Stinger/Ansage) — Plan §4-Ducking-Kette.
   *  faktor 0 = ECHTE Stille (Auflösungs-Dreiklang), Default 0,3 = klassisches Ducking. */
  duck(dauerMs?: number, faktor?: number): void;
  /** Erste Nutzer-Geste global abgreifen (pointerdown/keydown, einmalig). */
  unlockBeiGeste(): void;
  istEntsperrt(): boolean;
  istStumm(): boolean;
  setStumm(stumm: boolean): void;
  /** Master-Lautstärke 0–1 (skaliert SFX- und Musik-Bus gemeinsam). */
  setLautstaerke(v: number): void;
  getLautstaerke(): number;
  // ---------- Musik-Rotation (ADDITIV, Musik-Welle 3) ----------
  /** Bett-Rotation andocken (musik-rotation.ts) — null = fixe MUSIK-Map. */
  setBettQuelle(quelle: BettQuelle | null): void;
  /** „Nächster Track": Rotation der AKTUELLEN Ebene weiterschalten (no-op,
   * wenn gerade keine Musik-Ebene läuft — Musik-Formate bleiben stumm!). */
  musikSkip(): void;
  /** Aktuell rotierter Track (Ticker „♪ Titel — Artist") — null bei Stille. */
  aktuellerTrack(): { titel: string; artist: string } | null;
  /** Lokaler Musik-Toggle des Geräts (getrennt vom SFX-Stumm, persistiert). */
  istMusikAn(): boolean;
  setMusikAn(an: boolean): void;
  /** Lokale Musik-Lautstärke 0–1 (nur Bett — SFX bleiben unberührt). */
  setMusikLautstaerke(v: number): void;
  getMusikLautstaerke(): number;
  /** Match-Setting (GM): musik an/aus + Show-Volume — kommt aus dem View. */
  setMatchMusik(an: boolean, volume: number): void;
  istMatchMusikAn(): boolean;
  /** UI-Benachrichtigung bei Track-/Zustands-Wechsel (Ticker neu zeichnen). */
  onTrackWechsel(cb: () => void): void;
}

const jetzt = (): number => performance.now();

interface RollenProfil {
  sfx: number;
  musik: number;
  stummDefault: boolean;
}

const PROFILE: Record<string, RollenProfil> = {
  screen: { sfx: 0.9, musik: 0.4, stummDefault: false },
  player: { sfx: 0.7, musik: 0, stummDefault: true }, // Opt-in am Handy
  gm: { sfx: 0.5, musik: 0, stummDefault: true },
};

export function createSoundSystem(rolle: "screen" | "player" | "gm"): SoundSystem {
  const profil = PROFILE[rolle];
  const speicherKey = `mm:sound:${rolle}`;
  let entsperrt = false;
  let stumm = profil.stummDefault;
  let master = 1;
  // Musik-Welle 3: lokaler Musik-Toggle + Musik-Volume (persistiert, getrennt
  // vom SFX-Stumm) und das Match-Setting des GM (kommt aus dem View).
  let musikAn = true;
  let musikVol = 1;
  let matchMusikAn = true;
  let matchMusikVol = 1;
  try {
    const raw = localStorage.getItem(speicherKey);
    if (raw) {
      const s = JSON.parse(raw) as {
        stumm?: boolean;
        master?: number;
        musikAn?: boolean;
        musikVol?: number;
      };
      if (typeof s.stumm === "boolean") stumm = s.stumm;
      if (typeof s.master === "number") master = Math.min(1, Math.max(0, s.master));
      if (typeof s.musikAn === "boolean") musikAn = s.musikAn;
      if (typeof s.musikVol === "number") musikVol = Math.min(1, Math.max(0, s.musikVol));
    }
  } catch {
    /* localStorage kann fehlen (Private Mode) — Defaults reichen */
  }

  const speichern = (): void => {
    try {
      localStorage.setItem(speicherKey, JSON.stringify({ stumm, master, musikAn, musikVol }));
    } catch {
      /* egal */
    }
  };

  // ---------- Musik-Bus (Ebene + Rotation + weicher Wechsel + Ducking) ----------
  let musikEl: HTMLAudioElement | null = null;
  let aktuelleEbene: string | null = null;
  let gewuenschteEbene: string | null = null;
  let duckBis = 0;
  let duckFaktor = 0.3;
  let fadeTimer: ReturnType<typeof setInterval> | null = null;
  // Musik-Welle 3: Bett-Rotation (musik-rotation.ts) + Ticker-Zustand.
  let bettQuelle: BettQuelle | null = null;
  let spieltTrack: { titel: string; artist: string } | null = null;
  const trackHoerer: (() => void)[] = [];

  function benachrichtige(): void {
    for (const cb of trackHoerer) cb();
  }

  function musikZielVolumen(): number {
    const basis = profil.musik * master * musikVol * matchMusikVol;
    return jetzt() < duckBis ? basis * duckFaktor : basis;
  }

  function starteFade(): void {
    if (fadeTimer !== null) return;
    fadeTimer = setInterval(() => {
      if (!musikEl) return;
      const ziel = stumm ? 0 : musikZielVolumen();
      const diff = ziel - musikEl.volume;
      if (Math.abs(diff) < 0.015 && jetzt() >= duckBis) {
        musikEl.volume = ziel;
        if (fadeTimer !== null) clearInterval(fadeTimer);
        fadeTimer = null;
        return;
      }
      musikEl.volume = Math.min(1, Math.max(0, musikEl.volume + diff * 0.25));
    }, 90);
  }

  function spieleEbene(ebene: string | null): void {
    aktuelleEbene = ebene;
    if (!musikEl) {
      musikEl = new Audio();
      musikEl.loop = true;
      musikEl.volume = 0;
      // Rotation: Track zu Ende (loop=false bei > 1 Track) ⇒ nächster Track
      // derselben Ebene — nahtlose Playlist statt Dauerschleife.
      musikEl.addEventListener("ended", () => {
        if (aktuelleEbene === null || bettQuelle === null) return;
        bettQuelle.weiter(aktuelleEbene);
        spieleEbene(aktuelleEbene);
      });
    }
    // Musik-Toggle (lokal) + Match-Setting (GM) sitzen ÜBER der Rotation —
    // beide betreffen NUR das Bett, SFX/Media laufen unabhängig weiter.
    if (ebene === null || stumm || !musikAn || !matchMusikAn || profil.musik === 0) {
      musikEl.pause();
      if (spieltTrack !== null && (ebene === null || !musikAn || !matchMusikAn)) {
        spieltTrack = null;
        benachrichtige();
      }
      return;
    }
    const track = bettQuelle?.trackFuer(ebene) ?? null;
    const src = track?.url ?? MUSIK[ebene];
    if (!src) return;
    const absolut = new URL(src, window.location.origin).href;
    if (musikEl.src !== absolut) {
      musikEl.src = absolut;
      musikEl.volume = 0;
    }
    musikEl.loop = track?.loop ?? true;
    const info =
      track !== null ? { titel: track.titel, artist: track.artist } : bekannterTrack(ebene);
    if (info?.titel !== spieltTrack?.titel || info?.artist !== spieltTrack?.artist) {
      spieltTrack = info;
      benachrichtige();
    }
    void musikEl.play().catch(() => {
      /* Autoplay blockiert — nächste Geste holt es nach */
    });
    starteFade();
  }

  /** Ticker-Fallback ohne Rotation: die 6 MacLeod-Betten sind bekannt. */
  function bekannterTrack(ebene: string): { titel: string; artist: string } | null {
    const std = STANDARD_BETTEN[ebene];
    return std !== undefined ? { titel: std.titel, artist: std.artist } : null;
  }

  // ---------- Media-Bus (ADDITIV, Musik-Formate): beliebige URLs ----------
  // EIN Kanal wie ein Plattenspieler: eine neue URL stoppt die vorige — so
  // überlappen Song-Snippet-Stufen und die Vorwärts-Auflösung nie. Lautstärke
  // hängt am SFX-Profil der Rolle (Screen laut, Handy default stumm).
  let mediaEl: HTMLAudioElement | null = null;

  function istMediaUrl(id: string): boolean {
    return id.startsWith("/") || id.startsWith("http://") || id.startsWith("https://");
  }

  function spieleMedia(url: string): void {
    if (!mediaEl) mediaEl = new Audio();
    mediaEl.pause();
    mediaEl.src = new URL(url, window.location.origin).href;
    mediaEl.currentTime = 0;
    mediaEl.volume = Math.min(1, profil.sfx * master);
    duckBis = jetzt() + 1_500; // Musik weicht dem Song-Material
    starteFade();
    void mediaEl.play().catch(() => {
      /* Autoplay blockiert — nächste Geste holt es nach */
    });
  }

  // ---------- SFX-Bus (Round-Robin-Varianten, Parallel-Deckel) ----------
  const rr = new Map<string, number>();
  let aktiveSfx = 0;
  // Anti-Stapel-Regel (Eval 3): dieselbe Sound-Id stoppt ihren noch laufenden
  // Vorgänger — 17-s-Applaus-Dateien stapelten sich sonst über mehrere
  // Auflösungen (5 gleichzeitige Elemente), bis der 8-Stimmen-Deckel alles
  // Weitere schluckte. Für kurze SFX ist der Vorgänger längst zu Ende (no-op).
  const laufende = new Map<string, (() => void)[]>();

  function stoppeVorgaenger(sfxId: string): void {
    const stopps = laufende.get(sfxId);
    if (!stopps) return;
    laufende.delete(sfxId);
    for (const stopp of stopps) stopp();
  }

  function sound(sfxId: string): void {
    if (!entsperrt || stumm) return;
    if (istMediaUrl(sfxId)) {
      spieleMedia(sfxId);
      return;
    }
    const def = SFX[sfxId];
    if (!def) return;
    stoppeVorgaenger(sfxId);
    if (aktiveSfx >= 8) return;
    // Layer-Defs spielen ALLE Dateien gleichzeitig (Plan-Notation „A + B"),
    // sonst Round-Robin durch die Varianten (kein Zufall — Rng-Disziplin).
    let dateien: string[];
    if (def.layers) {
      dateien = def.dateien;
    } else {
      const i = rr.get(sfxId) ?? 0;
      rr.set(sfxId, i + 1);
      dateien = [def.dateien[i % def.dateien.length]];
    }
    const stopps: (() => void)[] = [];
    for (const src of dateien) {
      if (aktiveSfx >= 8) break;
      const el = new Audio(src);
      el.volume = Math.min(1, def.gain * profil.sfx * master);
      aktiveSfx += 1;
      let vorbei = false;
      const fertig = (): void => {
        if (vorbei) return;
        vorbei = true;
        aktiveSfx = Math.max(0, aktiveSfx - 1);
      };
      el.addEventListener("ended", fertig, { once: true });
      el.addEventListener("error", fertig, { once: true });
      stopps.push(() => {
        el.pause();
        fertig();
      });
      void el.play().catch(fertig);
    }
    laufende.set(sfxId, stopps);
  }

  function entsperren(): void {
    if (entsperrt) return;
    entsperrt = true;
    spieleEbene(gewuenschteEbene);
  }

  return {
    sound,
    stopMedia() {
      mediaEl?.pause();
    },
    musik(ebene) {
      gewuenschteEbene = ebene;
      if (!entsperrt) return;
      if (ebene !== aktuelleEbene) spieleEbene(ebene);
    },
    duck(dauerMs = 1200, faktor = 0.3) {
      duckBis = jetzt() + dauerMs;
      duckFaktor = faktor;
      starteFade();
    },
    unlockBeiGeste() {
      const geste = (): void => {
        entsperren();
        window.removeEventListener("pointerdown", geste);
        window.removeEventListener("keydown", geste);
      };
      window.addEventListener("pointerdown", geste, { passive: true });
      window.addEventListener("keydown", geste);
    },
    istEntsperrt: () => entsperrt,
    istStumm: () => stumm,
    setStumm(neu) {
      stumm = neu;
      speichern();
      if (stumm) {
        musikEl?.pause();
        mediaEl?.pause();
      } else if (entsperrt) spieleEbene(gewuenschteEbene);
    },
    setLautstaerke(v) {
      master = Math.min(1, Math.max(0, v));
      speichern();
      starteFade();
    },
    getLautstaerke: () => master,
    // ---------- Musik-Rotation (ADDITIV, Musik-Welle 3) ----------
    setBettQuelle(quelle) {
      bettQuelle = quelle;
      if (entsperrt) spieleEbene(gewuenschteEbene);
    },
    musikSkip() {
      // Kein Skip in Musik-Formaten: Ebene null heißt „Bett bewusst stumm"
      // (MUSIK_STUMME_FORMATE) — die Rotation darf da nichts anfassen.
      if (aktuelleEbene === null || bettQuelle === null) return;
      bettQuelle.weiter(aktuelleEbene);
      if (entsperrt) spieleEbene(aktuelleEbene);
    },
    aktuellerTrack: () => spieltTrack,
    istMusikAn: () => musikAn,
    setMusikAn(an) {
      musikAn = an;
      speichern();
      if (entsperrt) spieleEbene(gewuenschteEbene);
      benachrichtige();
    },
    setMusikLautstaerke(v) {
      musikVol = Math.min(1, Math.max(0, v));
      speichern();
      starteFade();
    },
    getMusikLautstaerke: () => musikVol,
    setMatchMusik(an, volume) {
      const geaendert = an !== matchMusikAn || volume !== matchMusikVol;
      matchMusikAn = an;
      matchMusikVol = Math.min(1, Math.max(0, volume));
      if (!geaendert) return;
      if (entsperrt) spieleEbene(gewuenschteEbene);
      starteFade();
      benachrichtige();
    },
    istMatchMusikAn: () => matchMusikAn,
    onTrackWechsel(cb) {
      trackHoerer.push(cb);
    },
  };
}
