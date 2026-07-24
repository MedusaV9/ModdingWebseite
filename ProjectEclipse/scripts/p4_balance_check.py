#!/usr/bin/env python3
"""Validate Eclipse P4 authored defaults after a server has generated runtime JSON.

Run from the ProjectEclipse root:
    python3 scripts/p4_balance_check.py --strict
    python3 scripts/p4_balance_check.py --config-dir run/config/eclipse --strict

Without --strict, a missing runtime config directory falls back to source-shape checks. This
keeps the checker useful before a server boot while making CI/orchestrator validation explicit.
"""

from __future__ import annotations

import argparse
import json
import math
import re
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
ADVANCEMENT_DIR = ROOT / "src/main/resources/data/eclipse/advancement/event"
LANGDROP = ROOT / "docs/plans_v3/langdrop/WB-CONTENT.json"

TRIGGER_IDS = {
    "collect_item",
    "craft_item",
    "smelt_item",
    "kill_entity",
    "mine_block",
    "place_blocks",
    "deposit_altar",
    "visit_location",
    "visit_biomes",
    "explore_chunks",
    "reach_depth",
    "travel_distance",
    "breed_animals",
    "stat_threshold",
    "survive_night_no_damage",
    "skill_level",
    "manual",
}

ANALYTICS_KEYS = {
    "kill_total",
    "death",
    "dmg_dealt",
    "dmg_taken",
    "mine_total",
    "place_total",
    "place_types",
    "craft_total",
    "smelt_total",
    "dist_cm",
    "biomes",
    "chunks_new",
    "playtime_s",
    "depth_min_y",
    "breed_total",
    "trade_total",
    "altar_value",
    "shards_banked",
    "quests_done",
    "mains_done",
    "sides_done",
    "personals_done",
}
DYNAMIC_ANALYTICS_PREFIXES = ("kill:", "mine:", "craft:")
ADVANCEMENT_TRIGGERS = {
    "minecraft:tick",
    "minecraft:impossible",
    "minecraft:inventory_changed",
    "minecraft:recipe_crafted",
    "minecraft:changed_dimension",
    "minecraft:location",
    "minecraft:player_killed_entity",
}

RUNTIME_FILES = (
    "goals.json",
    "quests.json",
    "milestones.json",
    "offering_values.json",
    "awards.json",
    "recipegate.json",
    "skills.json",
    "skilltree.json",
    "buffs.json",
)


class Checks:
    def __init__(self) -> None:
        self.errors: list[str] = []
        self.warnings: list[str] = []

    def require(self, condition: bool, message: str) -> None:
        if not condition:
            self.errors.append(message)

    def warn(self, condition: bool, message: str) -> None:
        if not condition:
            self.warnings.append(message)


def read_json(path: Path) -> Any:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def localized_pair(value: Any) -> bool:
    # Localized.toJsonElement intentionally emits one string when en == de; the loader treats
    # that representation as the fallback for both locales.
    if isinstance(value, str):
        return bool(value.strip())
    return (
        isinstance(value, dict)
        and isinstance(value.get("en"), str)
        and bool(value["en"].strip())
        and isinstance(value.get("de"), str)
        and bool(value["de"].strip())
    )


def validate_goals(config_dir: Path, checks: Checks) -> None:
    root = read_json(config_dir / "goals.json")
    days = root.get("days", [])
    by_day = {entry.get("day"): entry.get("goals", []) for entry in days}
    checks.require(set(range(1, 15)).issubset(by_day), "goals.json must cover days 1..14")

    shard_specs = 0
    trigger_use: set[str] = set()
    for day in range(1, 15):
        goals = by_day.get(day, [])
        mains = [goal for goal in goals if goal.get("kind") == "main"]
        sides = [goal for goal in goals if goal.get("kind") == "side"]
        checks.require(len(mains) == 3, f"day {day}: expected exactly 3 mains, got {len(mains)}")
        checks.require(3 <= len(sides) <= 5, f"day {day}: expected 3-5 sides, got {len(sides)}")
        for goal in goals:
            trigger = goal.get("trigger", {})
            trigger_id = trigger.get("type")
            checks.require(trigger_id in TRIGGER_IDS, f"{goal.get('id')}: invalid trigger {trigger_id!r}")
            if trigger_id in TRIGGER_IDS:
                trigger_use.add(trigger_id)
            checks.require(localized_pair(goal.get("text")), f"{goal.get('id')}: missing en/de text")
            reward = goal.get("reward", {})
            checks.require(reward.get("skillXp", 0) > 0, f"{goal.get('id')}: skillXp must be positive")
            if reward.get("shards", 0) > 0 or any(
                item.get("id") == "eclipse:umbral_shard" for item in reward.get("items", [])
            ):
                shard_specs += 1

    checks.require(len(trigger_use) >= 12, f"authored day goals use only {len(trigger_use)} trigger types")
    checks.require(shard_specs >= 8, f"expected at least 8 shard-bearing day rewards, got {shard_specs}")

    quests_root = read_json(config_dir / "quests.json")
    quests = quests_root.get("quests", [])
    checks.require(len(quests) >= 24, f"personal quest pool must contain >=24 entries, got {len(quests)}")
    for quest in quests:
        quest_id = quest.get("id")
        checks.require(quest.get("kind") == "personal", f"{quest_id}: kind must be personal")
        checks.require(quest.get("weight", 0) > 0, f"{quest_id}: weight must be positive")
        checks.require(
            quest.get("trigger", {}).get("type") in TRIGGER_IDS,
            f"{quest_id}: invalid personal trigger",
        )
        checks.require(localized_pair(quest.get("text")), f"{quest_id}: missing en/de text")
        checks.require(quest.get("reward", {}).get("skillXp", 0) > 0, f"{quest_id}: missing skill XP")

    print(
        f"goals: {len(by_day)} days, "
        f"{sum(len(v) for v in by_day.values())} day goals, {len(quests)} personals, "
        f"{len(trigger_use)}/17 trigger types used"
    )


def java_round(value: float) -> int:
    return math.floor(value + 0.5)


def cumulative_xp(level: int, curve: dict[str, Any]) -> int:
    base = float(curve["baseCost"])
    exponent = float(curve["exponent"])
    softcap = int(curve["softcapLevel"])
    softcap_mult = float(curve["softcapMult"])
    power = exponent + 1.0

    def raw(target: int) -> float:
        return base * target**power / power if target > 0 else 0.0

    if level <= softcap:
        return java_round(raw(level))
    at_cap = raw(softcap)
    return java_round(at_cap + softcap_mult * (raw(level) - at_cap))


def table_value(table: dict[str, Any], key: str) -> float:
    return float(table.get(key, table.get("default", 0)))


def validate_skills(config_dir: Path, checks: Checks) -> None:
    skills = read_json(config_dir / "skills.json")
    curve = skills["curve"]
    costs = [cumulative_xp(level, curve) - cumulative_xp(level - 1, curve) for level in range(1, 101)]
    checks.require(all(cost > 0 for cost in costs), "skill XP costs must remain positive")
    checks.require(
        all(right >= left for left, right in zip(costs, costs[1:])),
        "skill XP costs must be monotonic",
    )
    level_12 = cumulative_xp(12, curve)
    checks.require(2518 <= level_12 <= 2782, f"C(12) must be ~2650 +/-5%, got {level_12}")

    xp = skills["xp"]
    mining = (
        300 * table_value(xp["mine"], "minecraft:stone")
        + 20 * table_value(xp["mine"], "#minecraft:coal_ores")
        + 12 * table_value(xp["mine"], "#minecraft:iron_ores")
        + 6 * table_value(xp["mine"], "#minecraft:gold_ores")
        + 2 * table_value(xp["mine"], "#minecraft:diamond_ores")
    )
    combat = 12 * table_value(xp["kill"], "minecraft:zombie")
    exploration = 20 * float(xp["exploreChunk"])
    representative_quest = 150
    hourly = mining + combat + exploration + representative_quest
    checks.require(600 <= hourly <= 800, f"representative active XP/hour must be 600-800, got {hourly:g}")
    advancement_table = xp.get("advancements", {})
    advancement_ids = {path.stem for path in ADVANCEMENT_DIR.glob("*.json")}
    missing_xp = sorted(
        advancement_id
        for advancement_id in advancement_ids
        if f"eclipse:{advancement_id}" not in advancement_table
    )
    checks.require(not missing_xp, f"advancements missing explicit skill XP mappings: {missing_xp}")

    tree = read_json(config_dir / "skilltree.json")
    nodes = tree.get("nodes", [])
    ids = {node.get("id") for node in nodes}
    checks.require(24 <= len(nodes) <= 28, f"skill tree must contain 24-28 nodes, got {len(nodes)}")
    checks.require(len(ids) == len(nodes), "skill tree node ids must be unique")
    for node in nodes:
        for requirement in node.get("requires", []):
            checks.require(requirement in ids, f"{node.get('id')}: unknown prerequisite {requirement}")
        checks.require(localized_pair(node.get("title")), f"{node.get('id')}: missing en/de title")
        checks.require(localized_pair(node.get("desc")), f"{node.get('id')}: missing en/de description")

    print(
        f"skills: C(12)={level_12}, C(50)={cumulative_xp(50, curve)}, "
        f"simulated active hour={hourly:g} XP "
        f"(mine {mining:g} + combat {combat:g} + explore {exploration:g} + quest {representative_quest}), "
        f"tree={len(nodes)} nodes"
    )


def validate_offerings(config_dir: Path, checks: Checks) -> None:
    data = read_json(config_dir / "offering_values.json")
    tiers = data.get("tiers", {})
    items = data.get("byItem", {})
    junk = data.get("junk", [])
    checks.require(75 <= len(items) <= 120, f"offering table should have ~80 explicit items, got {len(items)}")
    checks.require(float(data.get("enchantedMultiplier", 0)) > 1.0, "enchanted multiplier must exceed 1")
    checks.require(tiers.get(data.get("default")) == 0, "default offering tier must resolve to zero")
    for item_id in junk:
        tier = items.get(item_id)
        checks.require(tier in tiers and tiers[tier] == 0, f"junk item {item_id} must explicitly resolve to 0")
    checks.require(
        tiers.get(items.get("minecraft:diamond"), 0) >= 100,
        "diamonds must be high-value offerings",
    )
    print(f"offerings: {len(items)} explicit items, {len(data.get('byTag', {}))} tags, {len(junk)} junk ids")


def valid_analytics_metric(metric: str) -> bool:
    if metric in ANALYTICS_KEYS:
        return True
    if metric in {"kill:$mob", "mine:$ore"}:
        return True
    return any(metric.startswith(prefix) and len(metric) > len(prefix) for prefix in DYNAMIC_ANALYTICS_PREFIXES)


def validate_awards(config_dir: Path, checks: Checks) -> None:
    data = read_json(config_dir / "awards.json")
    categories = data.get("categories", [])
    checks.require(len(categories) >= 15, f"awards must have >=15 weighted categories, got {len(categories)}")
    ids: set[str] = set()
    for category in categories:
        category_id = category.get("id")
        checks.require(bool(category_id) and category_id not in ids, f"duplicate/blank award id {category_id!r}")
        ids.add(category_id)
        checks.require(category.get("weight", 0) > 0, f"{category_id}: weight must be positive")
        checks.require(
            valid_analytics_metric(str(category.get("metric", ""))),
            f"{category_id}: unknown analytics metric {category.get('metric')!r}",
        )
        checks.require(localized_pair(category.get("title")), f"{category_id}: missing en/de title")
        checks.require(localized_pair(category.get("statLine")), f"{category_id}: missing en/de stat line")
    print(f"awards: {len(categories)} weighted categories, {data.get('categoriesPerDay')} drawn/day")


def validate_gates_milestones_buffs(config_dir: Path, checks: Checks) -> None:
    gates = read_json(config_dir / "recipegate.json").get("tiers", [])

    def unlock_day(entry: str) -> int | None:
        days = [
            int(tier.get("unlockDay", 1))
            for tier in gates
            if entry in tier.get("locks", {}).get("items", [])
        ]
        return max(days) if days else None

    checks.require(unlock_day("#eclipse:tier_diamond_gear") == 5, "diamond gear must unlock on day 5")
    checks.require(unlock_day("#eclipse:tier_netherite_gear") == 10, "netherite gear must unlock on day 10")

    milestones = read_json(config_dir / "milestones.json")
    checks.require([entry.get("level") for entry in milestones] == [1, 2, 3, 4, 5], "milestones must cover L1-L5")
    checks.require(
        all(len(entry.get("cost", [])) >= 2 for entry in milestones),
        "each milestone must use at least two item types",
    )

    buffs = read_json(config_dir / "buffs.json").get("buffs", [])
    checks.require(len(buffs) >= 9, f"buff defaults must contain at least 9 definitions, got {len(buffs)}")
    for buff in buffs:
        checks.require(localized_pair(buff.get("title")), f"{buff.get('id')}: missing en/de buff title")
        checks.require(int(buff.get("defaultMinutes", 0)) > 0, f"{buff.get('id')}: duration must be positive")
    print(f"gates/milestones/buffs: {len(gates)} tiers, {len(milestones)} milestones, {len(buffs)} buffs")


def validate_advancements(checks: Checks) -> None:
    lang = read_json(LANGDROP)
    en = lang.get("en_us", {})
    de = lang.get("de_de", {})
    files = sorted(ADVANCEMENT_DIR.glob("*.json"))
    checks.require(len(files) >= 14, f"expected >=14 event advancements, got {len(files)}")
    ids = {f"eclipse:event/{path.stem}" for path in files}
    impossible: list[str] = []
    for path in files:
        data = read_json(path)
        display = data.get("display", {})
        checks.require(display.get("announce_to_chat") is False, f"{path.name}: announce_to_chat must be false")
        checks.require(display.get("hidden") is True, f"{path.name}: hidden must be true")
        checks.require(display.get("frame") in {"task", "goal", "challenge"}, f"{path.name}: invalid frame")
        checks.require(bool(display.get("icon", {}).get("id")), f"{path.name}: icon.id missing")
        for field in ("title", "description"):
            key = display.get(field, {}).get("translate")
            checks.require(bool(key), f"{path.name}: {field} must use a translation key")
            if key:
                checks.require(key in en and key in de, f"{path.name}: translation {key} missing en_us/de_de")
        parent = data.get("parent")
        checks.require(parent is None or parent in ids, f"{path.name}: unknown parent {parent!r}")
        criteria = data.get("criteria", {})
        checks.require(bool(criteria), f"{path.name}: criteria missing")
        for criterion_id, criterion in criteria.items():
            checks.require(
                criterion.get("trigger") in ADVANCEMENT_TRIGGERS,
                f"{path.name}: {criterion_id} uses unexpected trigger {criterion.get('trigger')!r}",
            )
        for requirement_group in data.get("requirements", []):
            for criterion_id in requirement_group:
                checks.require(
                    criterion_id in criteria,
                    f"{path.name}: requirement references unknown criterion {criterion_id!r}",
                )
        if any(criterion.get("trigger") == "minecraft:impossible" for criterion in criteria.values()):
            impossible.append(path.stem)
    checks.require(set(en) == set(de), "WB-CONTENT langdrop locales must have identical key sets")
    print(f"advancements: {len(files)} JSONs, all hidden/chat-silent; code-grant seams={','.join(impossible)}")


def validate_source_shape(checks: Checks) -> None:
    """Fast fallback before runtime JSON exists; exact schema checks require --strict after boot."""
    goal_source = (ROOT / "src/main/java/dev/projecteclipse/eclipse/progression/goals/GoalConfig.java").read_text()
    days = {int(day) for day in re.findall(r"addDay\(days,\s*(\d+)", goal_source)}
    checks.require(days == set(range(1, 15)), f"Java goal defaults must contain days 1..14, got {sorted(days)}")
    for day in range(1, 15):
        prefix = f"{day:02d}"
        mains = len(re.findall(rf'main\("d{prefix}_', goal_source))
        sides = len(re.findall(rf'side\("d{prefix}_', goal_source))
        checks.require(mains == 3, f"Java day {day} defaults have {mains} mains")
        checks.require(3 <= sides <= 5, f"Java day {day} defaults have {sides} sides")
    personals = len(re.findall(r'pool\.add\(personal\("', goal_source))
    checks.require(personals >= 24, f"Java personal defaults must contain >=24 quests, got {personals}")

    offering_source = (ROOT / "src/main/java/dev/projecteclipse/eclipse/offering/OfferingConfig.java").read_text()
    authored_items = offering_source.split("Map<String, String> items", 1)[1].split(
        "Set<String> junk", 1
    )[0]
    item_ids = set(re.findall(r'"((?:minecraft|eclipse):[a-z0-9_]+)"', authored_items))
    checks.require(75 <= len(item_ids) <= 120, f"Java offering defaults have {len(item_ids)} explicit ids")

    awards_source = (ROOT / "src/main/java/dev/projecteclipse/eclipse/awards/AwardConfig.java").read_text()
    category_block = awards_source.split("List<Category> categories =", 1)[1].split(
        "Map<Integer, Set<String>> themes", 1
    )[0]
    categories = len(re.findall(r"\bcategory\(", category_block)) + len(
        re.findall(r"new Category\(", category_block)
    )
    checks.require(categories >= 15, f"Java award defaults have only {categories} categories")
    category_metrics = re.findall(
        r'(?:\bcategory|new Category)\("[^"]+",\s*"([^"]+)"',
        category_block,
    )
    checks.require(
        len(category_metrics) == categories,
        "could not statically extract every Java award metric",
    )
    for metric in category_metrics:
        checks.require(valid_analytics_metric(metric), f"Java award defaults use unknown metric {metric!r}")

    tree_source = (ROOT / "src/main/java/dev/projecteclipse/eclipse/skills/SkillTreeConfig.java").read_text()
    nodes = len(re.findall(r"nodes\.add\(node\(", tree_source))
    checks.require(24 <= nodes <= 28, f"Java skill tree defaults have {nodes} nodes")

    skill_source = (ROOT / "src/main/java/dev/projecteclipse/eclipse/skills/SkillConfig.java").read_text()
    mapped_advancements = set(re.findall(r'advancements\.addProperty\("eclipse:([^"]+)"', skill_source))
    advancement_ids = {path.stem for path in ADVANCEMENT_DIR.glob("*.json")}
    checks.require(
        advancement_ids.issubset(mapped_advancements),
        f"Java skill defaults miss advancement XP mappings: {sorted(advancement_ids - mapped_advancements)}",
    )

    buff_source = (ROOT / "src/main/java/dev/projecteclipse/eclipse/buffs/BuffConfig.java").read_text()
    buffs = len(re.findall(r"buffs\.add\(def\(", buff_source))
    checks.require(buffs >= 9, f"Java buff defaults have only {buffs} buffs")
    print(
        f"source defaults: {len(days)} days, {personals} personals, {len(item_ids)} offering ids, "
        f"{categories} awards, {nodes} skill nodes, {buffs} buffs"
    )


def detect_config_dir(explicit: Path | None) -> Path | None:
    if explicit is not None:
        return explicit.resolve()
    for candidate in (ROOT / "run/config/eclipse", ROOT / "config/eclipse"):
        if candidate.is_dir():
            return candidate
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config-dir", type=Path, help="Generated runtime config/eclipse directory")
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Fail if the runtime directory or any expected generated config is missing",
    )
    args = parser.parse_args()
    checks = Checks()

    validate_advancements(checks)
    config_dir = detect_config_dir(args.config_dir)
    if config_dir is None:
        if args.strict:
            checks.errors.append("runtime config directory missing; boot the server once before --strict")
        else:
            checks.warnings.append("runtime config missing; ran Java source-shape checks only")
            validate_source_shape(checks)
    else:
        missing = [name for name in RUNTIME_FILES if not (config_dir / name).is_file()]
        if missing:
            message = f"{config_dir}: missing generated files: {', '.join(missing)}"
            if args.strict:
                checks.errors.append(message)
            else:
                checks.warnings.append(message)
                validate_source_shape(checks)
        else:
            print(f"runtime config: {config_dir}")
            try:
                validate_goals(config_dir, checks)
                validate_skills(config_dir, checks)
                validate_offerings(config_dir, checks)
                validate_awards(config_dir, checks)
                validate_gates_milestones_buffs(config_dir, checks)
            except (KeyError, TypeError, ValueError, json.JSONDecodeError) as exc:
                checks.errors.append(f"runtime config schema error: {exc}")

    for warning in checks.warnings:
        print(f"WARN: {warning}", file=sys.stderr)
    for error in checks.errors:
        print(f"ERROR: {error}", file=sys.stderr)
    if checks.errors:
        print(f"FAILED: {len(checks.errors)} error(s), {len(checks.warnings)} warning(s)")
        return 1
    print(f"PASS: P4 balance invariants ({len(checks.warnings)} warning(s))")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
