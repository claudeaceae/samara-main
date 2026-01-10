import * as p from '@clack/prompts';
import color from 'picocolors';
import { existsSync, writeFileSync, mkdirSync } from 'fs';
import { join } from 'path';
import { tmpdir, homedir } from 'os';
import type { WizardContext } from '../types.js';
import {
  downloadFile,
  unzip,
  run,
  xcodeBuildArchive,
  xcodeBuildExport,
} from '../utils/shell.js';
import { isValidTeamId } from '../utils/validation.js';

const GITHUB_RELEASES_URL = 'https://api.github.com/repos/claudeaceae/samara-main/releases/latest';
const APP_PATH = '/Applications/Samara.app';

export async function app(ctx: WizardContext): Promise<void> {
  p.log.step('Samara.app');

  // Check if app already exists
  if (existsSync(APP_PATH)) {
    const rebuild = await p.confirm({
      message: 'Samara.app already exists. Skip this step?',
      initialValue: true,
    });

    if (p.isCancel(rebuild)) {
      p.cancel('Setup cancelled.');
      process.exit(0);
    }

    if (rebuild) {
      p.log.success('Using existing Samara.app');
      return;
    }
  }

  // Ask about Developer Account
  const hasDeveloperAccount = await p.confirm({
    message: 'Do you have an Apple Developer Account ($99/year)?',
    initialValue: false,
  });

  if (p.isCancel(hasDeveloperAccount)) {
    p.cancel('Setup cancelled.');
    process.exit(0);
  }

  ctx.hasDeveloperAccount = hasDeveloperAccount;

  if (hasDeveloperAccount) {
    // Ask if they want to build from source
    const buildFromSource = await p.select({
      message: 'How would you like to get Samara.app?',
      options: [
        {
          value: 'download',
          label: 'Download pre-built (faster)',
          hint: 'Uses existing Team ID, you can rebuild later',
        },
        {
          value: 'build',
          label: 'Build from source',
          hint: 'Uses your Team ID, full customization',
        },
      ],
    });

    if (p.isCancel(buildFromSource)) {
      p.cancel('Setup cancelled.');
      process.exit(0);
    }

    ctx.buildFromSource = buildFromSource === 'build';

    if (ctx.buildFromSource) {
      await buildFromSourceFlow(ctx);
      return;
    }
  } else {
    p.note(
      `Without a Developer Account, Full Disk Access won't persist if you rebuild the app later.

This is fine for getting started - you can always get a Developer Account later.`,
      'Note'
    );
  }

  // Download pre-built app
  await downloadPrebuiltFlow(ctx);
}

async function downloadPrebuiltFlow(ctx: WizardContext): Promise<void> {
  const spinner = p.spinner();
  spinner.start('Fetching latest release...');

  try {
    // Get latest release info
    const tempDir = join(tmpdir(), 'create-samara');
    mkdirSync(tempDir, { recursive: true });
    const releaseInfoPath = join(tempDir, 'release.json');

    await downloadFile(GITHUB_RELEASES_URL, releaseInfoPath);

    // For now, we'll use a direct download URL
    // In production, parse the release JSON to get the asset URL
    const downloadUrl = 'https://github.com/claudeaceae/samara-main/releases/latest/download/Samara.app.zip';
    const zipPath = join(tempDir, 'Samara.app.zip');

    spinner.message('Downloading Samara.app...');
    const downloaded = await downloadFile(downloadUrl, zipPath);

    if (!downloaded || !existsSync(zipPath)) {
      spinner.stop('Download failed');
      p.log.warn('Could not download pre-built app. Falling back to Xcode instructions.');
      await manualXcodeFlow(ctx);
      return;
    }

    spinner.message('Installing Samara.app...');
    const unzipped = await unzip(zipPath, '/Applications');

    if (!unzipped || !existsSync(APP_PATH)) {
      spinner.stop('Installation failed');
      p.log.warn('Could not install app. Falling back to Xcode instructions.');
      await manualXcodeFlow(ctx);
      return;
    }

    spinner.stop('Samara.app installed');
    p.log.success(`Installed to ${color.cyan(APP_PATH)}`);
  } catch (error) {
    spinner.stop('Error');
    p.log.warn(`Download failed: ${error instanceof Error ? error.message : String(error)}`);
    p.log.message(color.dim('Falling back to Xcode instructions...'));
    await manualXcodeFlow(ctx);
  }
}

async function buildFromSourceFlow(ctx: WizardContext): Promise<void> {
  // Get Team ID
  const teamId = await p.text({
    message: 'Enter your Apple Team ID',
    placeholder: 'XXXXXXXXXX',
    validate: (value) => {
      if (!value || value.length === 0) return 'Team ID is required';
      if (!isValidTeamId(value)) return 'Team ID must be 10 alphanumeric characters';
      return undefined;
    },
  });

  if (p.isCancel(teamId)) {
    p.cancel('Setup cancelled.');
    process.exit(0);
  }

  ctx.teamId = teamId;

  // Generate ExportOptions.plist
  const exportOptionsPlist = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>${teamId}</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>`;

  const tempDir = join(tmpdir(), 'create-samara');
  mkdirSync(tempDir, { recursive: true });
  const exportOptionsPath = join(tempDir, 'ExportOptions.plist');
  writeFileSync(exportOptionsPath, exportOptionsPlist);

  const spinner = p.spinner();
  spinner.start('Building Samara.app (this may take a few minutes)...');

  try {
    const projectPath = join(ctx.repoPath, 'Samara', 'Samara.xcodeproj');
    const archivePath = join(tempDir, 'Samara.xcarchive');
    const exportPath = join(tempDir, 'SamaraExport');

    // Archive
    spinner.message('Archiving...');
    const archiveSuccess = await xcodeBuildArchive(projectPath, 'Samara', archivePath);

    if (!archiveSuccess) {
      spinner.stop('Archive failed');
      p.log.warn('xcodebuild archive failed. Falling back to manual instructions.');
      await manualXcodeFlow(ctx);
      return;
    }

    // Export
    spinner.message('Exporting...');
    const exportSuccess = await xcodeBuildExport(archivePath, exportPath, exportOptionsPath);

    if (!exportSuccess) {
      spinner.stop('Export failed');
      p.log.warn('xcodebuild export failed. Falling back to manual instructions.');
      await manualXcodeFlow(ctx);
      return;
    }

    // Copy to Applications
    spinner.message('Installing...');
    const exportedApp = join(exportPath, 'Samara.app');

    if (!existsSync(exportedApp)) {
      spinner.stop('App not found after export');
      await manualXcodeFlow(ctx);
      return;
    }

    // Remove existing app if present
    if (existsSync(APP_PATH)) {
      await run('rm', ['-rf', APP_PATH], { silent: true });
    }

    await run('cp', ['-R', exportedApp, APP_PATH], { silent: true });

    if (!existsSync(APP_PATH)) {
      spinner.stop('Installation failed');
      await manualXcodeFlow(ctx);
      return;
    }

    spinner.stop('Samara.app built and installed');
    p.log.success(`Built with Team ID: ${color.cyan(teamId)}`);
    p.log.success(`Installed to ${color.cyan(APP_PATH)}`);
  } catch (error) {
    spinner.stop('Build error');
    p.log.error(`Error: ${error instanceof Error ? error.message : String(error)}`);
    p.log.message(color.dim('Falling back to manual instructions...'));
    await manualXcodeFlow(ctx);
  }
}

async function manualXcodeFlow(ctx: WizardContext): Promise<void> {
  p.note(
    `${color.bold('Manual Xcode Build Required')}

1. Opening Xcode project...
2. In Xcode:
   - Select your Team in Signing & Capabilities
   - Product > Archive
   - Distribute App > Developer ID
   - Export to a location
   - Move Samara.app to /Applications/

${color.dim('Press Enter when done.')}`,
    'Xcode Instructions'
  );

  // Open Xcode project
  const projectPath = join(ctx.repoPath, 'Samara', 'Samara.xcodeproj');
  await run('open', [projectPath], { silent: true });

  await p.text({
    message: 'Press Enter when Samara.app is in /Applications/',
    placeholder: '',
    validate: () => {
      if (!existsSync(APP_PATH)) {
        return 'Samara.app not found in /Applications/. Please complete the Xcode build first.';
      }
      return undefined;
    },
  });

  p.log.success('Samara.app found');
}
