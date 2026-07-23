package dev.projecteclipse.eclipse.devtools.dev;

import java.util.ArrayList;
import java.util.List;

/**
 * Config file metadata for the Dev Handbook config tab and {@link DevDocsExporter}.
 *
 * @param file        relative path under {@code config/eclipse/} or special label
 * @param purposeKey  lang key describing the file's role
 * @param layerKey    lang key for global vs per-world layer (P1 overlay when landed)
 * @param reloadStep  {@link DevReload} step index (1–6); {@code 0} = manual {@code /reload} only
 */
public record ConfigRefEntry(String file, String purposeKey, String layerKey, int reloadStep) {}
