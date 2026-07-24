/**
 * Config-driven ore gating for the disc terrain function (D5). {@link OreField} replaces
 * hand-rolled ore tables in {@link dev.projecteclipse.eclipse.worldgen.DiscTerrainFunction};
 * {@link OreConfig} owns {@code config/eclipse/ores.json}; {@link OreGateApi} exposes band /
 * unlock metadata for P4 progression UI. {@link OreVeinShape} (B2) is the single shared
 * port of vanilla {@code OreFeature.doPlace}'s segment + sine-ellipsoid vein chain that
 * both {@link OreField} (generation) and {@link VeinTracker} (mining feel) derive from.
 */
package dev.projecteclipse.eclipse.worldgen.ore;
