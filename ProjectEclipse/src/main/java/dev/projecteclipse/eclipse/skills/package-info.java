/**
 * Custom skill XP + ~21-node skill tree (P4-B4, plan §2.3 / R3): signal-driven action XP
 * with a fast→slow curve, config-driven earn table ({@code config/eclipse/skills.json}) and
 * tree ({@code skilltree.json}), per-save {@code eclipse_skills} SavedData, secret per-player
 * multipliers, never-OP perk hooks, advancement XP bridge and the {@code /skills} /
 * {@code /eclipse-skills} command roots. Frozen cross-worker surface: {@link
 * dev.projecteclipse.eclipse.skills.SkillsApi}.
 */
package dev.projecteclipse.eclipse.skills;
