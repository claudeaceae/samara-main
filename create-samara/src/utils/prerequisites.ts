import * as p from '@clack/prompts';
import color from 'picocolors';
import { commandExists, run, brewInstall } from './shell.js';
import { platform } from 'os';

export interface PrerequisiteResult {
  name: string;
  installed: boolean;
  version?: string;
  required: boolean;
  installable: boolean;
}

/**
 * Check if running on macOS
 */
export function isMacOS(): boolean {
  return platform() === 'darwin';
}

/**
 * Check Xcode Command Line Tools
 */
export async function checkXcodeTools(): Promise<PrerequisiteResult> {
  const result = await run('xcode-select', ['-p'], { silent: true });
  const installed = result.exitCode === 0;

  return {
    name: 'Xcode Command Line Tools',
    installed,
    required: true,
    installable: true,
  };
}

/**
 * Install Xcode Command Line Tools
 */
export async function installXcodeTools(): Promise<boolean> {
  p.log.info('Installing Xcode Command Line Tools...');
  p.log.info('A dialog will appear. Please complete the installation and run this wizard again.');
  await run('xcode-select', ['--install']);
  return false; // User needs to complete installation manually
}

/**
 * Check Homebrew
 */
export async function checkHomebrew(): Promise<PrerequisiteResult> {
  const installed = await commandExists('brew');
  let version: string | undefined;

  if (installed) {
    const result = await run('brew', ['--version'], { silent: true });
    version = result.stdout.split('\n')[0];
  }

  return {
    name: 'Homebrew',
    installed,
    version,
    required: true,
    installable: true,
  };
}

/**
 * Install Homebrew
 */
export async function installHomebrew(): Promise<boolean> {
  p.log.info('Installing Homebrew...');
  const result = await run('/bin/bash', [
    '-c',
    '$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)',
  ]);
  return result.exitCode === 0;
}

/**
 * Check jq
 */
export async function checkJq(): Promise<PrerequisiteResult> {
  const installed = await commandExists('jq');
  let version: string | undefined;

  if (installed) {
    const result = await run('jq', ['--version'], { silent: true });
    version = result.stdout.trim();
  }

  return {
    name: 'jq',
    installed,
    version,
    required: true,
    installable: true,
  };
}

/**
 * Install jq via Homebrew
 */
export async function installJq(): Promise<boolean> {
  p.log.info('Installing jq...');
  return brewInstall('jq');
}

/**
 * Check Claude Code CLI
 */
export async function checkClaudeCli(): Promise<PrerequisiteResult> {
  const installed = await commandExists('claude');
  let version: string | undefined;

  if (installed) {
    const result = await run('claude', ['--version'], { silent: true });
    version = result.stdout.trim();
  }

  return {
    name: 'Claude Code CLI',
    installed,
    version,
    required: true,
    installable: false, // Requires npm, not auto-installable
  };
}

/**
 * Check all prerequisites
 */
export async function checkAllPrerequisites(): Promise<PrerequisiteResult[]> {
  const results: PrerequisiteResult[] = [];

  // Check each prerequisite
  results.push(await checkXcodeTools());
  results.push(await checkHomebrew());
  results.push(await checkJq());
  results.push(await checkClaudeCli());

  return results;
}

/**
 * Display prerequisite check results
 */
export function displayPrerequisites(results: PrerequisiteResult[]): void {
  for (const result of results) {
    const status = result.installed
      ? color.green('\u2713')
      : color.red('\u2717');
    const version = result.version ? color.dim(` (${result.version})`) : '';
    p.log.message(`${status} ${result.name}${version}`);
  }
}

/**
 * Attempt to install missing prerequisites
 */
export async function installMissingPrerequisites(
  results: PrerequisiteResult[]
): Promise<{ success: boolean; needsRestart: boolean; missing: string[] }> {
  const missing: string[] = [];
  let needsRestart = false;

  for (const result of results) {
    if (result.installed) continue;

    if (!result.installable) {
      missing.push(result.name);
      continue;
    }

    // Try to install
    let installed = false;
    switch (result.name) {
      case 'Xcode Command Line Tools':
        installed = await installXcodeTools();
        if (!installed) needsRestart = true;
        break;
      case 'Homebrew':
        installed = await installHomebrew();
        break;
      case 'jq':
        installed = await installJq();
        break;
    }

    if (!installed && !needsRestart) {
      missing.push(result.name);
    }
  }

  return {
    success: missing.length === 0 && !needsRestart,
    needsRestart,
    missing,
  };
}

/**
 * Get installation instructions for Claude CLI
 */
export function getClaudeCliInstructions(): string {
  return `
To install Claude Code CLI:

  ${color.cyan('npm install -g @anthropic-ai/claude-code')}

Or see: ${color.underline('https://docs.anthropic.com/claude-code')}
`;
}
