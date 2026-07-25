# V7-ITEMSB wiring notes (PLAN-ITEMS package B — sigils/cores)

Everything self-registers: the three new GeckoLib item renderers hang off
`client/item/ItemsBClientExtensions` (`@EventBusSubscriber`, `RegisterClientExtensionsEvent`)
and `EclipseItems.register` is already a core `EclipseMod` line — **zero hub edits needed
for B's own items**. Langdrop: `docs/plans_v3/langdrop/V7-ITEMSB.json` (16 `.lore` keys ×
en/de — includes the lore lines for the A/C-package items per PLAN-ITEMS §3 B6;
`item.eclipse.storm_heart.lore` already exists in `en_us.json`/`de_de.json` and is NOT
in the drop).

## Integrator asks (frozen W4-WIZARD file — PLAN-ITEMS §5 seam)

`entity/wizard/WizardEntities.java` (owned by no ITEMS package) registers
`wizard_catalyst`; the §2.3 table wants its lore + glint-off there. Two one-liners:

1. Add to the catalyst's `Item.Properties` chain:
   `.component(DataComponents.LORE, new ItemLore(List.of(Component.translatable("item.eclipse.wizard_catalyst.lore"))))`
2. Remove its `.component(DataComponents.ENCHANTMENT_GLINT_OVERRIDE, Boolean.TRUE)` line
   (glint discipline: glint = ritual fuel only; the catalyst is a recipe gate item).
