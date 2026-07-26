import {Config} from '@remotion/cli/config';

Config.setVideoImageFormat('jpeg');
Config.setOverwriteOutput(true);
// Hohe Qualität, trotzdem kompakt (Ziel < 60 MB bei ~37 s 1080p60).
Config.setCrf(20);
Config.setCodec('h264');
