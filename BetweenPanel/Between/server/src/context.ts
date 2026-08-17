import type { Store } from './lib/jsonstore.ts'
import type { PanelConfig } from './config.ts'
import type { AuthService } from './auth/service.ts'
import type { ServerManager } from './servers/manager.ts'
import type { BackupService } from './services/backups.ts'
import type { ScheduleService } from './services/schedules.ts'
import type { MetricsService } from './services/metrics.ts'
import type { AuditService } from './services/audit.ts'
import type { Notifier } from './services/notify.ts'
import type { BlueprintRegistry } from './blueprints/registry.ts'
import type { SteamCmdManager } from './steam/steamcmd.ts'
import type { SteamLoginService } from './steam/login.ts'
import type { WsHub } from './ws/hub.ts'
import type { Collection } from './lib/jsonstore.ts'
import type { PanelSettings } from './types.ts'
import type { DockerService } from './services/docker.ts'
import type { FileAccessService } from './services/fileaccess.ts'
import type { NodeService } from './nodes/service.ts'
import type { ServerGateway } from './nodes/gateway.ts'

export interface AppContext {
  config: PanelConfig
  store: Store
  auth: AuthService
  manager: ServerManager
  backups: BackupService
  schedules: ScheduleService
  metrics: MetricsService
  audit: AuditService
  notifier: Notifier
  registry: BlueprintRegistry
  steam: SteamCmdManager
  /** Panel Steam account login/session management (password never persisted). */
  steamLogin: SteamLoginService
  docker: DockerService
  hub: WsHub
  settings: Collection<PanelSettings>
  /** SFTP file-access config + provider seam (placeholder provider in v1). */
  fileAccess: FileAccessService
  /** Remote node registry + health/mirror poller (inert in node-agent mode). */
  nodes: NodeService
  /** Local-vs-remote dispatch facade used by the server-scoped API routes. */
  gateway: ServerGateway
}

export function currentSettings(ctx: AppContext): PanelSettings {
  let settings = ctx.settings.all()[0]
  if (!settings) {
    settings = ctx.settings.insert({
      panelName: 'Between',
      defaultBackupRetention: 10,
      portRangeStart: 25565,
      portRangeEnd: 29000,
      discordWebhookUrl: null,
      discordEvents: { crash: true, power: false, backup: false },
      webhookUrl: null,
      webhookEvents: { crash: true, power: false, backup: false },
      defaultTheme: 'between-dark',
    })
  }
  return settings
}
