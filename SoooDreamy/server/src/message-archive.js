import { id, nowIso } from './util.js';

export const MESSAGE_ARCHIVE_CHUNK = 500;

export function messageArchivesOf(couple) {
  return Array.isArray(couple.messageArchives) ? couple.messageArchives : [];
}

export function allMessagesOf(couple) {
  return [
    ...messageArchivesOf(couple).flatMap((segment) =>
      Array.isArray(segment.messages) ? segment.messages : []),
    ...(couple.messages ?? []),
  ];
}

/**
 * Keep a bounded mutable hot set while retaining every older message in
 * append-only archive chunks. No mutation route searches these chunks.
 */
export function archiveMessageOverflow(couple, hotLimit) {
  const archives = couple.messageArchives ??= [];
  while (couple.messages.length > hotLimit) {
    const archived = couple.messages.splice(
      0,
      Math.min(MESSAGE_ARCHIVE_CHUNK, couple.messages.length - 1),
    );
    archives.push({
      format: 'message-archive-v1',
      id: id('message_archive'),
      firstMessageId: archived[0].id,
      lastMessageId: archived.at(-1).id,
      createdAt: nowIso(),
      messages: archived,
    });
  }
}
