import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const read = (relative) => readFile(new URL(relative, import.meta.url), 'utf8');

test('current release metadata stays in lockstep and bilingual', async () => {
  const [pkg, project, patchnotes, manualDe, manualEn] = await Promise.all([
    read('../package.json'),
    read('../../ios/project.yml'),
    read('../../../PATCHNOTES.md'),
    read('../../../docs/HANDBUCH.de.md'),
    read('../../../docs/MANUAL.en.md'),
  ]);
  assert.equal(JSON.parse(pkg).version, '16.0.0');
  assert.match(project, /MARKETING_VERSION: "16\.0\.0"/);
  assert.match(project, /CURRENT_PROJECT_VERSION: "54"/);
  assert.match(patchnotes, /^# SoooDreamy Patchnotes[\s\S]*?## 16\.0\.0 /);
  assert.match(patchnotes, /### Deutsch[\s\S]*### English/);
  assert.match(manualDe, /Version des Handbuchs: 16\.0\.0/);
  assert.match(manualEn, /Manual version: 16\.0\.0/);
  for (const document of [patchnotes, manualDe, manualEn]) {
    assert.match(document, /made by Sonic0810/);
  }
});

test('pairing invitation and Settings section no longer bypass localization', async () => {
  const settings = await read('../../ios/SoooDreamy/Stationen/Amt/SettingsView.swift');
  const strings = await read('../../ios/SoooDreamy/Core/CoreStrings.swift');
  assert.ok(!settings.includes('SectionHeader(title: "App")'));
  assert.ok(!settings.includes('"Komm zu mir auf SoooDreamy'));
  assert.ok(!settings.includes('"Join me on SoooDreamy'));
  assert.match(settings, /L10n\.t\("pairing\.shareInvite"/);
  assert.match(strings, /"pairing\.shareInvite": LText/);
  assert.match(strings, /"settings\.appSection": LText/);
});
