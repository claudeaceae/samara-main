import * as p from '@clack/prompts';
import color from 'picocolors';
import type { WizardContext } from '../types.js';
import { isValidBlueskyHandle, isValidGitHubUsername } from '../utils/validation.js';

export async function integrations(ctx: WizardContext): Promise<void> {
  p.log.step('Optional Integrations');
  p.log.message(color.dim('Set up social accounts for your Claude instance (optional).'));

  // Ask about Bluesky
  const setupBluesky = await p.confirm({
    message: 'Set up Bluesky account?',
    initialValue: false,
  });

  if (p.isCancel(setupBluesky)) {
    p.cancel('Setup cancelled.');
    process.exit(0);
  }

  ctx.setupBluesky = setupBluesky;

  if (setupBluesky) {
    const blueskyHandle = await p.text({
      message: "Claude's Bluesky handle",
      placeholder: '@claude.bsky.social',
      validate: (value) => {
        if (!value || value.length === 0) return 'Handle is required if setting up Bluesky';
        if (!isValidBlueskyHandle(value)) return 'Must be @handle.bsky.social format';
        return undefined;
      },
    });

    if (p.isCancel(blueskyHandle)) {
      p.cancel('Setup cancelled.');
      process.exit(0);
    }

    ctx.config.entity = ctx.config.entity || {};
    ctx.config.entity.bluesky = blueskyHandle;
    p.log.success(`Bluesky: ${color.cyan(blueskyHandle)}`);
  }

  // Ask about GitHub
  const setupGithub = await p.confirm({
    message: 'Set up GitHub account?',
    initialValue: false,
  });

  if (p.isCancel(setupGithub)) {
    p.cancel('Setup cancelled.');
    process.exit(0);
  }

  ctx.setupGithub = setupGithub;

  if (setupGithub) {
    const githubUsername = await p.text({
      message: "Claude's GitHub username",
      placeholder: 'claude-bot',
      validate: (value) => {
        if (!value || value.length === 0) return 'Username is required if setting up GitHub';
        if (!isValidGitHubUsername(value)) return 'Must be a valid GitHub username';
        return undefined;
      },
    });

    if (p.isCancel(githubUsername)) {
      p.cancel('Setup cancelled.');
      process.exit(0);
    }

    ctx.config.entity = ctx.config.entity || {};
    ctx.config.entity.github = githubUsername;
    p.log.success(`GitHub: ${color.cyan(githubUsername)}`);
  }

  // Ask about collaborator's Bluesky (optional)
  if (setupBluesky) {
    const collaboratorBluesky = await p.text({
      message: "Your Bluesky handle (optional)",
      placeholder: '@you.bsky.social',
      validate: (value) => {
        if (!value || value.length === 0) return undefined; // Optional
        if (!isValidBlueskyHandle(value.startsWith('@') ? value : `@${value}`)) {
          return 'Must be @handle.bsky.social format';
        }
        return undefined;
      },
    });

    if (p.isCancel(collaboratorBluesky)) {
      p.cancel('Setup cancelled.');
      process.exit(0);
    }

    if (collaboratorBluesky && collaboratorBluesky.length > 0) {
      ctx.config.collaborator = ctx.config.collaborator || {};
      ctx.config.collaborator.bluesky = collaboratorBluesky.startsWith('@')
        ? collaboratorBluesky
        : `@${collaboratorBluesky}`;
    }
  }

  if (!setupBluesky && !setupGithub) {
    p.log.message(color.dim('No integrations selected. You can set these up later.'));
  }
}
