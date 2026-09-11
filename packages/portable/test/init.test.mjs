import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, existsSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
const cli = fileURLToPath(new URL('../bin/init.mjs', import.meta.url));
const run = (...args) => spawnSync(process.execPath, [cli, ...args], { encoding: 'utf8' });
test('creates a usable workspace at a path with spaces', () => {
  const root = mkdtempSync(join(tmpdir(), 'agentos-test-'));
  try {
    const dest = join(root, 'my workspace');
    assert.equal(run(dest).status, 0);
    for (const file of ['AGENTS.md', 'TEAM.md', 'PROTOCOL.md', 'CLAUDE.md', 'GEMINI.md', 'templates/task.md', 'templates/acceptance.md', 'templates/review.md', 'templates/delivery.md', 'tasks/README.md', 'knowledge/README.md', 'examples/hello/task.md']) {
      assert.ok(existsSync(join(dest, file)), file);
    }
    assert.match(readFileSync(join(dest, 'AGENTS.md'), 'utf8'), /TEAM.md/);
    writeFileSync(join(dest, 'README.md'), 'preserve me');
    assert.notEqual(run(dest).status, 0);
    assert.equal(readFileSync(join(dest, 'README.md'), 'utf8'), 'preserve me');
    const empty = join(root, 'existing-empty');
    mkdirSync(empty);
    assert.notEqual(run(empty).status, 0);
    const file = join(root, 'existing-file');
    writeFileSync(file, 'original');
    assert.notEqual(run(file).status, 0);
    assert.equal(readFileSync(file, 'utf8'), 'original');
    assert.notEqual(run(join(root, 'missing-parent', 'child')).status, 0);
  } finally { rmSync(root, { recursive: true, force: true }); }
});
test('requires exactly one destination and offers help', () => {
  assert.notEqual(run().status, 0);
  assert.notEqual(run('a', 'b').status, 0);
  assert.equal(run('--help').status, 0);
});
