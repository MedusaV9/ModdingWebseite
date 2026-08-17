// FullRelease N1-C — zentrale Remotion-Defaults.
// Codec/CRF/Farbraum werden bewusst NICHT hier gesetzt, sondern explizit an
// jeder Render-Kommandozeile (npm-Scripts + CI) mitgegeben:
// `--codec=h265 --crf=23 --color-space=bt709 --muted` — so ist jeder Render
// selbst-dokumentierend und der CI-Lauf kann nicht von einer vergessenen
// Config-Zeile abweichen (RECON_REMOTION_PIPELINE.md §2.3/§6.2).
import {Config} from '@remotion/cli/config';

Config.setEntryPoint('src/index.ts');
Config.setOverwriteOutput(true);
