import { z } from 'zod';

// Entity (Claude's identity) schema
export const entitySchema = z.object({
  name: z.string().min(1).max(50).default('Claude'),
  icloud: z.string().email('Must be a valid email').refine(
    (email) => email.endsWith('@icloud.com'),
    'Must be an iCloud email address'
  ),
  bluesky: z.string().regex(/^@[\w.-]+\.bsky\.social$/, 'Must be @handle.bsky.social format').optional(),
  github: z.string().regex(/^[\w-]+$/, 'Must be a valid GitHub username').optional(),
});

// Collaborator (human partner) schema
export const collaboratorSchema = z.object({
  name: z.string().min(1).max(100),
  phone: z.string().regex(/^\+[1-9]\d{1,14}$/, 'Must be E.164 format: +1234567890'),
  email: z.string().email('Must be a valid email'),
  bluesky: z.string().regex(/^@[\w.-]+\.\w+$/, 'Must be @handle.domain format').optional(),
});

// Notes configuration schema
export const notesSchema = z.object({
  location: z.string().default('Claude Location Log'),
  scratchpad: z.string().default('Claude Scratchpad'),
});

// Mail configuration schema
export const mailSchema = z.object({
  account: z.string().default('iCloud'),
});

// Full configuration schema
export const configSchema = z.object({
  entity: entitySchema,
  collaborator: collaboratorSchema,
  notes: notesSchema.default({}),
  mail: mailSchema.default({}),
});

// Type definitions derived from schemas
export type EntityConfig = z.infer<typeof entitySchema>;
export type CollaboratorConfig = z.infer<typeof collaboratorSchema>;
export type NotesConfig = z.infer<typeof notesSchema>;
export type MailConfig = z.infer<typeof mailSchema>;
export type SamaraConfig = z.infer<typeof configSchema>;

// Wizard step names for checkpointing
export type StepName =
  | 'welcome'
  | 'identity'
  | 'collaborator'
  | 'integrations'
  | 'birth'
  | 'app'
  | 'permissions'
  | 'launchd'
  | 'credentials'
  | 'launch'
  | 'summary';

// Wizard context (shared state across steps)
export interface WizardContext {
  // Configuration being built
  config: Partial<SamaraConfig>;

  // Paths
  repoPath: string;
  mindPath: string;

  // Build options
  hasDeveloperAccount: boolean;
  buildFromSource: boolean;
  teamId?: string;

  // Integration selections
  setupBluesky: boolean;
  setupGithub: boolean;

  // Progress tracking
  completedSteps: Set<StepName>;
  currentStep: StepName;
}

// Saved wizard state for resume capability
export interface SavedWizardState {
  config: Partial<SamaraConfig>;
  completedSteps: StepName[];
  currentStep: StepName;
  hasDeveloperAccount: boolean;
  buildFromSource: boolean;
  teamId?: string;
  setupBluesky: boolean;
  setupGithub: boolean;
  timestamp: number;
}
