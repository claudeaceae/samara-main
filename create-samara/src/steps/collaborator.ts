import * as p from '@clack/prompts';
import color from 'picocolors';
import type { WizardContext } from '../types.js';
import { isValidEmail, isValidPhone } from '../utils/validation.js';

export async function collaborator(ctx: WizardContext): Promise<void> {
  p.log.step('Collaborator Details');
  p.log.message(color.dim("Now let's set up your information (the human collaborator)."));

  const result = await p.group(
    {
      name: () =>
        p.text({
          message: "Your name",
          placeholder: 'Your name',
          validate: (value) => {
            if (!value || value.length === 0) return 'Name is required';
            if (value.length > 100) return 'Name must be 100 characters or less';
            return undefined;
          },
        }),

      phone: () =>
        p.text({
          message: "Your phone number (for iMessage)",
          placeholder: '+14155551234',
          validate: (value) => {
            if (!value || value.length === 0) return 'Phone number is required';
            if (!isValidPhone(value)) return 'Must be E.164 format: +1234567890';
            return undefined;
          },
        }),

      email: () =>
        p.text({
          message: "Your email",
          placeholder: 'you@example.com',
          validate: (value) => {
            if (!value || value.length === 0) return 'Email is required';
            if (!isValidEmail(value)) return 'Must be a valid email address';
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

  // Initialize config.collaborator if needed
  ctx.config.collaborator = ctx.config.collaborator || {};
  ctx.config.collaborator.name = result.name;
  ctx.config.collaborator.phone = result.phone;
  ctx.config.collaborator.email = result.email;

  p.log.success(`Collaborator: ${color.cyan(result.name)} <${result.email}>`);
}
