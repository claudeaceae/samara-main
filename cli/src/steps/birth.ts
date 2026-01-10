import * as p from '@clack/prompts';
import color from 'picocolors';
import { writeFileSync, existsSync, mkdirSync } from 'fs';
import { join } from 'path';
import { tmpdir } from 'os';
import type { WizardContext, SamaraConfig } from '../types.js';
import { runBirth } from '../utils/shell.js';

export async function birth(ctx: WizardContext): Promise<void> {
  p.log.step('Configuration Review');

  // Build the full config object
  const config: SamaraConfig = {
    entity: {
      name: ctx.config.entity?.name || 'Claude',
      icloud: ctx.config.entity?.icloud || '',
      bluesky: ctx.config.entity?.bluesky,
      github: ctx.config.entity?.github,
    },
    collaborator: {
      name: ctx.config.collaborator?.name || '',
      phone: ctx.config.collaborator?.phone || '',
      email: ctx.config.collaborator?.email || '',
      bluesky: ctx.config.collaborator?.bluesky,
    },
    notes: {
      location: 'Claude Location Log',
      scratchpad: 'Claude Scratchpad',
    },
    mail: {
      account: 'iCloud',
    },
  };

  // Display config preview
  const configPreview = `
${color.bold('Entity (Claude)')}
  Name:    ${color.cyan(config.entity.name)}
  iCloud:  ${config.entity.icloud}
  ${config.entity.bluesky ? `Bluesky: ${config.entity.bluesky}` : ''}
  ${config.entity.github ? `GitHub:  ${config.entity.github}` : ''}

${color.bold('Collaborator (You)')}
  Name:   ${color.cyan(config.collaborator.name)}
  Phone:  ${config.collaborator.phone}
  Email:  ${config.collaborator.email}
  ${config.collaborator.bluesky ? `Bluesky: ${config.collaborator.bluesky}` : ''}
`;

  p.note(configPreview, 'Your Configuration');

  const proceed = await p.confirm({
    message: 'Proceed with this configuration?',
    initialValue: true,
  });

  if (p.isCancel(proceed) || !proceed) {
    p.cancel('Setup cancelled. Run npx create-samara to start over.');
    process.exit(0);
  }

  // Write config to temp file
  const tempDir = join(tmpdir(), 'create-samara');
  if (!existsSync(tempDir)) {
    mkdirSync(tempDir, { recursive: true });
  }
  const configPath = join(tempDir, 'config.json');
  writeFileSync(configPath, JSON.stringify(config, null, 2));

  // Run birth script
  p.log.step('Creating organism structure...');

  const spinner = p.spinner();
  spinner.start('Running birth script...');

  try {
    const success = await runBirth(configPath, ctx.repoPath);

    if (success) {
      spinner.stop('Organism structure created');
      p.log.success(`Created ${color.cyan('~/.claude-mind/')}`);
    } else {
      spinner.stop('Birth script failed');
      p.log.error('The birth script encountered an error.');
      p.log.message(color.dim('Check the output above for details.'));
      p.log.message(color.dim(`You can also try running manually: ${ctx.repoPath}/birth.sh ${configPath}`));

      const retry = await p.confirm({
        message: 'Would you like to retry?',
        initialValue: true,
      });

      if (p.isCancel(retry) || !retry) {
        p.cancel('Setup cancelled.');
        process.exit(1);
      }

      // Retry
      spinner.start('Retrying birth script...');
      const retrySuccess = await runBirth(configPath, ctx.repoPath);

      if (!retrySuccess) {
        spinner.stop('Birth script failed again');
        p.cancel('Please check the birth script manually and run this wizard again.');
        process.exit(1);
      }

      spinner.stop('Organism structure created on retry');
    }
  } catch (error) {
    spinner.stop('Birth script error');
    p.log.error(`Error: ${error instanceof Error ? error.message : String(error)}`);
    p.cancel('Setup failed. Please check the error and try again.');
    process.exit(1);
  }

  // Also save config to the mind directory
  const mindConfigPath = join(ctx.mindPath, 'config.json');
  if (existsSync(ctx.mindPath)) {
    writeFileSync(mindConfigPath, JSON.stringify(config, null, 2));
    p.log.success(`Config saved to ${color.dim(mindConfigPath)}`);
  }
}
