/**
 * Hand-rolled 5-field cron parser (minute hour day-of-month month day-of-week)
 * with vixie-cron semantics: when both dom and dow are restricted, a time
 * matches if EITHER matches. Supports *, lists, ranges, steps and names.
 */

export interface CronSpec {
  minutes: Set<number>
  hours: Set<number>
  dom: Set<number>
  months: Set<number>
  dow: Set<number>
  domStar: boolean
  dowStar: boolean
  source: string
}

const MONTH_NAMES: Record<string, number> = {
  jan: 1, feb: 2, mar: 3, apr: 4, may: 5, jun: 6, jul: 7, aug: 8, sep: 9, oct: 10, nov: 11, dec: 12,
}
const DOW_NAMES: Record<string, number> = { sun: 0, mon: 1, tue: 2, wed: 3, thu: 4, fri: 5, sat: 6 }

const ALIASES: Record<string, string> = {
  '@hourly': '0 * * * *',
  '@daily': '0 0 * * *',
  '@midnight': '0 0 * * *',
  '@weekly': '0 0 * * 0',
  '@monthly': '0 0 1 * *',
  '@yearly': '0 0 1 1 *',
  '@annually': '0 0 1 1 *',
}

function parseField(field: string, min: number, max: number, names?: Record<string, number>): { set: Set<number>; star: boolean } {
  const set = new Set<number>()
  let star = false
  const resolve = (token: string): number => {
    const lower = token.toLowerCase()
    if (names && lower in names) return names[lower]
    const n = parseInt(token, 10)
    if (!Number.isFinite(n)) throw new Error(`invalid cron token "${token}"`)
    return n
  }
  for (const part of field.split(',')) {
    const stepMatch = part.match(/^(.+?)\/(\d+)$/)
    const base = stepMatch ? stepMatch[1] : part
    const step = stepMatch ? parseInt(stepMatch[2], 10) : 1
    if (step < 1) throw new Error(`invalid step in "${part}"`)
    let from: number
    let to: number
    if (base === '*' || base === '?') {
      from = min
      to = max
      if (!stepMatch) star = true
    } else if (base.includes('-')) {
      const [a, b] = base.split('-')
      from = resolve(a)
      to = resolve(b)
      if (from > to) throw new Error(`inverted range "${part}"`)
    } else {
      from = resolve(base)
      to = stepMatch ? max : from
    }
    if (from < min || to > max) {
      // dow allows 7 = sunday
      if (!(max === 6 && to === 7)) throw new Error(`value out of range in "${part}" (${min}-${max})`)
    }
    for (let v = from; v <= to; v += step) set.add(v === 7 && max === 6 ? 0 : v)
  }
  if (set.size === 0) throw new Error(`empty cron field "${field}"`)
  return { set, star }
}

export function parseCron(expr: string): CronSpec {
  const trimmed = expr.trim().toLowerCase()
  const normalized = ALIASES[trimmed] ?? trimmed
  const fields = normalized.split(/\s+/)
  if (fields.length !== 5) throw new Error(`cron expression must have 5 fields, got ${fields.length}`)
  const [minF, hourF, domF, monF, dowF] = fields
  const minutes = parseField(minF, 0, 59)
  const hours = parseField(hourF, 0, 23)
  const dom = parseField(domF, 1, 31)
  const months = parseField(monF, 1, 12, MONTH_NAMES)
  const dow = parseField(dowF, 0, 6, DOW_NAMES)
  return {
    minutes: minutes.set,
    hours: hours.set,
    dom: dom.set,
    months: months.set,
    dow: dow.set,
    domStar: dom.star,
    dowStar: dow.star,
    source: expr.trim(),
  }
}

export function cronMatches(spec: CronSpec, date: Date): boolean {
  if (!spec.minutes.has(date.getMinutes())) return false
  if (!spec.hours.has(date.getHours())) return false
  if (!spec.months.has(date.getMonth() + 1)) return false
  const domMatch = spec.dom.has(date.getDate())
  const dowMatch = spec.dow.has(date.getDay())
  if (spec.domStar && spec.dowStar) return true
  if (spec.domStar) return dowMatch
  if (spec.dowStar) return domMatch
  return domMatch || dowMatch // vixie: either matches when both restricted
}

/** Next matching time strictly after `from`. Returns null if none within ~2 years. */
export function nextRun(spec: CronSpec, from: Date = new Date()): Date | null {
  const cursor = new Date(from)
  cursor.setSeconds(0, 0)
  cursor.setMinutes(cursor.getMinutes() + 1)
  const limit = from.getTime() + 2 * 366 * 24 * 60 * 60 * 1000
  while (cursor.getTime() <= limit) {
    if (!spec.months.has(cursor.getMonth() + 1)) {
      cursor.setMonth(cursor.getMonth() + 1, 1)
      cursor.setHours(0, 0, 0, 0)
      continue
    }
    const domMatch = spec.dom.has(cursor.getDate())
    const dowMatch = spec.dow.has(cursor.getDay())
    const dayOk =
      spec.domStar && spec.dowStar ? true : spec.domStar ? dowMatch : spec.dowStar ? domMatch : domMatch || dowMatch
    if (!dayOk) {
      cursor.setDate(cursor.getDate() + 1)
      cursor.setHours(0, 0, 0, 0)
      continue
    }
    if (!spec.hours.has(cursor.getHours())) {
      cursor.setHours(cursor.getHours() + 1, 0, 0, 0)
      continue
    }
    if (!spec.minutes.has(cursor.getMinutes())) {
      cursor.setMinutes(cursor.getMinutes() + 1, 0, 0)
      continue
    }
    return cursor
  }
  return null
}

/** Human-readable-ish description used by the UI as a fallback. */
export function describeCron(expr: string): string {
  try {
    parseCron(expr)
    return expr
  } catch (err) {
    return `invalid: ${(err as Error).message}`
  }
}
