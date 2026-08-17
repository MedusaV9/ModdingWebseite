/**
 * Tiny placeholder renderer for schedule task commands and backup notes:
 * `{name}` is substituted from `vars`, `{{` escapes a literal `{`, unknown
 * placeholders stay verbatim (never a crash). Deliberately NOT the `{{VAR}}`
 * engine from util.ts — that one serves blueprint variables; this one serves
 * runtime schedule context and must be user-typo-tolerant.
 *
 * Safety properties (unit-tested):
 * - Single pass: substituted values are never re-scanned, so a player named
 *   "{state}" cannot expand further (no recursive template injection).
 * - Lookups use Object.hasOwn, so key names like "__proto__"/"constructor"
 *   can never resolve to inherited properties.
 * - The replacement callback inserts values literally — `$&`/`$1` in a value
 *   are not regex replacement patterns.
 * - Output goes to the game console via stdin/RCON as one opaque string; no
 *   shell is involved anywhere downstream.
 */
export function renderTemplate(template: string, vars: Record<string, string>): string {
  // Split on the escape first: `{{` segments are re-joined as a literal `{`
  // AFTER substitution, so an escaped brace can never start a placeholder.
  return template
    .split('{{')
    .map((segment) =>
      segment.replace(/\{([A-Za-z0-9_]+)\}/g, (match, key: string) => (Object.hasOwn(vars, key) ? vars[key] : match)),
    )
    .join('{')
}
