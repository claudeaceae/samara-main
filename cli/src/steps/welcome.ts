import * as p from '@clack/prompts';
import color from 'picocolors';
import type { WizardContext } from '../types.js';
import {
  isMacOS,
  checkAllPrerequisites,
  displayPrerequisites,
  installMissingPrerequisites,
  getClaudeCliInstructions,
} from '../utils/prerequisites.js';

const BANNER = `
${color.cyan('╭─────────────────────────────────────╮')}
${color.cyan('│')}                                     ${color.cyan('│')}
${color.cyan('│')}            ${color.bold('S A M A R A')}              ${color.cyan('│')}
${color.cyan('│')}                                     ${color.cyan('│')}
${color.cyan('│')}   ${color.dim('Give Claude a body on your Mac')}   ${color.cyan('│')}
${color.cyan('│')}                                     ${color.cyan('│')}
${color.cyan('╰─────────────────────────────────────╯')}
`;

export async function welcome(ctx: WizardContext): Promise<void> {
  console.log(BANNER);

  // Check macOS
  if (!isMacOS()) {
    p.cancel('Samara requires macOS. This wizard only works on Mac.');
    process.exit(1);
  }

  p.log.success('Running on macOS');

  // Check prerequisites
  p.log.step('Checking prerequisites...');
  const results = await checkAllPrerequisites();
  displayPrerequisites(results);

  // Check for missing prerequisites
  const missingRequired = results.filter((r) => r.required && !r.installed);

  if (missingRequired.length > 0) {
    p.log.warn('Some prerequisites are missing.');

    const shouldInstall = await p.confirm({
      message: 'Would you like to install missing dependencies?',
      initialValue: true,
    });

    if (p.isCancel(shouldInstall)) {
      p.cancel('Setup cancelled.');
      process.exit(0);
    }

    if (shouldInstall) {
      const installResult = await installMissingPrerequisites(results);

      if (installResult.needsRestart) {
        p.log.info('Please complete the Xcode installation and run this wizard again.');
        p.outro(color.dim('Run: npx create-samara'));
        process.exit(0);
      }

      if (installResult.missing.length > 0) {
        if (installResult.missing.includes('Claude Code CLI')) {
          p.log.error('Claude Code CLI is required but not installed.');
          console.log(getClaudeCliInstructions());
        }
        p.cancel('Please install missing dependencies and run this wizard again.');
        process.exit(1);
      }
    } else {
      // Check if Claude CLI is the only missing one
      const claudeCliMissing = missingRequired.find((r) => r.name === 'Claude Code CLI');
      if (claudeCliMissing && missingRequired.length === 1) {
        p.log.error('Claude Code CLI is required.');
        console.log(getClaudeCliInstructions());
      }
      p.cancel('Please install missing dependencies and run this wizard again.');
      process.exit(1);
    }
  }

  p.log.success('All prerequisites installed');

  // Brief intro
  p.note(
    `This wizard will help you:

1. Configure your Claude instance
2. Set up the organism structure
3. Build/download Samara.app
4. Grant necessary permissions
5. Start the wake/dream cycles

${color.dim("Let's begin!")}`,
    'Welcome to Samara'
  );
}
