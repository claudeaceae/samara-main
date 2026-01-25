import * as p from '@clack/prompts';
import color from 'picocolors';
import { existsSync } from 'fs';
import type { WizardContext } from '../types.js';
import { run, isProcessRunning } from '../utils/shell.js';

const APP_PATH = '/Applications/Samara.app';

export async function launch(ctx: WizardContext): Promise<void> {
  p.log.step('Launch');

  if (!existsSync(APP_PATH)) {
    p.log.warn('Samara.app not found in /Applications/');
    p.log.message(color.dim('Skipping launch step. Please install the app manually.'));
    return;
  }

  // Check if already running
  const alreadyRunning = await isProcessRunning('Samara');
  if (alreadyRunning) {
    p.log.success('Samara is already running');
    return;
  }

  const spinner = p.spinner();
  spinner.start('Launching Samara...');

  try {
    // Launch the app
    await run('open', [APP_PATH], { silent: true });

    // Wait a moment for it to start
    await new Promise((resolve) => setTimeout(resolve, 2000));

    // Verify it's running
    const running = await isProcessRunning('Samara');

    if (running) {
      spinner.stop('Samara is running');
      p.log.success('Samara.app launched successfully');
    } else {
      spinner.stop('Launch may have failed');
      p.log.warn('Samara may not have started correctly.');

      const retry = await p.confirm({
        message: 'Try launching again?',
        initialValue: true,
      });

      if (p.isCancel(retry)) {
        p.cancel('Setup cancelled.');
        process.exit(0);
      }

      if (retry) {
        spinner.start('Retrying launch...');
        await run('open', [APP_PATH], { silent: true });
        await new Promise((resolve) => setTimeout(resolve, 3000));

        const runningRetry = await isProcessRunning('Samara');
        if (runningRetry) {
          spinner.stop('Samara is running');
          p.log.success('Samara.app launched on retry');
        } else {
          spinner.stop('Launch failed');
          p.log.warn('Could not verify Samara is running. You may need to launch it manually.');
        }
      }
    }
  } catch (error) {
    spinner.stop('Launch error');
    p.log.error(`Error: ${error instanceof Error ? error.message : String(error)}`);
    p.log.message(color.dim('You can launch Samara manually: open /Applications/Samara.app'));
  }
}
