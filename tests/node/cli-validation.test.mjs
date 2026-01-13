import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { pathToFileURL } from 'node:url';
import { join } from 'node:path';

const moduleUrl = pathToFileURL(join(process.cwd(), 'cli/dist/exports.js')).href;

function withTempHome(testFn) {
  const originalEnv = { ...process.env };
  const tempHome = mkdtempSync(join(tmpdir(), 'samara-node-test-'));
  process.env.HOME = tempHome;
  process.env.USERPROFILE = tempHome;
  process.env.XDG_CONFIG_HOME = join(tempHome, '.config');

  return Promise.resolve()
    .then(testFn)
    .finally(() => {
      for (const key of Object.keys(process.env)) {
        if (!(key in originalEnv)) {
          delete process.env[key];
        }
      }
      for (const [key, value] of Object.entries(originalEnv)) {
        process.env[key] = value;
      }
    });
}

async function importExportsModule() {
  const cacheBust = `?t=${Date.now()}-${Math.random()}`;
  return import(`${moduleUrl}${cacheBust}`);
}

test('validation helpers accept valid inputs', async () => {
  await withTempHome(async () => {
    const {
      isValidEmail,
      isValidICloudEmail,
      isValidPhone,
      isValidBlueskyHandle,
      isValidGitHubUsername,
      isValidTeamId,
    } = await importExportsModule();

    assert.equal(isValidEmail('test@example.com'), true);
    assert.equal(isValidICloudEmail('USER@ICLOUD.COM'), true);
    assert.equal(isValidPhone('+14155551234'), true);
    assert.equal(isValidBlueskyHandle('@tester.bsky.social'), true);
    assert.equal(isValidGitHubUsername('test-user'), true);
    assert.equal(isValidTeamId('A1B2C3D4E5'), true);
  });
});

test('validation helpers reject invalid inputs', async () => {
  await withTempHome(async () => {
    const {
      isValidEmail,
      isValidICloudEmail,
      isValidPhone,
      isValidBlueskyHandle,
      isValidGitHubUsername,
      isValidTeamId,
    } = await importExportsModule();

    assert.equal(isValidEmail('not-an-email'), false);
    assert.equal(isValidICloudEmail('user@example.com'), false);
    assert.equal(isValidPhone('4155551234'), false);
    assert.equal(isValidBlueskyHandle('tester.bsky.social'), false);
    assert.equal(isValidGitHubUsername('bad name'), false);
    assert.equal(isValidTeamId('A1B2C3'), false);
  });
});

test('formatPhoneHint returns helpful guidance', async () => {
  await withTempHome(async () => {
    const { formatPhoneHint } = await importExportsModule();

    assert.equal(formatPhoneHint('415'), 'Must start with + (e.g., +14155551234)');
    assert.equal(formatPhoneHint('+1415'), 'Enter full number including country code');
    assert.equal(formatPhoneHint('+14155551234'), '');
  });
});

test('validateEntity and validateCollaborator report success', async () => {
  await withTempHome(async () => {
    const { validateEntity, validateCollaborator } = await importExportsModule();

    const entity = {
      name: 'Test Claude',
      icloud: 'test@icloud.com',
      bluesky: '@test.bsky.social',
      github: 'test-claude',
    };
    const collaborator = {
      name: 'Tester',
      phone: '+14155551234',
      email: 'tester@example.com',
      bluesky: '@tester.example',
    };

    const entityResult = validateEntity(entity);
    const collaboratorResult = validateCollaborator(collaborator);

    assert.equal(entityResult.success, true);
    assert.equal(collaboratorResult.success, true);
  });
});

test('validateEntity and validateCollaborator report errors', async () => {
  await withTempHome(async () => {
    const { validateEntity, validateCollaborator } = await importExportsModule();

    const badEntity = {
      name: '',
      icloud: 'not-an-email',
    };
    const badCollaborator = {
      name: 'Tester',
      phone: '4155551234',
      email: 'tester@example.com',
    };

    const entityResult = validateEntity(badEntity);
    const collaboratorResult = validateCollaborator(badCollaborator);

    assert.equal(entityResult.success, false);
    assert.equal(typeof entityResult.error, 'string');
    assert.equal(collaboratorResult.success, false);
    assert.equal(typeof collaboratorResult.error, 'string');
  });
});
