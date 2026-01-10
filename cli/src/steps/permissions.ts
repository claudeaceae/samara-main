import * as p from '@clack/prompts';
import color from 'picocolors';
import { existsSync, accessSync, constants } from 'fs';
import { homedir } from 'os';
import { join } from 'path';
import type { WizardContext } from '../types.js';
import { openSystemPreferences } from '../utils/shell.js';

const CHAT_DB_PATH = join(homedir(), 'Library/Messages/chat.db');

export async function permissions(ctx: WizardContext): Promise<void> {
  p.log.step('Permissions');
  p.log.message(color.dim('Samara needs Full Disk Access to read messages.'));

  // Check if FDA is already granted by trying to access chat.db
  if (await hasFdaAccess()) {
    p.log.success('Full Disk Access already granted');
    return;
  }

  p.note(
    `${color.bold('Grant Full Disk Access')}

1. Opening System Settings...
2. Click the ${color.cyan('+')} button
3. Navigate to ${color.cyan('/Applications/Samara.app')}
4. Add it to the list
5. Enable the toggle

${color.dim('Press Enter when done.')}`,
    'Full Disk Access'
  );

  // Open System Preferences to FDA pane
  await openSystemPreferences('com.apple.preference.security?Privacy_AllFiles');

  // Wait for user to grant access
  let attempts = 0;
  const maxAttempts = 3;

  while (attempts < maxAttempts) {
    const proceed = await p.text({
      message: 'Press Enter after granting Full Disk Access',
      placeholder: '',
    });

    if (p.isCancel(proceed)) {
      p.cancel('Setup cancelled.');
      process.exit(0);
    }

    if (await hasFdaAccess()) {
      p.log.success('Full Disk Access granted');
      return;
    }

    attempts++;
    if (attempts < maxAttempts) {
      p.log.warn('Full Disk Access not detected. Please try again.');
      p.log.message(color.dim(`Make sure Samara.app is added to the list and the toggle is enabled.`));
    }
  }

  // If we get here, FDA wasn't granted after multiple attempts
  const skipFda = await p.confirm({
    message: 'Continue without Full Disk Access? (iMessage reading will not work)',
    initialValue: false,
  });

  if (p.isCancel(skipFda)) {
    p.cancel('Setup cancelled.');
    process.exit(0);
  }

  if (!skipFda) {
    p.note(
      `${color.bold('Troubleshooting Full Disk Access')}

1. Make sure you're adding the correct app:
   ${color.cyan('/Applications/Samara.app')}

2. The app must be in /Applications, not elsewhere

3. The toggle must be ${color.green('ON')} (green)

4. You may need to restart Samara.app after granting

5. Try removing and re-adding the app if it doesn't work`,
      'Help'
    );

    p.cancel('Please grant Full Disk Access and run this wizard again.');
    process.exit(1);
  }

  p.log.warn('Continuing without Full Disk Access. iMessage features will not work.');
}

/**
 * Check if Full Disk Access is granted by trying to read chat.db
 */
async function hasFdaAccess(): Promise<boolean> {
  try {
    // Check if chat.db exists and is readable
    if (!existsSync(CHAT_DB_PATH)) {
      // chat.db doesn't exist, which is fine - FDA might still be granted
      // This can happen on new accounts or if Messages hasn't been used
      return true;
    }

    // Try to access the file
    accessSync(CHAT_DB_PATH, constants.R_OK);
    return true;
  } catch {
    // Access denied - FDA not granted
    return false;
  }
}
