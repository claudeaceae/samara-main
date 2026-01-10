import * as p from '@clack/prompts';
import color from 'picocolors';
import { existsSync, readdirSync, copyFileSync } from 'fs';
import { join, basename } from 'path';
import { homedir } from 'os';
import type { WizardContext } from '../types.js';
import { loadLaunchAgent, isLaunchAgentLoaded } from '../utils/shell.js';

const LAUNCH_AGENTS_DIR = join(homedir(), 'Library/LaunchAgents');

const REQUIRED_PLISTS = [
  'com.claude.wake-morning.plist',
  'com.claude.wake-afternoon.plist',
  'com.claude.wake-evening.plist',
  'com.claude.dream.plist',
];

export async function launchd(ctx: WizardContext): Promise<void> {
  p.log.step('Wake/Dream Cycles');
  p.log.message(color.dim('Installing scheduled tasks for autonomous operation.'));

  const spinner = p.spinner();
  spinner.start('Installing launchd services...');

  const sourcePlistDir = join(ctx.mindPath, 'launchd');
  const results: { name: string; success: boolean; error?: string }[] = [];

  // Check if source directory exists
  if (!existsSync(sourcePlistDir)) {
    spinner.stop('Source directory not found');
    p.log.warn(`Launchd plists not found at ${sourcePlistDir}`);
    p.log.message(color.dim('You may need to run birth.sh first or check the installation.'));
    return;
  }

  // Get all plist files
  const plistFiles = readdirSync(sourcePlistDir).filter((f) => f.endsWith('.plist'));

  if (plistFiles.length === 0) {
    spinner.stop('No plist files found');
    p.log.warn('No launchd plist files found to install.');
    return;
  }

  // Process each plist
  for (const plistFile of plistFiles) {
    const sourcePath = join(sourcePlistDir, plistFile);
    const destPath = join(LAUNCH_AGENTS_DIR, plistFile);
    const label = basename(plistFile, '.plist');

    try {
      // Check if already loaded
      const alreadyLoaded = await isLaunchAgentLoaded(label);
      if (alreadyLoaded) {
        results.push({ name: label, success: true });
        continue;
      }

      // Copy to LaunchAgents
      copyFileSync(sourcePath, destPath);

      // Load the agent
      const loaded = await loadLaunchAgent(destPath);
      results.push({
        name: label,
        success: loaded,
        error: loaded ? undefined : 'Failed to load',
      });
    } catch (error) {
      results.push({
        name: label,
        success: false,
        error: error instanceof Error ? error.message : String(error),
      });
    }
  }

  spinner.stop('Services processed');

  // Display results
  const successful = results.filter((r) => r.success);
  const failed = results.filter((r) => !r.success);

  for (const result of successful) {
    p.log.success(`${color.green('\u2713')} ${result.name}`);
  }

  for (const result of failed) {
    p.log.error(`${color.red('\u2717')} ${result.name}: ${result.error}`);
  }

  if (failed.length > 0) {
    p.note(
      `Some services failed to load. You can try loading them manually:

${failed.map((f) => `  launchctl load ~/Library/LaunchAgents/${f.name}.plist`).join('\n')}`,
      'Manual Loading'
    );

    const continueAnyway = await p.confirm({
      message: 'Continue with setup?',
      initialValue: true,
    });

    if (p.isCancel(continueAnyway) || !continueAnyway) {
      p.cancel('Setup cancelled.');
      process.exit(1);
    }
  } else {
    p.log.success(`All ${successful.length} services installed`);

    // Show schedule
    p.note(
      `${color.bold('Wake Schedule')}
  9:00 AM  - Morning wake
  2:00 PM  - Afternoon wake
  8:00 PM  - Evening wake
  3:00 AM  - Dream cycle`,
      'Autonomy Cycles'
    );
  }
}
