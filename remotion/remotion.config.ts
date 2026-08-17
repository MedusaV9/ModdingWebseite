import { Config } from "@remotion/cli/config";

Config.setEntryPoint("src/index.ts");
// Font-/Bild-Laden auf der schwachen VM kann >28 s dauern (Standard-Timeout).
Config.setDelayRenderTimeoutInMilliseconds(120000);
// Installiertes Chrome statt Headless-Shell-Download (VM hat wenig Platz/Netz).
// chrome-for-testing-Modus: volles Chrome im neuen Headless-Modus (der
// Default „headless-shell" passt nicht zum vollen Chrome-Binary).
Config.setBrowserExecutable("/usr/bin/google-chrome-stable");
Config.setChromeMode("chrome-for-testing");
Config.setChromiumOpenGlRenderer("angle-egl");
// Wenige Kerne auf der VM — nicht überparallelisieren.
Config.setConcurrency(2);
Config.setVideoImageFormat("jpeg");
Config.setOverwriteOutput(true);
// h264 als Standard-Codec; CRF wird pro Render-Aufruf gesetzt (--crf=21),
// weil der WAV-Audio-Pass des Chunk-Skripts kein CRF akzeptiert.
Config.setCodec("h264");
