import {Config} from '@remotion/cli/config';

// Qualitäts-Kette (User-Feedback „pixelig“ behoben): die Quell-Clips sind
// native 1080p (CRF 14), deshalb hier KEIN verlustiges JPEG-Zwischenformat
// mehr (PNG-Frames) und ein sichtbar transparenter End-Encode mit CRF 16.
Config.setVideoImageFormat('png');
Config.setOverwriteOutput(true);
Config.setCrf(16);
Config.setCodec('h264');
