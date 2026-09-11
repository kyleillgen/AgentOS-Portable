#!/usr/bin/env node
import { cpSync, mkdirSync, rmSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const args = process.argv.slice(2);
if (args.length !== 1 || args[0].startsWith('-')) {
  console.log('Usage: node bin/init.mjs <new-workspace-directory>');
  process.exit(args.includes('--help') ? 0 : 1);
}
const destination = resolve(args[0]);
let created = false;
try {
  // Exclusive creation: never merge into or overwrite an existing workspace.
  mkdirSync(destination);
  created = true;
  cpSync(resolve(dirname(fileURLToPath(import.meta.url)), '../template'), destination,
    { recursive: true, force: false, errorOnExist: true });
  console.log(`Created ${destination}\nStart with README.md and configure TEAM.md.`);
} catch (error) {
  if (created) rmSync(destination, { recursive: true, force: true });
  console.error(`Workspace creation failed: ${error.message}`);
  process.exitCode = 1;
}
