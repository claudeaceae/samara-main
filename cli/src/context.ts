import Conf from 'conf';
import { homedir } from 'os';
import { join } from 'path';
import type { WizardContext, SavedWizardState, StepName } from './types.js';

// Persistent storage for wizard state
const store = new Conf<{ wizardState?: SavedWizardState }>({
  projectName: 'create-samara',
});

// State expiry time (24 hours)
const STATE_EXPIRY_MS = 24 * 60 * 60 * 1000;

/**
 * Create a fresh wizard context
 */
export function createContext(): WizardContext {
  return {
    config: {},
    repoPath: process.cwd(),
    mindPath: join(homedir(), '.claude-mind'),
    hasDeveloperAccount: false,
    buildFromSource: false,
    setupBluesky: false,
    setupGithub: false,
    completedSteps: new Set(),
    currentStep: 'welcome',
  };
}

/**
 * Load saved wizard state if available and not expired
 */
export function loadSavedState(): SavedWizardState | null {
  const saved = store.get('wizardState');

  if (!saved) return null;

  // Check if expired
  if (Date.now() - saved.timestamp > STATE_EXPIRY_MS) {
    store.delete('wizardState');
    return null;
  }

  return saved;
}

/**
 * Restore wizard context from saved state
 */
export function restoreFromState(saved: SavedWizardState): WizardContext {
  return {
    config: saved.config,
    repoPath: process.cwd(),
    mindPath: join(homedir(), '.claude-mind'),
    hasDeveloperAccount: saved.hasDeveloperAccount,
    buildFromSource: saved.buildFromSource,
    teamId: saved.teamId,
    setupBluesky: saved.setupBluesky,
    setupGithub: saved.setupGithub,
    completedSteps: new Set(saved.completedSteps),
    currentStep: saved.currentStep,
  };
}

/**
 * Save wizard state for resume capability
 */
export function saveState(ctx: WizardContext, step: StepName): void {
  ctx.completedSteps.add(step);
  ctx.currentStep = step;

  const state: SavedWizardState = {
    config: ctx.config,
    completedSteps: Array.from(ctx.completedSteps),
    currentStep: step,
    hasDeveloperAccount: ctx.hasDeveloperAccount,
    buildFromSource: ctx.buildFromSource,
    teamId: ctx.teamId,
    setupBluesky: ctx.setupBluesky,
    setupGithub: ctx.setupGithub,
    timestamp: Date.now(),
  };

  store.set('wizardState', state);
}

/**
 * Clear saved wizard state (on completion or explicit reset)
 */
export function clearState(): void {
  store.delete('wizardState');
}

/**
 * Check if a step should be skipped (already completed)
 */
export function shouldSkipStep(ctx: WizardContext, step: StepName): boolean {
  return ctx.completedSteps.has(step);
}

/**
 * Get the step to resume from
 */
export function getResumeStep(saved: SavedWizardState): StepName {
  // Find the first step that wasn't completed
  const steps: StepName[] = [
    'welcome',
    'identity',
    'collaborator',
    'integrations',
    'birth',
    'app',
    'permissions',
    'launchd',
    'credentials',
    'launch',
    'summary',
  ];

  for (const step of steps) {
    if (!saved.completedSteps.includes(step)) {
      return step;
    }
  }

  return 'summary';
}
