/**
 * Server-side timeline + announcement layer (worker 8, {@code docs/ideas/03_ui_ux.md} §E).
 * {@link dev.projecteclipse.eclipse.timeline.TimelineService} builds the anonymized
 * {@link dev.projecteclipse.eclipse.timeline.TimelineEntry} list (future entries carry no
 * title/icon) and syncs it at login + day/altar changes;
 * {@link dev.projecteclipse.eclipse.timeline.AnnouncementService} fires
 * {@code S2CAnnouncePayload}s on day advances, unlock-key additions, altar milestone
 * level-ups and finished stage-growth sweeps.
 */
package dev.projecteclipse.eclipse.timeline;
