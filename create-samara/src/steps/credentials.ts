import * as p from '@clack/prompts';
import color from 'picocolors';
import { existsSync, writeFileSync, mkdirSync } from 'fs';
import { join } from 'path';
import type { WizardContext } from '../types.js';

export async function credentials(ctx: WizardContext): Promise<void> {
  // Skip if no integrations were selected
  if (!ctx.setupBluesky && !ctx.setupGithub) {
    p.log.message(color.dim('No credentials needed (no integrations selected).'));
    return;
  }

  p.log.step('Credentials');
  p.log.message(color.dim('Set up API keys for your integrations.'));

  const credentialsDir = join(ctx.mindPath, 'credentials');

  // Ensure credentials directory exists
  if (!existsSync(credentialsDir)) {
    mkdirSync(credentialsDir, { recursive: true });
  }

  // Bluesky credentials
  if (ctx.setupBluesky) {
    p.note(
      `${color.bold('Bluesky App Password')}

1. Go to ${color.cyan('https://bsky.app/settings/app-passwords')}
2. Create a new app password
3. Copy the password (looks like: xxxx-xxxx-xxxx-xxxx)`,
      'Bluesky Setup'
    );

    const blueskyPassword = await p.password({
      message: 'Enter Bluesky app password (or leave empty to skip)',
    });

    if (p.isCancel(blueskyPassword)) {
      p.cancel('Setup cancelled.');
      process.exit(0);
    }

    if (blueskyPassword && blueskyPassword.length > 0) {
      const blueskyHandle = ctx.config.entity?.bluesky || '';
      const blueskyCredentials = {
        identifier: blueskyHandle.replace('@', ''),
        password: blueskyPassword,
      };

      const blueskyPath = join(credentialsDir, 'bluesky.json');
      writeFileSync(blueskyPath, JSON.stringify(blueskyCredentials, null, 2), { mode: 0o600 });
      p.log.success(`Bluesky credentials saved to ${color.dim(blueskyPath)}`);
    } else {
      p.log.message(color.dim('Skipped Bluesky credentials. You can add them later.'));
    }
  }

  // GitHub credentials
  if (ctx.setupGithub) {
    p.note(
      `${color.bold('GitHub Personal Access Token')}

1. Go to ${color.cyan('https://github.com/settings/tokens')}
2. Generate new token (classic)
3. Select scopes: repo, user (at minimum)
4. Copy the token`,
      'GitHub Setup'
    );

    const githubToken = await p.password({
      message: 'Enter GitHub personal access token (or leave empty to skip)',
    });

    if (p.isCancel(githubToken)) {
      p.cancel('Setup cancelled.');
      process.exit(0);
    }

    if (githubToken && githubToken.length > 0) {
      const githubPath = join(credentialsDir, 'github.txt');
      writeFileSync(githubPath, githubToken, { mode: 0o600 });
      p.log.success(`GitHub token saved to ${color.dim(githubPath)}`);
    } else {
      p.log.message(color.dim('Skipped GitHub credentials. You can add them later.'));
    }
  }
}
