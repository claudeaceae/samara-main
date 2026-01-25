import { z } from 'zod';

declare const configSchema: z.ZodObject<{
    entity: z.ZodObject<{
        name: z.ZodDefault<z.ZodString>;
        icloud: z.ZodEffects<z.ZodString, string, string>;
        bluesky: z.ZodOptional<z.ZodString>;
        github: z.ZodOptional<z.ZodString>;
    }, "strip", z.ZodTypeAny, {
        name: string;
        icloud: string;
        bluesky?: string | undefined;
        github?: string | undefined;
    }, {
        icloud: string;
        name?: string | undefined;
        bluesky?: string | undefined;
        github?: string | undefined;
    }>;
    collaborator: z.ZodObject<{
        name: z.ZodString;
        phone: z.ZodString;
        email: z.ZodString;
        bluesky: z.ZodOptional<z.ZodString>;
    }, "strip", z.ZodTypeAny, {
        name: string;
        phone: string;
        email: string;
        bluesky?: string | undefined;
    }, {
        name: string;
        phone: string;
        email: string;
        bluesky?: string | undefined;
    }>;
    notes: z.ZodDefault<z.ZodObject<{
        location: z.ZodDefault<z.ZodString>;
        scratchpad: z.ZodDefault<z.ZodString>;
    }, "strip", z.ZodTypeAny, {
        location: string;
        scratchpad: string;
    }, {
        location?: string | undefined;
        scratchpad?: string | undefined;
    }>>;
    mail: z.ZodDefault<z.ZodObject<{
        account: z.ZodDefault<z.ZodString>;
    }, "strip", z.ZodTypeAny, {
        account: string;
    }, {
        account?: string | undefined;
    }>>;
}, "strip", z.ZodTypeAny, {
    entity: {
        name: string;
        icloud: string;
        bluesky?: string | undefined;
        github?: string | undefined;
    };
    collaborator: {
        name: string;
        phone: string;
        email: string;
        bluesky?: string | undefined;
    };
    notes: {
        location: string;
        scratchpad: string;
    };
    mail: {
        account: string;
    };
}, {
    entity: {
        icloud: string;
        name?: string | undefined;
        bluesky?: string | undefined;
        github?: string | undefined;
    };
    collaborator: {
        name: string;
        phone: string;
        email: string;
        bluesky?: string | undefined;
    };
    notes?: {
        location?: string | undefined;
        scratchpad?: string | undefined;
    } | undefined;
    mail?: {
        account?: string | undefined;
    } | undefined;
}>;
type SamaraConfig = z.infer<typeof configSchema>;
type StepName = 'welcome' | 'identity' | 'collaborator' | 'integrations' | 'birth' | 'app' | 'permissions' | 'launchd' | 'credentials' | 'launch' | 'summary';
interface WizardContext {
    config: Partial<SamaraConfig>;
    repoPath: string;
    mindPath: string;
    hasDeveloperAccount: boolean;
    buildFromSource: boolean;
    teamId?: string;
    setupBluesky: boolean;
    setupGithub: boolean;
    completedSteps: Set<StepName>;
    currentStep: StepName;
}
interface SavedWizardState {
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

/**
 * Create a fresh wizard context
 */
declare function createContext(): WizardContext;
/**
 * Load saved wizard state if available and not expired
 */
declare function loadSavedState(): SavedWizardState | null;
/**
 * Restore wizard context from saved state
 */
declare function restoreFromState(saved: SavedWizardState): WizardContext;
/**
 * Save wizard state for resume capability
 */
declare function saveState(ctx: WizardContext, step: StepName): void;
/**
 * Clear saved wizard state (on completion or explicit reset)
 */
declare function clearState(): void;
/**
 * Check if a step should be skipped (already completed)
 */
declare function shouldSkipStep(ctx: WizardContext, step: StepName): boolean;
/**
 * Get the step to resume from
 */
declare function getResumeStep(saved: SavedWizardState): StepName;

/**
 * Validate email format
 */
declare function isValidEmail(email: string): boolean;
/**
 * Validate iCloud email
 */
declare function isValidICloudEmail(email: string): boolean;
/**
 * Validate E.164 phone format
 */
declare function isValidPhone(phone: string): boolean;
/**
 * Validate Bluesky handle format
 */
declare function isValidBlueskyHandle(handle: string): boolean;
/**
 * Validate GitHub username format
 */
declare function isValidGitHubUsername(username: string): boolean;
/**
 * Validate Apple Team ID format
 */
declare function isValidTeamId(teamId: string): boolean;
/**
 * Format phone number hint
 */
declare function formatPhoneHint(partial: string): string;
/**
 * Validate entity config
 */
declare function validateEntity(data: unknown): {
    success: true;
    data: unknown;
} | {
    success: false;
    error: string;
};
/**
 * Validate collaborator config
 */
declare function validateCollaborator(data: unknown): {
    success: true;
    data: unknown;
} | {
    success: false;
    error: string;
};

export { clearState, createContext, formatPhoneHint, getResumeStep, isValidBlueskyHandle, isValidEmail, isValidGitHubUsername, isValidICloudEmail, isValidPhone, isValidTeamId, loadSavedState, restoreFromState, saveState, shouldSkipStep, validateCollaborator, validateEntity };
