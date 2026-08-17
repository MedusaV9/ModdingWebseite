import { brief } from './util.mjs';

/**
 * Central findings collector. Every violated invariant lands here with a
 * machine code, severity, human message and a repro hint — the arena run
 * never aborts on a violation (we want ALL findings of a run, not the first).
 */
export class Violations {
  constructor() {
    this.items = [];
  }

  /**
   * @param {string} code machine code, e.g. 'cross_couple_frame'
   * @param {'critical'|'high'|'medium'|'low'|'info'} severity
   * @param {string} message human description
   * @param {object} [context] structured evidence (frame, response, ids…)
   */
  add(code, severity, message, context = {}) {
    const item = { code, severity, message, context, at: new Date().toISOString() };
    this.items.push(item);
    // Live echo so a watcher sees findings as they happen.
    console.error(`  ✗ [${severity}] ${code}: ${message} ${brief(context, 220)}`);
  }

  get count() {
    return this.items.length;
  }

  summary() {
    const byCode = {};
    for (const item of this.items) {
      byCode[item.code] = (byCode[item.code] ?? 0) + 1;
    }
    return { total: this.items.length, byCode };
  }
}
