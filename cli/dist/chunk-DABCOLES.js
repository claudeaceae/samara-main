// src/context.ts
import Conf from "conf";
import { homedir } from "os";
import { join, resolve } from "path";
var store = new Conf({
  projectName: "create-samara"
});
var STATE_EXPIRY_MS = 24 * 60 * 60 * 1e3;
function expandTilde(value) {
  if (value === "~") return homedir();
  if (value.startsWith("~/")) return join(homedir(), value.slice(2));
  return value;
}
function resolveMindPath() {
  const override = process.env.SAMARA_MIND_PATH || process.env.MIND_PATH;
  if (override && override.trim().length > 0) {
    return resolve(expandTilde(override));
  }
  return join(homedir(), ".claude-mind");
}
function createContext() {
  return {
    config: {},
    repoPath: process.cwd(),
    mindPath: resolveMindPath(),
    hasDeveloperAccount: false,
    buildFromSource: false,
    setupBluesky: false,
    setupGithub: false,
    completedSteps: /* @__PURE__ */ new Set(),
    currentStep: "welcome"
  };
}
function loadSavedState() {
  const saved = store.get("wizardState");
  if (!saved) return null;
  if (Date.now() - saved.timestamp > STATE_EXPIRY_MS) {
    store.delete("wizardState");
    return null;
  }
  return saved;
}
function restoreFromState(saved) {
  return {
    config: saved.config,
    repoPath: process.cwd(),
    mindPath: resolveMindPath(),
    hasDeveloperAccount: saved.hasDeveloperAccount,
    buildFromSource: saved.buildFromSource,
    teamId: saved.teamId,
    setupBluesky: saved.setupBluesky,
    setupGithub: saved.setupGithub,
    completedSteps: new Set(saved.completedSteps),
    currentStep: saved.currentStep
  };
}
function saveState(ctx, step) {
  ctx.completedSteps.add(step);
  ctx.currentStep = step;
  const state = {
    config: ctx.config,
    completedSteps: Array.from(ctx.completedSteps),
    currentStep: step,
    hasDeveloperAccount: ctx.hasDeveloperAccount,
    buildFromSource: ctx.buildFromSource,
    teamId: ctx.teamId,
    setupBluesky: ctx.setupBluesky,
    setupGithub: ctx.setupGithub,
    timestamp: Date.now()
  };
  store.set("wizardState", state);
}
function clearState() {
  store.delete("wizardState");
}
function shouldSkipStep(ctx, step) {
  return ctx.completedSteps.has(step);
}
function getResumeStep(saved) {
  const steps = [
    "welcome",
    "identity",
    "collaborator",
    "integrations",
    "birth",
    "app",
    "permissions",
    "launchd",
    "credentials",
    "launch",
    "summary"
  ];
  for (const step of steps) {
    if (!saved.completedSteps.includes(step)) {
      return step;
    }
  }
  return "summary";
}

// src/types.ts
import { z } from "zod";
var entitySchema = z.object({
  name: z.string().min(1).max(50).default("Claude"),
  icloud: z.string().email("Must be a valid email").refine(
    (email) => email.endsWith("@icloud.com"),
    "Must be an iCloud email address"
  ),
  bluesky: z.string().regex(/^@[\w.-]+\.bsky\.social$/, "Must be @handle.bsky.social format").optional(),
  github: z.string().regex(/^[\w-]+$/, "Must be a valid GitHub username").optional()
});
var collaboratorSchema = z.object({
  name: z.string().min(1).max(100),
  phone: z.string().regex(/^\+[1-9]\d{1,14}$/, "Must be E.164 format: +1234567890"),
  email: z.string().email("Must be a valid email"),
  bluesky: z.string().regex(/^@[\w.-]+\.\w+$/, "Must be @handle.domain format").optional()
});
var notesSchema = z.object({
  location: z.string().default("Claude Location Log"),
  scratchpad: z.string().default("Claude Scratchpad")
});
var mailSchema = z.object({
  account: z.string().default("iCloud")
});
var configSchema = z.object({
  entity: entitySchema,
  collaborator: collaboratorSchema,
  notes: notesSchema.default({}),
  mail: mailSchema.default({})
});

// src/utils/validation.ts
function isValidEmail(email) {
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  return emailRegex.test(email);
}
function isValidICloudEmail(email) {
  return isValidEmail(email) && email.toLowerCase().endsWith("@icloud.com");
}
function isValidPhone(phone) {
  const e164Regex = /^\+[1-9]\d{1,14}$/;
  return e164Regex.test(phone);
}
function isValidBlueskyHandle(handle) {
  const blueskyRegex = /^@[\w.-]+\.bsky\.social$/;
  return blueskyRegex.test(handle);
}
function isValidGitHubUsername(username) {
  const githubRegex = /^[\w-]+$/;
  return githubRegex.test(username);
}
function isValidTeamId(teamId) {
  const teamIdRegex = /^[A-Z0-9]{10}$/;
  return teamIdRegex.test(teamId);
}
function formatPhoneHint(partial) {
  if (!partial.startsWith("+")) {
    return "Must start with + (e.g., +14155551234)";
  }
  if (partial.length < 10) {
    return "Enter full number including country code";
  }
  return "";
}
function validateEntity(data) {
  const result = entitySchema.safeParse(data);
  if (result.success) {
    return { success: true, data: result.data };
  }
  return { success: false, error: result.error.errors[0]?.message || "Invalid entity configuration" };
}
function validateCollaborator(data) {
  const result = collaboratorSchema.safeParse(data);
  if (result.success) {
    return { success: true, data: result.data };
  }
  return { success: false, error: result.error.errors[0]?.message || "Invalid collaborator configuration" };
}

export {
  createContext,
  loadSavedState,
  restoreFromState,
  saveState,
  clearState,
  shouldSkipStep,
  getResumeStep,
  isValidEmail,
  isValidICloudEmail,
  isValidPhone,
  isValidBlueskyHandle,
  isValidGitHubUsername,
  isValidTeamId,
  formatPhoneHint,
  validateEntity,
  validateCollaborator
};
//# sourceMappingURL=chunk-DABCOLES.js.map