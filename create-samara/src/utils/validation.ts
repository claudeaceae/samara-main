import { entitySchema, collaboratorSchema } from '../types.js';

/**
 * Validate email format
 */
export function isValidEmail(email: string): boolean {
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  return emailRegex.test(email);
}

/**
 * Validate iCloud email
 */
export function isValidICloudEmail(email: string): boolean {
  return isValidEmail(email) && email.toLowerCase().endsWith('@icloud.com');
}

/**
 * Validate E.164 phone format
 */
export function isValidPhone(phone: string): boolean {
  const e164Regex = /^\+[1-9]\d{1,14}$/;
  return e164Regex.test(phone);
}

/**
 * Validate Bluesky handle format
 */
export function isValidBlueskyHandle(handle: string): boolean {
  const blueskyRegex = /^@[\w.-]+\.bsky\.social$/;
  return blueskyRegex.test(handle);
}

/**
 * Validate GitHub username format
 */
export function isValidGitHubUsername(username: string): boolean {
  const githubRegex = /^[\w-]+$/;
  return githubRegex.test(username);
}

/**
 * Validate Apple Team ID format
 */
export function isValidTeamId(teamId: string): boolean {
  // Team IDs are 10-character alphanumeric strings
  const teamIdRegex = /^[A-Z0-9]{10}$/;
  return teamIdRegex.test(teamId);
}

/**
 * Format phone number hint
 */
export function formatPhoneHint(partial: string): string {
  if (!partial.startsWith('+')) {
    return 'Must start with + (e.g., +14155551234)';
  }
  if (partial.length < 10) {
    return 'Enter full number including country code';
  }
  return '';
}

/**
 * Validate entity config
 */
export function validateEntity(data: unknown): { success: true; data: unknown } | { success: false; error: string } {
  const result = entitySchema.safeParse(data);
  if (result.success) {
    return { success: true, data: result.data };
  }
  return { success: false, error: result.error.errors[0]?.message || 'Invalid entity configuration' };
}

/**
 * Validate collaborator config
 */
export function validateCollaborator(data: unknown): { success: true; data: unknown } | { success: false; error: string } {
  const result = collaboratorSchema.safeParse(data);
  if (result.success) {
    return { success: true, data: result.data };
  }
  return { success: false, error: result.error.errors[0]?.message || 'Invalid collaborator configuration' };
}
