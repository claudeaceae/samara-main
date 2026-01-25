#!/usr/bin/env node
import * as p from '@clack/prompts';
import color from 'picocolors';
import { existsSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import {
  createContext,
  loadSavedState,
  restoreFromState,
  saveState,
  shouldSkipStep,
  getResumeStep,
} from './context.js';
import type { StepName, WizardContext } from './types.js';

// Step imports
import { welcome } from './steps/welcome.js';
import { identity } from './steps/identity.js';
import { collaborator } from './steps/collaborator.js';
import { integrations } from './steps/integrations.js';
import { birth } from './steps/birth.js';
import { app } from './steps/app.js';
import { permissions } from './steps/permissions.js';
import { launchd } from './steps/launchd.js';
import { credentials } from './steps/credentials.js';
import { launch } from './steps/launch.js';
import { summary } from './steps/summary.js';

// Step definitions
interface Step {
  name: StepName;
  fn: (ctx: WizardContext) => Promise<void>;
}

const STEPS: Step[] = [
  { name: 'welcome', fn: welcome },
  { name: 'identity', fn: identity },
  { name: 'collaborator', fn: collaborator },
  { name: 'integrations', fn: integrations },
  { name: 'birth', fn: birth },
  { name: 'app', fn: app },
  { name: 'permissions', fn: permissions },
  { name: 'launchd', fn: launchd },
  { name: 'credentials', fn: credentials },
  { name: 'launch', fn: launch },
  { name: 'summary', fn: summary },
];

/**
 * Find the repo path by looking for birth.sh
 */
function findRepoPath(): string {
  // Try current directory
  if (existsSync(join(process.cwd(), 'birth.sh'))) {
    return process.cwd();
  }

  // Try parent directory
  const parentDir = dirname(process.cwd());
  if (existsSync(join(parentDir, 'birth.sh'))) {
    return parentDir;
  }

  // Try common locations
  const commonPaths = [
    join(process.env.HOME || '', 'Developer/samara-main'),
    join(process.env.HOME || '', 'Developer/samara'),
    join(process.env.HOME || '', 'samara-main'),
    join(process.env.HOME || '', 'samara'),
  ];

  for (const path of commonPaths) {
    if (existsSync(join(path, 'birth.sh'))) {
      return path;
    }
  }

  // Default to current directory
  return process.cwd();
}

async function main(): Promise<void> {
  console.clear();

  p.intro(color.bgCyan(color.black(' create-samara ')));

  // Check for saved state
  const savedState = loadSavedState();
  let ctx: WizardContext;

  if (savedState) {
    const resumeStep = getResumeStep(savedState);
    const shouldResume = await p.confirm({
      message: `Resume setup from "${resumeStep}" step?`,
      initialValue: true,
    });

    if (p.isCancel(shouldResume)) {
      p.cancel('Setup cancelled.');
      process.exit(0);
    }

    if (shouldResume) {
      ctx = restoreFromState(savedState);
      p.log.info(`Resuming from ${color.cyan(resumeStep)} step...`);
    } else {
      ctx = createContext();
      p.log.info('Starting fresh setup...');
    }
  } else {
    ctx = createContext();
  }

  // Find repo path
  ctx.repoPath = findRepoPath();

  if (!existsSync(join(ctx.repoPath, 'birth.sh'))) {
    p.log.warn(`Samara repository not found at ${ctx.repoPath}`);

    const repoPath = await p.text({
      message: 'Enter the path to your samara-main repository',
      placeholder: '~/Developer/samara-main',
      validate: (value) => {
        if (!value || value.length === 0) return 'Path is required';
        const expandedPath = value.replace('~', process.env.HOME || '');
        if (!existsSync(join(expandedPath, 'birth.sh'))) {
          return 'birth.sh not found at this location';
        }
        return undefined;
      },
    });

    if (p.isCancel(repoPath)) {
      p.cancel('Setup cancelled.');
      process.exit(0);
    }

    ctx.repoPath = repoPath.replace('~', process.env.HOME || '');
  }

  p.log.message(color.dim(`Using repository: ${ctx.repoPath}`));

  // Run steps
  for (const step of STEPS) {
    // Skip completed steps when resuming
    if (shouldSkipStep(ctx, step.name)) {
      p.log.message(color.dim(`Skipping ${step.name} (already completed)`));
      continue;
    }

    try {
      await step.fn(ctx);
      saveState(ctx, step.name);
    } catch (error) {
      p.log.error(`Error in ${step.name}: ${error instanceof Error ? error.message : String(error)}`);
      p.note(
        `Your progress has been saved. Run ${color.cyan('npx create-samara')} to resume.`,
        'Setup Paused'
      );
      process.exit(1);
    }
  }

  p.outro(color.green('Samara is alive!'));
}

// Run
main().catch((error) => {
  console.error('Unexpected error:', error);
  process.exit(1);
});
