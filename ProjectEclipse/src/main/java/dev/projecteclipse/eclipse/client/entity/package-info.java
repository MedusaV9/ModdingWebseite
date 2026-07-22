/**
 * Client half of the v2 custom mobs: hand-coded cube models
 * ({@code MeshDefinition}/{@code CubeListBuilder}, no Blockbench files), procedural
 * animations in {@code setupAnim}, and renderers (including emissive
 * {@code RenderType.eyes} layers). Layer definitions and renderer bindings are registered
 * in {@link dev.projecteclipse.eclipse.client.entity.EclipseEntityRenderers}. Every cube's
 * UV layout is documented in {@code docs/uv/<mob>.md} so the orchestrator can generate
 * final textures against the exact pixel rects.
 */
package dev.projecteclipse.eclipse.client.entity;
