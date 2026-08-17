#!/usr/bin/env node

import { spawnSync } from 'node:child_process';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { homedir } from 'node:os';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const binary = resolve(homedir(), 'Applications/Language Relay.app/Contents/MacOS/LanguageRelay');
const [command, ...args] = process.argv.slice(2);

const run = (executable, argv, cwd = process.cwd()) => {
  const result = spawnSync(executable, argv, { cwd, stdio: 'inherit' });
  if (result.error) {
    console.error(`language-relay: ${result.error.message}`);
    process.exit(1);
  }
  process.exit(result.status ?? 1);
};

if (command === 'install') run('/usr/bin/make', ['install'], root);
if (command === 'setup') run(binary, ['--enable-pair']);
if (command === 'doctor') run(binary, ['--doctor-json']);
if (command === 'status') run(binary, ['--status-json']);
if (command === 'capabilities') run(binary, ['--capabilities-json']);
if (command === 'convert') {
  if (args.length === 0) {
    console.error('usage: language-relay convert <text> [--capitalization preserve|sentence|uppercase|lowercase]');
    process.exit(2);
  }
  run(binary, ['--convert-json', ...args]);
}
if (command === 'switch') run(binary, ['--switch']);

console.log(`language relay 2.3

commands:
  install                    build and install in ~/Applications
  setup                      enable the configured layout pair as macOS input sources
  convert <text>             convert text and return JSON
  switch                     switch between the configured pair
  status                     current input source as JSON
  doctor                     local health as JSON
  capabilities               stable capability schema as JSON`);
