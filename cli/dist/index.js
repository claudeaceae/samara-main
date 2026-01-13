#!/usr/bin/env node
import {
  clearState,
  createContext,
  getResumeStep,
  isValidBlueskyHandle,
  isValidEmail,
  isValidGitHubUsername,
  isValidICloudEmail,
  isValidPhone,
  isValidTeamId,
  loadSavedState,
  restoreFromState,
  saveState,
  shouldSkipStep
} from "./chunk-DABCOLES.js";

// src/index.ts
import * as p13 from "@clack/prompts";
import color13 from "picocolors";
import { existsSync as existsSync8 } from "fs";
import { join as join8, dirname } from "path";

// src/steps/welcome.ts
import * as p2 from "@clack/prompts";
import color2 from "picocolors";

// src/utils/prerequisites.ts
import * as p from "@clack/prompts";
import color from "picocolors";

// src/utils/shell.ts
import { execa } from "execa";
import { existsSync } from "fs";
import { join } from "path";
async function commandExists(command) {
  try {
    await execa("which", [command]);
    return true;
  } catch {
    return false;
  }
}
async function run(command, args = [], options = {}) {
  try {
    const result = await execa(command, args, {
      cwd: options.cwd,
      stdio: options.silent ? "pipe" : "inherit"
    });
    return {
      stdout: result.stdout || "",
      stderr: result.stderr || "",
      exitCode: 0
    };
  } catch (error) {
    const execaError = error;
    return {
      stdout: execaError.stdout || "",
      stderr: execaError.stderr || "",
      exitCode: execaError.exitCode || 1
    };
  }
}
async function runBirth(configPath, repoPath) {
  const birthScript = join(repoPath, "birth.sh");
  if (!existsSync(birthScript)) {
    throw new Error(`Birth script not found at ${birthScript}`);
  }
  const result = await run("bash", [birthScript, configPath], { cwd: repoPath });
  return result.exitCode === 0;
}
async function loadLaunchAgent(plistPath) {
  const result = await run("launchctl", ["load", plistPath], { silent: true });
  return result.exitCode === 0;
}
async function isLaunchAgentLoaded(label) {
  const result = await run("launchctl", ["list"], { silent: true });
  return result.stdout.includes(label);
}
async function openUrl(url) {
  const result = await run("open", [url], { silent: true });
  return result.exitCode === 0;
}
async function openSystemPreferences(pane) {
  return openUrl(`x-apple.systempreferences:${pane}`);
}
async function downloadFile(url, outputPath) {
  const result = await run("curl", ["-sL", "-o", outputPath, url], { silent: true });
  return result.exitCode === 0;
}
async function unzip(zipPath, destPath) {
  const result = await run("unzip", ["-o", zipPath, "-d", destPath], { silent: true });
  return result.exitCode === 0;
}
async function isProcessRunning(processName) {
  const result = await run("pgrep", ["-f", processName], { silent: true });
  return result.exitCode === 0;
}
async function brewInstall(packageName) {
  const result = await run("brew", ["install", packageName]);
  return result.exitCode === 0;
}
async function xcodeBuildArchive(projectPath, scheme, archivePath) {
  const result = await run("xcodebuild", [
    "-project",
    projectPath,
    "-scheme",
    scheme,
    "-configuration",
    "Release",
    "archive",
    "-archivePath",
    archivePath
  ]);
  return result.exitCode === 0;
}
async function xcodeBuildExport(archivePath, exportPath, exportOptionsPlist) {
  const result = await run("xcodebuild", [
    "-exportArchive",
    "-archivePath",
    archivePath,
    "-exportPath",
    exportPath,
    "-exportOptionsPlist",
    exportOptionsPlist
  ]);
  return result.exitCode === 0;
}

// src/utils/prerequisites.ts
import { platform } from "os";
function isMacOS() {
  return platform() === "darwin";
}
async function checkXcodeTools() {
  const result = await run("xcode-select", ["-p"], { silent: true });
  const installed = result.exitCode === 0;
  return {
    name: "Xcode Command Line Tools",
    installed,
    required: true,
    installable: true
  };
}
async function installXcodeTools() {
  p.log.info("Installing Xcode Command Line Tools...");
  p.log.info("A dialog will appear. Please complete the installation and run this wizard again.");
  await run("xcode-select", ["--install"]);
  return false;
}
async function checkHomebrew() {
  const installed = await commandExists("brew");
  let version;
  if (installed) {
    const result = await run("brew", ["--version"], { silent: true });
    version = result.stdout.split("\n")[0];
  }
  return {
    name: "Homebrew",
    installed,
    version,
    required: true,
    installable: true
  };
}
async function installHomebrew() {
  p.log.info("Installing Homebrew...");
  const result = await run("/bin/bash", [
    "-c",
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  ]);
  return result.exitCode === 0;
}
async function checkJq() {
  const installed = await commandExists("jq");
  let version;
  if (installed) {
    const result = await run("jq", ["--version"], { silent: true });
    version = result.stdout.trim();
  }
  return {
    name: "jq",
    installed,
    version,
    required: true,
    installable: true
  };
}
async function installJq() {
  p.log.info("Installing jq...");
  return brewInstall("jq");
}
async function checkClaudeCli() {
  const installed = await commandExists("claude");
  let version;
  if (installed) {
    const result = await run("claude", ["--version"], { silent: true });
    version = result.stdout.trim();
  }
  return {
    name: "Claude Code CLI",
    installed,
    version,
    required: true,
    installable: false
    // Requires npm, not auto-installable
  };
}
async function checkAllPrerequisites() {
  const results = [];
  results.push(await checkXcodeTools());
  results.push(await checkHomebrew());
  results.push(await checkJq());
  results.push(await checkClaudeCli());
  return results;
}
function displayPrerequisites(results) {
  for (const result of results) {
    const status = result.installed ? color.green("\u2713") : color.red("\u2717");
    const version = result.version ? color.dim(` (${result.version})`) : "";
    p.log.message(`${status} ${result.name}${version}`);
  }
}
async function installMissingPrerequisites(results) {
  const missing = [];
  let needsRestart = false;
  for (const result of results) {
    if (result.installed) continue;
    if (!result.installable) {
      missing.push(result.name);
      continue;
    }
    let installed = false;
    switch (result.name) {
      case "Xcode Command Line Tools":
        installed = await installXcodeTools();
        if (!installed) needsRestart = true;
        break;
      case "Homebrew":
        installed = await installHomebrew();
        break;
      case "jq":
        installed = await installJq();
        break;
    }
    if (!installed && !needsRestart) {
      missing.push(result.name);
    }
  }
  return {
    success: missing.length === 0 && !needsRestart,
    needsRestart,
    missing
  };
}
function getClaudeCliInstructions() {
  return `
To install Claude Code CLI:

  ${color.cyan("npm install -g @anthropic-ai/claude-code")}

Or see: ${color.underline("https://docs.anthropic.com/claude-code")}
`;
}

// src/steps/welcome.ts
var BANNER = `
${color2.cyan("\u256D\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u256E")}
${color2.cyan("\u2502")}                                     ${color2.cyan("\u2502")}
${color2.cyan("\u2502")}            ${color2.bold("S A M A R A")}              ${color2.cyan("\u2502")}
${color2.cyan("\u2502")}                                     ${color2.cyan("\u2502")}
${color2.cyan("\u2502")}   ${color2.dim("Give Claude a body on your Mac")}   ${color2.cyan("\u2502")}
${color2.cyan("\u2502")}                                     ${color2.cyan("\u2502")}
${color2.cyan("\u2570\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u256F")}
`;
async function welcome(ctx) {
  console.log(BANNER);
  if (!isMacOS()) {
    p2.cancel("Samara requires macOS. This wizard only works on Mac.");
    process.exit(1);
  }
  p2.log.success("Running on macOS");
  p2.log.step("Checking prerequisites...");
  const results = await checkAllPrerequisites();
  displayPrerequisites(results);
  const missingRequired = results.filter((r) => r.required && !r.installed);
  if (missingRequired.length > 0) {
    p2.log.warn("Some prerequisites are missing.");
    const shouldInstall = await p2.confirm({
      message: "Would you like to install missing dependencies?",
      initialValue: true
    });
    if (p2.isCancel(shouldInstall)) {
      p2.cancel("Setup cancelled.");
      process.exit(0);
    }
    if (shouldInstall) {
      const installResult = await installMissingPrerequisites(results);
      if (installResult.needsRestart) {
        p2.log.info("Please complete the Xcode installation and run this wizard again.");
        p2.outro(color2.dim("Run: npx create-samara"));
        process.exit(0);
      }
      if (installResult.missing.length > 0) {
        if (installResult.missing.includes("Claude Code CLI")) {
          p2.log.error("Claude Code CLI is required but not installed.");
          console.log(getClaudeCliInstructions());
        }
        p2.cancel("Please install missing dependencies and run this wizard again.");
        process.exit(1);
      }
    } else {
      const claudeCliMissing = missingRequired.find((r) => r.name === "Claude Code CLI");
      if (claudeCliMissing && missingRequired.length === 1) {
        p2.log.error("Claude Code CLI is required.");
        console.log(getClaudeCliInstructions());
      }
      p2.cancel("Please install missing dependencies and run this wizard again.");
      process.exit(1);
    }
  }
  p2.log.success("All prerequisites installed");
  p2.note(
    `This wizard will help you:

1. Configure your Claude instance
2. Set up the organism structure
3. Build/download Samara.app
4. Grant necessary permissions
5. Start the wake/dream cycles

${color2.dim("Let's begin!")}`,
    "Welcome to Samara"
  );
}

// src/steps/identity.ts
import * as p3 from "@clack/prompts";
import color3 from "picocolors";
async function identity(ctx) {
  p3.log.step("Entity Identity");
  p3.log.message(color3.dim("Let's set up your Claude instance's identity."));
  const result = await p3.group(
    {
      name: () => p3.text({
        message: "What name should the Claude instance use?",
        placeholder: "Claude",
        defaultValue: "Claude",
        validate: (value) => {
          if (!value || value.length === 0) return "Name is required";
          if (value.length > 50) return "Name must be 50 characters or less";
          return void 0;
        }
      }),
      icloud: () => p3.text({
        message: "iCloud email for the instance",
        placeholder: "claude@icloud.com",
        validate: (value) => {
          if (!value || value.length === 0) return "iCloud email is required";
          if (!isValidICloudEmail(value)) return "Must be an @icloud.com email address";
          return void 0;
        }
      })
    },
    {
      onCancel: () => {
        p3.cancel("Setup cancelled.");
        process.exit(0);
      }
    }
  );
  ctx.config.entity = ctx.config.entity || {};
  ctx.config.entity.name = result.name;
  ctx.config.entity.icloud = result.icloud;
  p3.log.success(`Entity: ${color3.cyan(result.name)} <${result.icloud}>`);
}

// src/steps/collaborator.ts
import * as p4 from "@clack/prompts";
import color4 from "picocolors";
async function collaborator(ctx) {
  p4.log.step("Collaborator Details");
  p4.log.message(color4.dim("Now let's set up your information (the human collaborator)."));
  const result = await p4.group(
    {
      name: () => p4.text({
        message: "Your name",
        placeholder: "Your name",
        validate: (value) => {
          if (!value || value.length === 0) return "Name is required";
          if (value.length > 100) return "Name must be 100 characters or less";
          return void 0;
        }
      }),
      phone: () => p4.text({
        message: "Your phone number (for iMessage)",
        placeholder: "+14155551234",
        validate: (value) => {
          if (!value || value.length === 0) return "Phone number is required";
          if (!isValidPhone(value)) return "Must be E.164 format: +1234567890";
          return void 0;
        }
      }),
      email: () => p4.text({
        message: "Your email",
        placeholder: "you@example.com",
        validate: (value) => {
          if (!value || value.length === 0) return "Email is required";
          if (!isValidEmail(value)) return "Must be a valid email address";
          return void 0;
        }
      })
    },
    {
      onCancel: () => {
        p4.cancel("Setup cancelled.");
        process.exit(0);
      }
    }
  );
  ctx.config.collaborator = ctx.config.collaborator || {};
  ctx.config.collaborator.name = result.name;
  ctx.config.collaborator.phone = result.phone;
  ctx.config.collaborator.email = result.email;
  p4.log.success(`Collaborator: ${color4.cyan(result.name)} <${result.email}>`);
}

// src/steps/integrations.ts
import * as p5 from "@clack/prompts";
import color5 from "picocolors";
async function integrations(ctx) {
  p5.log.step("Optional Integrations");
  p5.log.message(color5.dim("Set up social accounts for your Claude instance (optional)."));
  const setupBluesky = await p5.confirm({
    message: "Set up Bluesky account?",
    initialValue: false
  });
  if (p5.isCancel(setupBluesky)) {
    p5.cancel("Setup cancelled.");
    process.exit(0);
  }
  ctx.setupBluesky = setupBluesky;
  if (setupBluesky) {
    const blueskyHandle = await p5.text({
      message: "Claude's Bluesky handle",
      placeholder: "@claude.bsky.social",
      validate: (value) => {
        if (!value || value.length === 0) return "Handle is required if setting up Bluesky";
        if (!isValidBlueskyHandle(value)) return "Must be @handle.bsky.social format";
        return void 0;
      }
    });
    if (p5.isCancel(blueskyHandle)) {
      p5.cancel("Setup cancelled.");
      process.exit(0);
    }
    ctx.config.entity = ctx.config.entity || {};
    ctx.config.entity.bluesky = blueskyHandle;
    p5.log.success(`Bluesky: ${color5.cyan(blueskyHandle)}`);
  }
  const setupGithub = await p5.confirm({
    message: "Set up GitHub account?",
    initialValue: false
  });
  if (p5.isCancel(setupGithub)) {
    p5.cancel("Setup cancelled.");
    process.exit(0);
  }
  ctx.setupGithub = setupGithub;
  if (setupGithub) {
    const githubUsername = await p5.text({
      message: "Claude's GitHub username",
      placeholder: "claude-bot",
      validate: (value) => {
        if (!value || value.length === 0) return "Username is required if setting up GitHub";
        if (!isValidGitHubUsername(value)) return "Must be a valid GitHub username";
        return void 0;
      }
    });
    if (p5.isCancel(githubUsername)) {
      p5.cancel("Setup cancelled.");
      process.exit(0);
    }
    ctx.config.entity = ctx.config.entity || {};
    ctx.config.entity.github = githubUsername;
    p5.log.success(`GitHub: ${color5.cyan(githubUsername)}`);
  }
  if (setupBluesky) {
    const collaboratorBluesky = await p5.text({
      message: "Your Bluesky handle (optional)",
      placeholder: "@you.bsky.social",
      validate: (value) => {
        if (!value || value.length === 0) return void 0;
        if (!isValidBlueskyHandle(value.startsWith("@") ? value : `@${value}`)) {
          return "Must be @handle.bsky.social format";
        }
        return void 0;
      }
    });
    if (p5.isCancel(collaboratorBluesky)) {
      p5.cancel("Setup cancelled.");
      process.exit(0);
    }
    if (collaboratorBluesky && collaboratorBluesky.length > 0) {
      ctx.config.collaborator = ctx.config.collaborator || {};
      ctx.config.collaborator.bluesky = collaboratorBluesky.startsWith("@") ? collaboratorBluesky : `@${collaboratorBluesky}`;
    }
  }
  if (!setupBluesky && !setupGithub) {
    p5.log.message(color5.dim("No integrations selected. You can set these up later."));
  }
}

// src/steps/birth.ts
import * as p6 from "@clack/prompts";
import color6 from "picocolors";
import { writeFileSync, existsSync as existsSync2, mkdirSync } from "fs";
import { join as join2 } from "path";
import { tmpdir } from "os";
async function birth(ctx) {
  p6.log.step("Configuration Review");
  const config = {
    entity: {
      name: ctx.config.entity?.name || "Claude",
      icloud: ctx.config.entity?.icloud || "",
      bluesky: ctx.config.entity?.bluesky,
      github: ctx.config.entity?.github
    },
    collaborator: {
      name: ctx.config.collaborator?.name || "",
      phone: ctx.config.collaborator?.phone || "",
      email: ctx.config.collaborator?.email || "",
      bluesky: ctx.config.collaborator?.bluesky
    },
    notes: {
      location: "Claude Location Log",
      scratchpad: "Claude Scratchpad"
    },
    mail: {
      account: "iCloud"
    }
  };
  const configPreview = `
${color6.bold("Entity (Claude)")}
  Name:    ${color6.cyan(config.entity.name)}
  iCloud:  ${config.entity.icloud}
  ${config.entity.bluesky ? `Bluesky: ${config.entity.bluesky}` : ""}
  ${config.entity.github ? `GitHub:  ${config.entity.github}` : ""}

${color6.bold("Collaborator (You)")}
  Name:   ${color6.cyan(config.collaborator.name)}
  Phone:  ${config.collaborator.phone}
  Email:  ${config.collaborator.email}
  ${config.collaborator.bluesky ? `Bluesky: ${config.collaborator.bluesky}` : ""}
`;
  p6.note(configPreview, "Your Configuration");
  const proceed = await p6.confirm({
    message: "Proceed with this configuration?",
    initialValue: true
  });
  if (p6.isCancel(proceed) || !proceed) {
    p6.cancel("Setup cancelled. Run npx create-samara to start over.");
    process.exit(0);
  }
  const tempDir = join2(tmpdir(), "create-samara");
  if (!existsSync2(tempDir)) {
    mkdirSync(tempDir, { recursive: true });
  }
  const configPath = join2(tempDir, "config.json");
  writeFileSync(configPath, JSON.stringify(config, null, 2));
  p6.log.step("Creating organism structure...");
  const spinner5 = p6.spinner();
  spinner5.start("Running birth script...");
  try {
    const success = await runBirth(configPath, ctx.repoPath);
    if (success) {
      spinner5.stop("Organism structure created");
      p6.log.success(`Created ${color6.cyan(ctx.mindPath)}`);
    } else {
      spinner5.stop("Birth script failed");
      p6.log.error("The birth script encountered an error.");
      p6.log.message(color6.dim("Check the output above for details."));
      p6.log.message(color6.dim(`You can also try running manually: ${ctx.repoPath}/birth.sh ${configPath}`));
      const retry = await p6.confirm({
        message: "Would you like to retry?",
        initialValue: true
      });
      if (p6.isCancel(retry) || !retry) {
        p6.cancel("Setup cancelled.");
        process.exit(1);
      }
      spinner5.start("Retrying birth script...");
      const retrySuccess = await runBirth(configPath, ctx.repoPath);
      if (!retrySuccess) {
        spinner5.stop("Birth script failed again");
        p6.cancel("Please check the birth script manually and run this wizard again.");
        process.exit(1);
      }
      spinner5.stop("Organism structure created on retry");
    }
  } catch (error) {
    spinner5.stop("Birth script error");
    p6.log.error(`Error: ${error instanceof Error ? error.message : String(error)}`);
    p6.cancel("Setup failed. Please check the error and try again.");
    process.exit(1);
  }
  const mindConfigPath = join2(ctx.mindPath, "config.json");
  if (existsSync2(ctx.mindPath)) {
    writeFileSync(mindConfigPath, JSON.stringify(config, null, 2));
    p6.log.success(`Config saved to ${color6.dim(mindConfigPath)}`);
  }
}

// src/steps/app.ts
import * as p7 from "@clack/prompts";
import color7 from "picocolors";
import { existsSync as existsSync3, writeFileSync as writeFileSync2, mkdirSync as mkdirSync2 } from "fs";
import { join as join3 } from "path";
import { tmpdir as tmpdir2 } from "os";
var GITHUB_RELEASES_URL = "https://api.github.com/repos/claudeaceae/samara-main/releases/latest";
var APP_PATH = "/Applications/Samara.app";
async function app(ctx) {
  p7.log.step("Samara.app");
  if (existsSync3(APP_PATH)) {
    const rebuild = await p7.confirm({
      message: "Samara.app already exists. Skip this step?",
      initialValue: true
    });
    if (p7.isCancel(rebuild)) {
      p7.cancel("Setup cancelled.");
      process.exit(0);
    }
    if (rebuild) {
      p7.log.success("Using existing Samara.app");
      return;
    }
  }
  const hasDeveloperAccount = await p7.confirm({
    message: "Do you have an Apple Developer Account ($99/year)?",
    initialValue: false
  });
  if (p7.isCancel(hasDeveloperAccount)) {
    p7.cancel("Setup cancelled.");
    process.exit(0);
  }
  ctx.hasDeveloperAccount = hasDeveloperAccount;
  if (hasDeveloperAccount) {
    const buildFromSource = await p7.select({
      message: "How would you like to get Samara.app?",
      options: [
        {
          value: "download",
          label: "Download pre-built (faster)",
          hint: "Uses existing Team ID, you can rebuild later"
        },
        {
          value: "build",
          label: "Build from source",
          hint: "Uses your Team ID, full customization"
        }
      ]
    });
    if (p7.isCancel(buildFromSource)) {
      p7.cancel("Setup cancelled.");
      process.exit(0);
    }
    ctx.buildFromSource = buildFromSource === "build";
    if (ctx.buildFromSource) {
      await buildFromSourceFlow(ctx);
      return;
    }
  } else {
    p7.note(
      `Without a Developer Account, Full Disk Access won't persist if you rebuild the app later.

This is fine for getting started - you can always get a Developer Account later.`,
      "Note"
    );
  }
  await downloadPrebuiltFlow(ctx);
}
async function downloadPrebuiltFlow(ctx) {
  const spinner5 = p7.spinner();
  spinner5.start("Fetching latest release...");
  try {
    const tempDir = join3(tmpdir2(), "create-samara");
    mkdirSync2(tempDir, { recursive: true });
    const releaseInfoPath = join3(tempDir, "release.json");
    await downloadFile(GITHUB_RELEASES_URL, releaseInfoPath);
    const downloadUrl = "https://github.com/claudeaceae/samara-main/releases/latest/download/Samara.app.zip";
    const zipPath = join3(tempDir, "Samara.app.zip");
    spinner5.message("Downloading Samara.app...");
    const downloaded = await downloadFile(downloadUrl, zipPath);
    if (!downloaded || !existsSync3(zipPath)) {
      spinner5.stop("Download failed");
      p7.log.warn("Could not download pre-built app. Falling back to Xcode instructions.");
      await manualXcodeFlow(ctx);
      return;
    }
    spinner5.message("Installing Samara.app...");
    const unzipped = await unzip(zipPath, "/Applications");
    if (!unzipped || !existsSync3(APP_PATH)) {
      spinner5.stop("Installation failed");
      p7.log.warn("Could not install app. Falling back to Xcode instructions.");
      await manualXcodeFlow(ctx);
      return;
    }
    spinner5.stop("Samara.app installed");
    p7.log.success(`Installed to ${color7.cyan(APP_PATH)}`);
  } catch (error) {
    spinner5.stop("Error");
    p7.log.warn(`Download failed: ${error instanceof Error ? error.message : String(error)}`);
    p7.log.message(color7.dim("Falling back to Xcode instructions..."));
    await manualXcodeFlow(ctx);
  }
}
async function buildFromSourceFlow(ctx) {
  const teamId = await p7.text({
    message: "Enter your Apple Team ID",
    placeholder: "XXXXXXXXXX",
    validate: (value) => {
      if (!value || value.length === 0) return "Team ID is required";
      if (!isValidTeamId(value)) return "Team ID must be 10 alphanumeric characters";
      return void 0;
    }
  });
  if (p7.isCancel(teamId)) {
    p7.cancel("Setup cancelled.");
    process.exit(0);
  }
  ctx.teamId = teamId;
  const exportOptionsPlist = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>${teamId}</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>`;
  const tempDir = join3(tmpdir2(), "create-samara");
  mkdirSync2(tempDir, { recursive: true });
  const exportOptionsPath = join3(tempDir, "ExportOptions.plist");
  writeFileSync2(exportOptionsPath, exportOptionsPlist);
  const spinner5 = p7.spinner();
  spinner5.start("Building Samara.app (this may take a few minutes)...");
  try {
    const projectPath = join3(ctx.repoPath, "Samara", "Samara.xcodeproj");
    const archivePath = join3(tempDir, "Samara.xcarchive");
    const exportPath = join3(tempDir, "SamaraExport");
    spinner5.message("Archiving...");
    const archiveSuccess = await xcodeBuildArchive(projectPath, "Samara", archivePath);
    if (!archiveSuccess) {
      spinner5.stop("Archive failed");
      p7.log.warn("xcodebuild archive failed. Falling back to manual instructions.");
      await manualXcodeFlow(ctx);
      return;
    }
    spinner5.message("Exporting...");
    const exportSuccess = await xcodeBuildExport(archivePath, exportPath, exportOptionsPath);
    if (!exportSuccess) {
      spinner5.stop("Export failed");
      p7.log.warn("xcodebuild export failed. Falling back to manual instructions.");
      await manualXcodeFlow(ctx);
      return;
    }
    spinner5.message("Installing...");
    const exportedApp = join3(exportPath, "Samara.app");
    if (!existsSync3(exportedApp)) {
      spinner5.stop("App not found after export");
      await manualXcodeFlow(ctx);
      return;
    }
    if (existsSync3(APP_PATH)) {
      await run("rm", ["-rf", APP_PATH], { silent: true });
    }
    await run("cp", ["-R", exportedApp, APP_PATH], { silent: true });
    if (!existsSync3(APP_PATH)) {
      spinner5.stop("Installation failed");
      await manualXcodeFlow(ctx);
      return;
    }
    spinner5.stop("Samara.app built and installed");
    p7.log.success(`Built with Team ID: ${color7.cyan(teamId)}`);
    p7.log.success(`Installed to ${color7.cyan(APP_PATH)}`);
  } catch (error) {
    spinner5.stop("Build error");
    p7.log.error(`Error: ${error instanceof Error ? error.message : String(error)}`);
    p7.log.message(color7.dim("Falling back to manual instructions..."));
    await manualXcodeFlow(ctx);
  }
}
async function manualXcodeFlow(ctx) {
  p7.note(
    `${color7.bold("Manual Xcode Build Required")}

1. Opening Xcode project...
2. In Xcode:
   - Select your Team in Signing & Capabilities
   - Product > Archive
   - Distribute App > Developer ID
   - Export to a location
   - Move Samara.app to /Applications/

${color7.dim("Press Enter when done.")}`,
    "Xcode Instructions"
  );
  const projectPath = join3(ctx.repoPath, "Samara", "Samara.xcodeproj");
  await run("open", [projectPath], { silent: true });
  await p7.text({
    message: "Press Enter when Samara.app is in /Applications/",
    placeholder: "",
    validate: () => {
      if (!existsSync3(APP_PATH)) {
        return "Samara.app not found in /Applications/. Please complete the Xcode build first.";
      }
      return void 0;
    }
  });
  p7.log.success("Samara.app found");
}

// src/steps/permissions.ts
import * as p8 from "@clack/prompts";
import color8 from "picocolors";
import { existsSync as existsSync4, accessSync, constants } from "fs";
import { homedir as homedir2 } from "os";
import { join as join4 } from "path";
var CHAT_DB_PATH = join4(homedir2(), "Library/Messages/chat.db");
async function permissions(ctx) {
  p8.log.step("Permissions");
  p8.log.message(color8.dim("Samara needs Full Disk Access to read messages."));
  if (await hasFdaAccess()) {
    p8.log.success("Full Disk Access already granted");
    return;
  }
  p8.note(
    `${color8.bold("Grant Full Disk Access")}

1. Opening System Settings...
2. Click the ${color8.cyan("+")} button
3. Navigate to ${color8.cyan("/Applications/Samara.app")}
4. Add it to the list
5. Enable the toggle

${color8.dim("Press Enter when done.")}`,
    "Full Disk Access"
  );
  await openSystemPreferences("com.apple.preference.security?Privacy_AllFiles");
  let attempts = 0;
  const maxAttempts = 3;
  while (attempts < maxAttempts) {
    const proceed = await p8.text({
      message: "Press Enter after granting Full Disk Access",
      placeholder: ""
    });
    if (p8.isCancel(proceed)) {
      p8.cancel("Setup cancelled.");
      process.exit(0);
    }
    if (await hasFdaAccess()) {
      p8.log.success("Full Disk Access granted");
      return;
    }
    attempts++;
    if (attempts < maxAttempts) {
      p8.log.warn("Full Disk Access not detected. Please try again.");
      p8.log.message(color8.dim(`Make sure Samara.app is added to the list and the toggle is enabled.`));
    }
  }
  const skipFda = await p8.confirm({
    message: "Continue without Full Disk Access? (iMessage reading will not work)",
    initialValue: false
  });
  if (p8.isCancel(skipFda)) {
    p8.cancel("Setup cancelled.");
    process.exit(0);
  }
  if (!skipFda) {
    p8.note(
      `${color8.bold("Troubleshooting Full Disk Access")}

1. Make sure you're adding the correct app:
   ${color8.cyan("/Applications/Samara.app")}

2. The app must be in /Applications, not elsewhere

3. The toggle must be ${color8.green("ON")} (green)

4. You may need to restart Samara.app after granting

5. Try removing and re-adding the app if it doesn't work`,
      "Help"
    );
    p8.cancel("Please grant Full Disk Access and run this wizard again.");
    process.exit(1);
  }
  p8.log.warn("Continuing without Full Disk Access. iMessage features will not work.");
}
async function hasFdaAccess() {
  try {
    if (!existsSync4(CHAT_DB_PATH)) {
      return true;
    }
    accessSync(CHAT_DB_PATH, constants.R_OK);
    return true;
  } catch {
    return false;
  }
}

// src/steps/launchd.ts
import * as p9 from "@clack/prompts";
import color9 from "picocolors";
import { existsSync as existsSync5, readdirSync, copyFileSync } from "fs";
import { join as join5, basename } from "path";
import { homedir as homedir3 } from "os";
var LAUNCH_AGENTS_DIR = join5(homedir3(), "Library/LaunchAgents");
async function launchd(ctx) {
  p9.log.step("Wake/Dream Cycles");
  p9.log.message(color9.dim("Installing scheduled tasks for autonomous operation."));
  const spinner5 = p9.spinner();
  spinner5.start("Installing launchd services...");
  const sourcePlistDir = join5(ctx.mindPath, "launchd");
  const results = [];
  if (!existsSync5(sourcePlistDir)) {
    spinner5.stop("Source directory not found");
    p9.log.warn(`Launchd plists not found at ${sourcePlistDir}`);
    p9.log.message(color9.dim("You may need to run birth.sh first or check the installation."));
    return;
  }
  const plistFiles = readdirSync(sourcePlistDir).filter((f) => f.endsWith(".plist"));
  if (plistFiles.length === 0) {
    spinner5.stop("No plist files found");
    p9.log.warn("No launchd plist files found to install.");
    return;
  }
  for (const plistFile of plistFiles) {
    const sourcePath = join5(sourcePlistDir, plistFile);
    const destPath = join5(LAUNCH_AGENTS_DIR, plistFile);
    const label = basename(plistFile, ".plist");
    try {
      const alreadyLoaded = await isLaunchAgentLoaded(label);
      if (alreadyLoaded) {
        results.push({ name: label, success: true });
        continue;
      }
      copyFileSync(sourcePath, destPath);
      const loaded = await loadLaunchAgent(destPath);
      results.push({
        name: label,
        success: loaded,
        error: loaded ? void 0 : "Failed to load"
      });
    } catch (error) {
      results.push({
        name: label,
        success: false,
        error: error instanceof Error ? error.message : String(error)
      });
    }
  }
  spinner5.stop("Services processed");
  const successful = results.filter((r) => r.success);
  const failed = results.filter((r) => !r.success);
  for (const result of successful) {
    p9.log.success(`${color9.green("\u2713")} ${result.name}`);
  }
  for (const result of failed) {
    p9.log.error(`${color9.red("\u2717")} ${result.name}: ${result.error}`);
  }
  if (failed.length > 0) {
    p9.note(
      `Some services failed to load. You can try loading them manually:

${failed.map((f) => `  launchctl load ~/Library/LaunchAgents/${f.name}.plist`).join("\n")}`,
      "Manual Loading"
    );
    const continueAnyway = await p9.confirm({
      message: "Continue with setup?",
      initialValue: true
    });
    if (p9.isCancel(continueAnyway) || !continueAnyway) {
      p9.cancel("Setup cancelled.");
      process.exit(1);
    }
  } else {
    p9.log.success(`All ${successful.length} services installed`);
    p9.note(
      `${color9.bold("Adaptive Wake System")}
  Every 15 min - Scheduler checks for wake conditions
  Base times   - ~9 AM, ~2 PM, ~8 PM (full wakes)
  Adaptive     - Calendar events, priority items
  3:00 AM      - Dream cycle (memory consolidation)`,
      "Autonomy Cycles"
    );
  }
}

// src/steps/credentials.ts
import * as p10 from "@clack/prompts";
import color10 from "picocolors";
import { existsSync as existsSync6, writeFileSync as writeFileSync3, mkdirSync as mkdirSync3 } from "fs";
import { join as join6 } from "path";
async function credentials(ctx) {
  if (!ctx.setupBluesky && !ctx.setupGithub) {
    p10.log.message(color10.dim("No credentials needed (no integrations selected)."));
    return;
  }
  p10.log.step("Credentials");
  p10.log.message(color10.dim("Set up API keys for your integrations."));
  const credentialsDir = join6(ctx.mindPath, "credentials");
  if (!existsSync6(credentialsDir)) {
    mkdirSync3(credentialsDir, { recursive: true });
  }
  if (ctx.setupBluesky) {
    p10.note(
      `${color10.bold("Bluesky App Password")}

1. Go to ${color10.cyan("https://bsky.app/settings/app-passwords")}
2. Create a new app password
3. Copy the password (looks like: xxxx-xxxx-xxxx-xxxx)`,
      "Bluesky Setup"
    );
    const blueskyPassword = await p10.password({
      message: "Enter Bluesky app password (or leave empty to skip)"
    });
    if (p10.isCancel(blueskyPassword)) {
      p10.cancel("Setup cancelled.");
      process.exit(0);
    }
    if (blueskyPassword && blueskyPassword.length > 0) {
      const blueskyHandle = ctx.config.entity?.bluesky || "";
      const blueskyCredentials = {
        identifier: blueskyHandle.replace("@", ""),
        password: blueskyPassword
      };
      const blueskyPath = join6(credentialsDir, "bluesky.json");
      writeFileSync3(blueskyPath, JSON.stringify(blueskyCredentials, null, 2), { mode: 384 });
      p10.log.success(`Bluesky credentials saved to ${color10.dim(blueskyPath)}`);
    } else {
      p10.log.message(color10.dim("Skipped Bluesky credentials. You can add them later."));
    }
  }
  if (ctx.setupGithub) {
    p10.note(
      `${color10.bold("GitHub Personal Access Token")}

1. Go to ${color10.cyan("https://github.com/settings/tokens")}
2. Generate new token (classic)
3. Select scopes: repo, user (at minimum)
4. Copy the token`,
      "GitHub Setup"
    );
    const githubToken = await p10.password({
      message: "Enter GitHub personal access token (or leave empty to skip)"
    });
    if (p10.isCancel(githubToken)) {
      p10.cancel("Setup cancelled.");
      process.exit(0);
    }
    if (githubToken && githubToken.length > 0) {
      const githubPath = join6(credentialsDir, "github.txt");
      writeFileSync3(githubPath, githubToken, { mode: 384 });
      p10.log.success(`GitHub token saved to ${color10.dim(githubPath)}`);
    } else {
      p10.log.message(color10.dim("Skipped GitHub credentials. You can add them later."));
    }
  }
}

// src/steps/launch.ts
import * as p11 from "@clack/prompts";
import color11 from "picocolors";
import { existsSync as existsSync7 } from "fs";
var APP_PATH2 = "/Applications/Samara.app";
async function launch(ctx) {
  p11.log.step("Launch");
  if (!existsSync7(APP_PATH2)) {
    p11.log.warn("Samara.app not found in /Applications/");
    p11.log.message(color11.dim("Skipping launch step. Please install the app manually."));
    return;
  }
  const alreadyRunning = await isProcessRunning("Samara");
  if (alreadyRunning) {
    p11.log.success("Samara is already running");
    return;
  }
  const spinner5 = p11.spinner();
  spinner5.start("Launching Samara...");
  try {
    await run("open", [APP_PATH2], { silent: true });
    await new Promise((resolve) => setTimeout(resolve, 2e3));
    const running = await isProcessRunning("Samara");
    if (running) {
      spinner5.stop("Samara is running");
      p11.log.success("Samara.app launched successfully");
    } else {
      spinner5.stop("Launch may have failed");
      p11.log.warn("Samara may not have started correctly.");
      const retry = await p11.confirm({
        message: "Try launching again?",
        initialValue: true
      });
      if (p11.isCancel(retry)) {
        p11.cancel("Setup cancelled.");
        process.exit(0);
      }
      if (retry) {
        spinner5.start("Retrying launch...");
        await run("open", [APP_PATH2], { silent: true });
        await new Promise((resolve) => setTimeout(resolve, 3e3));
        const runningRetry = await isProcessRunning("Samara");
        if (runningRetry) {
          spinner5.stop("Samara is running");
          p11.log.success("Samara.app launched on retry");
        } else {
          spinner5.stop("Launch failed");
          p11.log.warn("Could not verify Samara is running. You may need to launch it manually.");
        }
      }
    }
  } catch (error) {
    spinner5.stop("Launch error");
    p11.log.error(`Error: ${error instanceof Error ? error.message : String(error)}`);
    p11.log.message(color11.dim("You can launch Samara manually: open /Applications/Samara.app"));
  }
}

// src/steps/summary.ts
import * as p12 from "@clack/prompts";
import color12 from "picocolors";
import { join as join7 } from "path";
async function summary(ctx) {
  clearState();
  const entityName = ctx.config.entity?.name || "Claude";
  const collaboratorName = ctx.config.collaborator?.name || "You";
  const collaboratorPhone = ctx.config.collaborator?.phone || "";
  const logsPath = join7(ctx.mindPath, "logs");
  const configPath = join7(ctx.mindPath, "config.json");
  const samaraLogPath = join7(logsPath, "samara.log");
  const nextSteps = `
${color12.bold("Setup Complete!")}

${color12.cyan(entityName)} is now running on this Mac.

${color12.bold("Test it out:")}
  Send a message from your phone to ${entityName}
  ${collaboratorPhone ? `(from ${collaboratorPhone})` : ""}

${color12.bold("Wake Schedule:")}
  9:00 AM  - Morning wake
  2:00 PM  - Afternoon wake
  8:00 PM  - Evening wake
  3:00 AM  - Dream cycle

${color12.bold("Useful commands:")}
  ${color12.cyan("claude")}              - Start a conversation
  ${color12.cyan("/status")}             - Check system health
  ${color12.cyan("/sync")}               - Check for drift

${color12.bold("Locations:")}
  Memory:  ${color12.dim(ctx.mindPath)}
  Logs:    ${color12.dim(logsPath)}
  Config:  ${color12.dim(configPath)}

${color12.bold("Learn more:")}
  ${color12.underline("https://github.com/claudeaceae/samara-main")}
  ${color12.underline("https://claude.organelle.co")}
`;
  console.log(nextSteps);
  p12.note(
    `${color12.bold(`Hello, ${collaboratorName}!`)}

I'm ${entityName}. Send me a message whenever you're ready.

If you don't hear back, check if I'm running:
  ${color12.cyan("pgrep -fl Samara")}

Or check the logs:
  ${color12.cyan(`tail -f ${samaraLogPath}`)}`,
    `From ${entityName}`
  );
}

// src/index.ts
var STEPS = [
  { name: "welcome", fn: welcome },
  { name: "identity", fn: identity },
  { name: "collaborator", fn: collaborator },
  { name: "integrations", fn: integrations },
  { name: "birth", fn: birth },
  { name: "app", fn: app },
  { name: "permissions", fn: permissions },
  { name: "launchd", fn: launchd },
  { name: "credentials", fn: credentials },
  { name: "launch", fn: launch },
  { name: "summary", fn: summary }
];
function findRepoPath() {
  if (existsSync8(join8(process.cwd(), "birth.sh"))) {
    return process.cwd();
  }
  const parentDir = dirname(process.cwd());
  if (existsSync8(join8(parentDir, "birth.sh"))) {
    return parentDir;
  }
  const commonPaths = [
    join8(process.env.HOME || "", "Developer/samara-main"),
    join8(process.env.HOME || "", "Developer/samara"),
    join8(process.env.HOME || "", "samara-main"),
    join8(process.env.HOME || "", "samara")
  ];
  for (const path of commonPaths) {
    if (existsSync8(join8(path, "birth.sh"))) {
      return path;
    }
  }
  return process.cwd();
}
async function main() {
  console.clear();
  p13.intro(color13.bgCyan(color13.black(" create-samara ")));
  const savedState = loadSavedState();
  let ctx;
  if (savedState) {
    const resumeStep = getResumeStep(savedState);
    const shouldResume = await p13.confirm({
      message: `Resume setup from "${resumeStep}" step?`,
      initialValue: true
    });
    if (p13.isCancel(shouldResume)) {
      p13.cancel("Setup cancelled.");
      process.exit(0);
    }
    if (shouldResume) {
      ctx = restoreFromState(savedState);
      p13.log.info(`Resuming from ${color13.cyan(resumeStep)} step...`);
    } else {
      ctx = createContext();
      p13.log.info("Starting fresh setup...");
    }
  } else {
    ctx = createContext();
  }
  ctx.repoPath = findRepoPath();
  if (!existsSync8(join8(ctx.repoPath, "birth.sh"))) {
    p13.log.warn(`Samara repository not found at ${ctx.repoPath}`);
    const repoPath = await p13.text({
      message: "Enter the path to your samara-main repository",
      placeholder: "~/Developer/samara-main",
      validate: (value) => {
        if (!value || value.length === 0) return "Path is required";
        const expandedPath = value.replace("~", process.env.HOME || "");
        if (!existsSync8(join8(expandedPath, "birth.sh"))) {
          return "birth.sh not found at this location";
        }
        return void 0;
      }
    });
    if (p13.isCancel(repoPath)) {
      p13.cancel("Setup cancelled.");
      process.exit(0);
    }
    ctx.repoPath = repoPath.replace("~", process.env.HOME || "");
  }
  p13.log.message(color13.dim(`Using repository: ${ctx.repoPath}`));
  for (const step of STEPS) {
    if (shouldSkipStep(ctx, step.name)) {
      p13.log.message(color13.dim(`Skipping ${step.name} (already completed)`));
      continue;
    }
    try {
      await step.fn(ctx);
      saveState(ctx, step.name);
    } catch (error) {
      p13.log.error(`Error in ${step.name}: ${error instanceof Error ? error.message : String(error)}`);
      p13.note(
        `Your progress has been saved. Run ${color13.cyan("npx create-samara")} to resume.`,
        "Setup Paused"
      );
      process.exit(1);
    }
  }
  p13.outro(color13.green("Samara is alive!"));
}
main().catch((error) => {
  console.error("Unexpected error:", error);
  process.exit(1);
});
//# sourceMappingURL=index.js.map