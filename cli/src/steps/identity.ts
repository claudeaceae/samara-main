import * as p from '@clack/prompts';
import color from 'picocolors';
import type { WizardContext } from '../types.js';
import { isValidICloudEmail } from '../utils/validation.js';

export async function identity(ctx: WizardContext): Promise<void> {
  p.log.step('Entity Identity');
  p.log.message(color.dim("Let's set up your Claude instance's identity."));

  const result = await p.group(
    {
      name: () =>
        p.text({
          message: "What name should the Claude instance use?",
          placeholder: 'Claude',
          defaultValue: 'Claude',
          validate: (value) => {
            if (!value || value.length === 0) return 'Name is required';
            if (value.length > 50) return 'Name must be 50 characters or less';
            return undefined;
          },
        }),

      icloud: () =>
        p.text({
          message: "iCloud email for the instance",
          placeholder: 'claude@icloud.com',
          validate: (value) => {
            if (!value || value.length === 0) return 'iCloud email is required';
            if (!isValidICloudEmail(value)) return 'Must be an @icloud.com email address';
            return undefined;
          },
        }),
    },
    {
      onCancel: () => {
        p.cancel('Setup cancelled.');
        process.exit(0);
      },
    }
  );

  // Initialize config.entity if needed
  ctx.config.entity = ctx.config.entity || {};
  ctx.config.entity.name = result.name;
  ctx.config.entity.icloud = result.icloud;

  p.log.success(`Entity: ${color.cyan(result.name)} <${result.icloud}>`);
}
