import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

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

async function importContextModule() {
  const cacheBust = `?t=${Date.now()}-${Math.random()}`;
  return import(`${moduleUrl}${cacheBust}`);
}

test('createContext respects SAMARA_MIND_PATH override', async () => {
  await withTempHome(async () => {
    const override = join(process.env.HOME, 'custom-mind');
    process.env.SAMARA_MIND_PATH = override;
    delete process.env.MIND_PATH;

    const { createContext } = await importContextModule();
    const ctx = createContext();

    assert.equal(ctx.mindPath, resolve(override));
  });
});

test('createContext respects MIND_PATH override with tilde expansion', async () => {
  await withTempHome(async () => {
    delete process.env.SAMARA_MIND_PATH;
    process.env.MIND_PATH = '~/alt-mind';

    const { createContext } = await importContextModule();
    const ctx = createContext();

    assert.equal(ctx.mindPath, resolve(join(process.env.HOME, 'alt-mind')));
  });
});

test('createContext defaults to HOME/.claude-mind when no overrides are set', async () => {
  await withTempHome(async () => {
    delete process.env.SAMARA_MIND_PATH;
    delete process.env.MIND_PATH;

    const { createContext } = await importContextModule();
    const ctx = createContext();

    assert.equal(ctx.mindPath, resolve(join(process.env.HOME, '.claude-mind')));
  });
});

test('restoreFromState uses the override paths', async () => {
  await withTempHome(async () => {
    const override = join(process.env.HOME, 'override-mind');
    process.env.SAMARA_MIND_PATH = override;

    const { restoreFromState } = await importContextModule();
    const restored = restoreFromState({
      config: {},
      completedSteps: [],
      currentStep: 'welcome',
      hasDeveloperAccount: false,
      buildFromSource: false,
      teamId: undefined,
      setupBluesky: false,
      setupGithub: false,
      timestamp: Date.now(),
    });

    assert.equal(restored.mindPath, resolve(override));
  });
});

test('saveState persists progress and loadSavedState restores it', async () => {
  await withTempHome(async () => {
    const {
      createContext,
      saveState,
      loadSavedState,
      restoreFromState,
      shouldSkipStep,
      clearState,
    } = await importContextModule();

    const ctx = createContext();
    ctx.hasDeveloperAccount = true;
    ctx.buildFromSource = true;
    ctx.setupBluesky = true;
    ctx.setupGithub = true;
    ctx.teamId = 'A1B2C3D4E5';
    ctx.config = { entity: { name: 'Test' } };

    saveState(ctx, 'identity');

    const saved = loadSavedState();
    assert.ok(saved);
    assert.equal(saved.currentStep, 'identity');
    assert.equal(saved.hasDeveloperAccount, true);
    assert.equal(saved.buildFromSource, true);
    assert.equal(saved.setupBluesky, true);
    assert.equal(saved.setupGithub, true);
    assert.equal(saved.teamId, 'A1B2C3D4E5');
    assert.deepEqual(saved.completedSteps, ['identity']);

    const restored = restoreFromState(saved);
    assert.equal(restored.completedSteps.has('identity'), true);
    assert.equal(shouldSkipStep(restored, 'identity'), true);

    clearState();
  });
});

test('clearState removes saved wizard state', async () => {
  await withTempHome(async () => {
    const { createContext, saveState, loadSavedState, clearState } = await importContextModule();

    const ctx = createContext();
    saveState(ctx, 'welcome');

    assert.ok(loadSavedState());

    clearState();
    assert.equal(loadSavedState(), null);
  });
});

test('loadSavedState expires stale state', async () => {
  await withTempHome(async () => {
    const { createContext, saveState, loadSavedState } = await importContextModule();
    const originalNow = Date.now;

    try {
      Date.now = () => 0;
      const ctx = createContext();
      saveState(ctx, 'welcome');

      Date.now = () => 25 * 60 * 60 * 1000;
      assert.equal(loadSavedState(), null);
    } finally {
      Date.now = originalNow;
    }
  });
});

test('getResumeStep returns the first incomplete step', async () => {
  const { getResumeStep } = await importContextModule();

  const resume = getResumeStep({
    config: {},
    completedSteps: ['welcome', 'identity', 'collaborator'],
    currentStep: 'collaborator',
    hasDeveloperAccount: false,
    buildFromSource: false,
    teamId: undefined,
    setupBluesky: false,
    setupGithub: false,
    timestamp: Date.now(),
  });

  assert.equal(resume, 'integrations');
});
