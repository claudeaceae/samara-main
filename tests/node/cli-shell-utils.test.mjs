import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, chmodSync, rmSync, existsSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const shellUrl = pathToFileURL(join(process.cwd(), 'cli/src/utils/shell.ts')).href;
const prereqUrl = pathToFileURL(join(process.cwd(), 'cli/src/utils/prerequisites.ts')).href;

async function importShell() {
  return import(shellUrl);
}

async function importPrerequisites() {
  return import(prereqUrl);
}

function withEnv(env, fn) {
  const previous = {};
  for (const [key, value] of Object.entries(env)) {
    previous[key] = process.env[key];
    if (value === undefined) {
      delete process.env[key];
    } else {
      process.env[key] = value;
    }
  }

  try {
    return fn();
  } finally {
    for (const [key, value] of Object.entries(previous)) {
      if (value === undefined) {
        delete process.env[key];
      } else {
        process.env[key] = value;
      }
    }
  }
}

function makeStubCommand(dir, name, content) {
  const path = join(dir, name);
  writeFileSync(path, content, { encoding: 'utf8' });
  chmodSync(path, 0o755);
  return path;
}

async function withStubbedPath(stubs, fn) {
  const originalPath = process.env.PATH || '';
  const tempDir = mkdtempSync(join(tmpdir(), 'samara-cli-stubs-'));

  try {
    for (const [name, script] of Object.entries(stubs)) {
      makeStubCommand(tempDir, name, script);
    }
    process.env.PATH = `${tempDir}:${originalPath}`;
    return await fn(tempDir);
  } finally {
    process.env.PATH = originalPath;
    rmSync(tempDir, { recursive: true, force: true });
  }
}

test('shell helpers cover success and failure paths', async () => {
  const stubs = {
    okcmd: `#!/bin/sh\necho \"ok-out\"\necho \"ok-err\" 1>&2\nexit 0\n`,
    failcmd: `#!/bin/sh\necho \"fail-out\"\necho \"fail-err\" 1>&2\nexit 2\n`,
  };

  await withStubbedPath(stubs, async () => {
    const { commandExists, run } = await importShell();

    assert.equal(await commandExists('okcmd'), true);
    assert.equal(await commandExists('missingcmd'), false);

    const ok = await run('okcmd', [], { silent: true });
    assert.equal(ok.exitCode, 0);
    assert.equal(ok.stdout.trim(), 'ok-out');
    assert.equal(ok.stderr.trim(), 'ok-err');

    const failed = await run('failcmd', [], { silent: true });
    assert.equal(failed.exitCode, 2);
    assert.equal(failed.stdout.trim(), 'fail-out');
    assert.equal(failed.stderr.trim(), 'fail-err');
  });
});

test('runBirth handles success, failure, and missing script', async () => {
  const { runBirth } = await importShell();

  const repoDir = mkdtempSync(join(tmpdir(), 'samara-birth-'));
  const birthPath = join(repoDir, 'birth.sh');
  writeFileSync(birthPath, '#!/bin/sh\nexit "${STUB_BIRTH_EXIT:-0}"\n', { encoding: 'utf8' });

  const success = withEnv({ STUB_BIRTH_EXIT: '0' }, () => runBirth('config.json', repoDir));
  assert.equal(await success, true);

  const failure = withEnv({ STUB_BIRTH_EXIT: '1' }, () => runBirth('config.json', repoDir));
  assert.equal(await failure, false);

  await assert.rejects(() => runBirth('config.json', join(repoDir, 'missing')));

  rmSync(repoDir, { recursive: true, force: true });
});

test('launchctl helpers and open helpers behave as expected', async () => {
  const stubs = {
    launchctl: `#!/bin/sh\nif [ \"$1\" = \"list\" ]; then\n  if [ \"$STUB_LAUNCHCTL_HAS_LABEL\" = \"1\" ]; then\n    echo \"123 com.example.agent\"\n  fi\n  exit 0\nfi\nexit \"\${STUB_LAUNCHCTL_EXIT:-0}\"\n`,
    open: `#!/bin/sh\nexit \"\${STUB_OPEN_EXIT:-0}\"\n`,
  };

  await withStubbedPath(stubs, async () => {
    const {
      loadLaunchAgent,
      unloadLaunchAgent,
      isLaunchAgentLoaded,
      openUrl,
      openSystemPreferences,
    } = await importShell();

    const loadOk = withEnv({ STUB_LAUNCHCTL_EXIT: '0' }, () => loadLaunchAgent('/tmp/test.plist'));
    assert.equal(await loadOk, true);

    const unloadFail = withEnv({ STUB_LAUNCHCTL_EXIT: '1' }, () => unloadLaunchAgent('/tmp/test.plist'));
    assert.equal(await unloadFail, false);

    const loaded = withEnv({ STUB_LAUNCHCTL_HAS_LABEL: '1' }, () => isLaunchAgentLoaded('com.example.agent'));
    assert.equal(await loaded, true);

    const notLoaded = withEnv({ STUB_LAUNCHCTL_HAS_LABEL: '0' }, () => isLaunchAgentLoaded('com.example.agent'));
    assert.equal(await notLoaded, false);

    const openOk = withEnv({ STUB_OPEN_EXIT: '0' }, () => openUrl('https://example.com'));
    assert.equal(await openOk, true);

    const prefsOk = withEnv({ STUB_OPEN_EXIT: '0' }, () => openSystemPreferences('com.apple.preference.security'));
    assert.equal(await prefsOk, true);

    const openFail = withEnv({ STUB_OPEN_EXIT: '1' }, () => openUrl('https://example.com'));
    assert.equal(await openFail, false);
  });
});

test('download, unzip, process, brew, and xcode helpers return expected results', async () => {
  const stubs = {
    curl: `#!/bin/sh\nout=\"\"\nwhile [ \"$#\" -gt 0 ]; do\n  if [ \"$1\" = \"-o\" ]; then\n    shift\n    out=\"$1\"\n  fi\n  shift\ndone\nif [ -n \"$out\" ]; then\n  echo \"data\" > \"$out\"\nfi\nexit \"\${STUB_CURL_EXIT:-0}\"\n`,
    unzip: `#!/bin/sh\ndest=\"\"\nwhile [ \"$#\" -gt 0 ]; do\n  if [ \"$1\" = \"-d\" ]; then\n    shift\n    dest=\"$1\"\n  fi\n  shift\ndone\nif [ -n \"$dest\" ]; then\n  mkdir -p \"$dest\"\n  echo \"unzipped\" > \"$dest/ok.txt\"\nfi\nexit \"\${STUB_UNZIP_EXIT:-0}\"\n`,
    pgrep: `#!/bin/sh\nexit \"\${STUB_PGREP_EXIT:-1}\"\n`,
    brew: `#!/bin/sh\nif [ \"$1\" = \"--version\" ]; then\n  echo \"Homebrew 4.0.0\"\n  exit 0\nfi\nexit \"\${STUB_BREW_EXIT:-0}\"\n`,
    xcodebuild: `#!/bin/sh\nexit \"\${STUB_XCODEBUILD_EXIT:-0}\"\n`,
  };

  await withStubbedPath(stubs, async () => {
    const {
      downloadFile,
      unzip,
      isProcessRunning,
      brewInstall,
      xcodeBuildArchive,
      xcodeBuildExport,
    } = await importShell();

    const downloadPath = join(tmpdir(), `samara-download-${Date.now()}.txt`);
    const downloadOk = withEnv({ STUB_CURL_EXIT: '0' }, () =>
      downloadFile('https://example.com/file.txt', downloadPath)
    );
    assert.equal(await downloadOk, true);
    assert.equal(existsSync(downloadPath), true);
    rmSync(downloadPath, { force: true });

    const downloadFail = withEnv({ STUB_CURL_EXIT: '1' }, () =>
      downloadFile('https://example.com/file.txt', downloadPath)
    );
    assert.equal(await downloadFail, false);

    const unzipDir = join(tmpdir(), `samara-unzip-${Date.now()}`);
    const unzipOk = withEnv({ STUB_UNZIP_EXIT: '0' }, () => unzip('archive.zip', unzipDir));
    assert.equal(await unzipOk, true);
    assert.equal(existsSync(join(unzipDir, 'ok.txt')), true);
    rmSync(unzipDir, { recursive: true, force: true });

    const running = withEnv({ STUB_PGREP_EXIT: '0' }, () => isProcessRunning('samara'));
    assert.equal(await running, true);

    const notRunning = withEnv({ STUB_PGREP_EXIT: '1' }, () => isProcessRunning('samara'));
    assert.equal(await notRunning, false);

    const brewOk = withEnv({ STUB_BREW_EXIT: '0' }, () => brewInstall('jq'));
    assert.equal(await brewOk, true);

    const brewFail = withEnv({ STUB_BREW_EXIT: '1' }, () => brewInstall('jq'));
    assert.equal(await brewFail, false);

    const archiveOk = withEnv({ STUB_XCODEBUILD_EXIT: '0' }, () =>
      xcodeBuildArchive('Samara/Samara.xcodeproj', 'Samara', '/tmp/Samara.xcarchive')
    );
    assert.equal(await archiveOk, true);

    const exportFail = withEnv({ STUB_XCODEBUILD_EXIT: '1' }, () =>
      xcodeBuildExport('/tmp/Samara.xcarchive', '/tmp/SamaraExport', '/tmp/Export.plist')
    );
    assert.equal(await exportFail, false);
  });
});

test('prerequisite checks and installers behave predictably', async () => {
  const shellShimPath = join(process.cwd(), 'cli/src/utils/shell.js');
  const shimContents = "export { commandExists, run, brewInstall } from './shell.ts';\n";
  let createdShim = false;

  if (!existsSync(shellShimPath)) {
    writeFileSync(shellShimPath, shimContents, { encoding: 'utf8' });
    createdShim = true;
  }

  try {
    const stubs = {
      'xcode-select': `#!/bin/sh\nif [ \"$1\" = \"-p\" ]; then\n  echo \"/Library/Developer/CommandLineTools\"\n  exit 0\nfi\nif [ \"$1\" = \"--install\" ]; then\n  exit 0\nfi\nexit 0\n`,
      brew: `#!/bin/sh\nif [ \"$1\" = \"--version\" ]; then\n  echo \"Homebrew 4.0.0\"\n  exit 0\nfi\nexit \"\${STUB_BREW_EXIT:-0}\"\n`,
      jq: `#!/bin/sh\nif [ \"$1\" = \"--version\" ]; then\n  echo \"jq-1.7\"\n  exit 0\nfi\nexit 0\n`,
      claude: `#!/bin/sh\nif [ \"$1\" = \"--version\" ]; then\n  echo \"claude 0.1.0\"\n  exit 0\nfi\nexit 0\n`,
    };

    await withStubbedPath(stubs, async () => {
    const {
      isMacOS,
      checkXcodeTools,
      checkHomebrew,
      checkJq,
      checkClaudeCli,
      checkAllPrerequisites,
      displayPrerequisites,
      installMissingPrerequisites,
      getClaudeCliInstructions,
    } = await importPrerequisites();

    assert.equal(typeof isMacOS(), 'boolean');

    const xcode = await checkXcodeTools();
    assert.equal(xcode.installed, true);

    const brew = await checkHomebrew();
    assert.equal(brew.installed, true);
    assert.equal(brew.version, 'Homebrew 4.0.0');

    const jq = await checkJq();
    assert.equal(jq.installed, true);
    assert.equal(jq.version, 'jq-1.7');

    const claude = await checkClaudeCli();
    assert.equal(claude.installed, true);
    assert.equal(claude.installable, false);

    const all = await checkAllPrerequisites();
    assert.equal(all.length, 4);
    displayPrerequisites(all);

    const result = await installMissingPrerequisites([
      { name: 'Xcode Command Line Tools', installed: false, required: true, installable: true },
      { name: 'Homebrew', installed: true, required: true, installable: true },
      { name: 'jq', installed: false, required: true, installable: true },
      { name: 'Claude Code CLI', installed: false, required: true, installable: false },
    ]);

    assert.equal(result.needsRestart, true);
    assert.deepEqual(result.missing, ['Claude Code CLI']);
    assert.equal(result.success, false);

    const instructions = getClaudeCliInstructions();
    assert.ok(instructions.includes('npm install -g @anthropic-ai/claude-code'));
    });
  } finally {
    if (createdShim) {
      rmSync(shellShimPath, { force: true });
    }
  }
});
