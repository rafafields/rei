import { spawnSync } from 'node:child_process';

export function onPath(cmd) {
  const r = spawnSync('where.exe', [cmd], { encoding: 'utf8' });
  return r.status === 0 ? r.stdout.split(/\r?\n/)[0].trim() : null;
}

export function findWindowsTerminal() {
  return onPath('wt') || null;
}

/** Each requirement: how to detect it and what to tell the user when missing. */
export function checkRequirements() {
  return [
    { name: 'Windows', ok: process.platform === 'win32', help: 'Rei only works on Windows 10/11.' },
    { name: 'Windows Terminal', ok: !!findWindowsTerminal(), help: 'winget install Microsoft.WindowsTerminal' },
    { name: 'PowerShell 5.1', ok: !!onPath('powershell'), help: 'Included with Windows.' },
    { name: 'Claude Code', ok: !!onPath('claude'), help: 'npm install -g @anthropic-ai/claude-code' },
    { name: 'git', ok: !!onPath('git'), help: 'winget install Git.Git' },
  ];
}

export function powershell(args, opts = {}) {
  return spawnSync('powershell', ['-NoProfile', '-ExecutionPolicy', 'Bypass', ...args],
    { encoding: 'utf8', ...opts });
}

export function profilePath() {
  const r = powershell(['-Command', '$PROFILE']);
  return r.status === 0 ? r.stdout.trim() : null;
}
