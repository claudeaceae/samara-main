import * as p from '@clack/prompts';
import color from 'picocolors';
import { join } from 'path';
import type { WizardContext } from '../types.js';
import { clearState } from '../context.js';

export async function summary(ctx: WizardContext): Promise<void> {
  // Clear saved state - setup is complete
  clearState();

  const entityName = ctx.config.entity?.name || 'Claude';
  const collaboratorName = ctx.config.collaborator?.name || 'You';
  const collaboratorPhone = ctx.config.collaborator?.phone || '';
  const logsPath = join(ctx.mindPath, 'logs');
  const configPath = join(ctx.mindPath, 'config.json');
  const samaraLogPath = join(logsPath, 'samara.log');

  const nextSteps = `
${color.bold('Setup Complete!')}

${color.cyan(entityName)} is now running on this Mac.

${color.bold('Test it out:')}
  Send a message from your phone to ${entityName}
  ${collaboratorPhone ? `(from ${collaboratorPhone})` : ''}

${color.bold('Wake Schedule:')}
  9:00 AM  - Morning wake
  2:00 PM  - Afternoon wake
  8:00 PM  - Evening wake
  3:00 AM  - Dream cycle

${color.bold('Useful commands:')}
  ${color.cyan('claude')}              - Start a conversation
  ${color.cyan('/status')}             - Check system health
  ${color.cyan('/sync')}               - Check for drift

${color.bold('Locations:')}
  Memory:  ${color.dim(ctx.mindPath)}
  Logs:    ${color.dim(logsPath)}
  Config:  ${color.dim(configPath)}

${color.bold('Learn more:')}
  ${color.underline('https://github.com/claudeaceae/samara-main')}
  ${color.underline('https://claude.organelle.co')}
`;

  console.log(nextSteps);

  p.note(
    `${color.bold(`Hello, ${collaboratorName}!`)}

I'm ${entityName}. Send me a message whenever you're ready.

If you don't hear back, check if I'm running:
  ${color.cyan('pgrep -fl Samara')}

Or check the logs:
  ${color.cyan(`tail -f ${samaraLogPath}`)}`,
    `From ${entityName}`
  );
}
