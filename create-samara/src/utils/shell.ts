import { execa, type ExecaError } from 'execa';
import { existsSync } from 'fs';
import { join } from 'path';

/**
 * Check if a command exists in PATH
 */
export async function commandExists(command: string): Promise<boolean> {
  try {
    await execa('which', [command]);
    return true;
  } catch {
    return false;
  }
}

/**
 * Run a shell command and return output
 */
export async function run(
  command: string,
  args: string[] = [],
  options: { cwd?: string; silent?: boolean } = {}
): Promise<{ stdout: string; stderr: string; exitCode: number }> {
  try {
    const result = await execa(command, args, {
      cwd: options.cwd,
      stdio: options.silent ? 'pipe' : 'inherit',
    });
    return {
      stdout: result.stdout || '',
      stderr: result.stderr || '',
      exitCode: 0,
    };
  } catch (error) {
    const execaError = error as ExecaError;
    return {
      stdout: execaError.stdout || '',
      stderr: execaError.stderr || '',
      exitCode: execaError.exitCode || 1,
    };
  }
}

/**
 * Run the birth script
 */
export async function runBirth(configPath: string, repoPath: string): Promise<boolean> {
  const birthScript = join(repoPath, 'birth.sh');

  if (!existsSync(birthScript)) {
    throw new Error(`Birth script not found at ${birthScript}`);
  }

  const result = await run('bash', [birthScript, configPath], { cwd: repoPath });
  return result.exitCode === 0;
}

/**
 * Load a launchd agent
 */
export async function loadLaunchAgent(plistPath: string): Promise<boolean> {
  const result = await run('launchctl', ['load', plistPath], { silent: true });
  return result.exitCode === 0;
}

/**
 * Unload a launchd agent (if needed for reload)
 */
export async function unloadLaunchAgent(plistPath: string): Promise<boolean> {
  const result = await run('launchctl', ['unload', plistPath], { silent: true });
  return result.exitCode === 0;
}

/**
 * Check if a launchd agent is loaded
 */
export async function isLaunchAgentLoaded(label: string): Promise<boolean> {
  const result = await run('launchctl', ['list'], { silent: true });
  return result.stdout.includes(label);
}

/**
 * Open a URL or file with the default application
 */
export async function openUrl(url: string): Promise<boolean> {
  const result = await run('open', [url], { silent: true });
  return result.exitCode === 0;
}

/**
 * Open System Preferences to a specific pane
 */
export async function openSystemPreferences(pane: string): Promise<boolean> {
  return openUrl(`x-apple.systempreferences:${pane}`);
}

/**
 * Download a file using curl
 */
export async function downloadFile(url: string, outputPath: string): Promise<boolean> {
  const result = await run('curl', ['-sL', '-o', outputPath, url], { silent: true });
  return result.exitCode === 0;
}

/**
 * Unzip a file
 */
export async function unzip(zipPath: string, destPath: string): Promise<boolean> {
  const result = await run('unzip', ['-o', zipPath, '-d', destPath], { silent: true });
  return result.exitCode === 0;
}

/**
 * Check if a process is running
 */
export async function isProcessRunning(processName: string): Promise<boolean> {
  const result = await run('pgrep', ['-f', processName], { silent: true });
  return result.exitCode === 0;
}

/**
 * Install Homebrew package
 */
export async function brewInstall(packageName: string): Promise<boolean> {
  const result = await run('brew', ['install', packageName]);
  return result.exitCode === 0;
}

/**
 * Run xcodebuild archive
 */
export async function xcodeBuildArchive(
  projectPath: string,
  scheme: string,
  archivePath: string
): Promise<boolean> {
  const result = await run('xcodebuild', [
    '-project', projectPath,
    '-scheme', scheme,
    '-configuration', 'Release',
    'archive',
    '-archivePath', archivePath,
  ]);
  return result.exitCode === 0;
}

/**
 * Run xcodebuild export archive
 */
export async function xcodeBuildExport(
  archivePath: string,
  exportPath: string,
  exportOptionsPlist: string
): Promise<boolean> {
  const result = await run('xcodebuild', [
    '-exportArchive',
    '-archivePath', archivePath,
    '-exportPath', exportPath,
    '-exportOptionsPlist', exportOptionsPlist,
  ]);
  return result.exitCode === 0;
}
