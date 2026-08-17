import type { I18nKey } from '../i18n/en.ts'

/**
 * Verb→tint mapping for audit-action badges — the single source for every
 * audit surface (Dashboard, AuditLog, ActivityTab). Order matters: the warn
 * set is tested BEFORE the success set because "restart" contains "start"
 * and "disable" contains "enable" (no success verb contains a warn verb,
 * so the reverse cannot misfire).
 */
export function auditActionTint(action: string): string {
  if (/(delete|remove|revoke|suspend|prune)/.test(action)) return 'border-danger/30 bg-danger/10 text-danger'
  if (/(stop|kill|restart|disable)/.test(action)) return 'border-warn/30 bg-warn/10 text-warn'
  if (/(create|install|enable|restore|start|add)/.test(action)) return 'border-success/30 bg-success/10 text-success'
  if (/(login|logout|auth|totp|password|session)/.test(action)) return 'border-accent/30 bg-accent/10 text-accent'
  return ''
}

/** The most common server-side audit actions, mapped to humanized i18n labels. */
const ACTION_LABEL_KEYS: Record<string, I18nKey> = {
  'server.power.start': 'audit.server.power.start',
  'server.power.stop': 'audit.server.power.stop',
  'server.power.restart': 'audit.server.power.restart',
  'server.power.kill': 'audit.server.power.kill',
  'server.created': 'audit.server.created',
  'server.updated': 'audit.server.updated',
  'server.deleted': 'audit.server.deleted',
  'server.cloned': 'audit.server.cloned',
  'server.crashed': 'audit.server.crashed',
  'server.reinstall': 'audit.server.reinstall',
  'backup.created': 'audit.backup.created',
  'backup.restored': 'audit.backup.restored',
  'backup.deleted': 'audit.backup.deleted',
  'backup.pruned': 'audit.backup.pruned',
  'auth.login': 'audit.auth.login',
  'auth.logout': 'audit.auth.logout',
  'auth.login_failed': 'audit.auth.login_failed',
  'settings.updated': 'audit.settings.updated',
  'schedule.created': 'audit.schedule.created',
  'schedule.deleted': 'audit.schedule.deleted',
  'files.upload': 'audit.files.upload',
  'files.write': 'audit.files.write',
  'files.delete': 'audit.files.delete',
  'files.rename': 'audit.files.rename',
  'files.copy': 'audit.files.copy',
  'files.move': 'audit.files.move',
  'files.zip': 'audit.files.zip',
  'files.extract': 'audit.files.extract',
  'steam.login': 'audit.steam.login',
  'steam.login_failed': 'audit.steam.login_failed',
  'steam.logout': 'audit.steam.logout',
}

/**
 * Humanized label for an audit action; unmapped actions fall back to the raw
 * key (callers should always put the raw key in `title`).
 */
export function auditActionLabel(action: string, t: (key: I18nKey) => string): string {
  const key = ACTION_LABEL_KEYS[action]
  return key ? t(key) : action
}
