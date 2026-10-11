#!/usr/bin/env node
// Downloads the latest Desklamp release, verifies its checksum, and installs it.
'use strict';
const https = require('https');
const http = require('http');
const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync, spawnSync } = require('child_process');

const REPO = 'https://github.com/seansmithworks/desklamp';
const CUSTOM_DIR = process.env.DESKLAMP_INSTALL_DIR;
// Test-only: the release base override is honored only alongside DESKLAMP_INSTALL_DIR.
// A real /Applications install always downloads from GitHub over https.
const OVERRIDE = Boolean(CUSTOM_DIR && process.env.DESKLAMP_RELEASE_BASE);
const BASE = OVERRIDE ? process.env.DESKLAMP_RELEASE_BASE : `${REPO}/releases/latest/download`;
const TIMEOUT_MS = 30000;
const INSTALL_DIR = CUSTOM_DIR || '/Applications';
const NO_RELEASE = `No Desklamp release yet. See ${REPO}`;

// Failures are thrown, never process.exit'd, so main()'s finally always runs cleanup.
class InstallError extends Error {}
function fail(msg) {
  throw new InstallError(msg);
}

function get(url, redirects = 0, strict = !OVERRIDE) {
  return new Promise((resolve, reject) => {
    const lib = url.startsWith('http:') ? http : https;
    const req = lib.get(url, { headers: { 'User-Agent': 'desklamp-installer' } }, (res) => {
      if ([301, 302, 303, 307, 308].includes(res.statusCode) && res.headers.location) {
        res.resume();
        if (redirects > 10) return reject(new InstallError('Too many redirects'));
        const next = new URL(res.headers.location, url);
        if (strict && next.protocol !== 'https:') {
          return reject(new InstallError(`Refusing redirect to non-https URL (${next.href}); aborting.`));
        }
        return resolve(get(next.href, redirects + 1, strict));
      }
      if (res.statusCode === 404) { res.resume(); return resolve(null); }
      if (res.statusCode !== 200) { res.resume(); return reject(new Error(`HTTP ${res.statusCode} from ${url}`)); }
      const chunks = [];
      res.on('data', (c) => chunks.push(c));
      res.on('end', () => resolve(Buffer.concat(chunks)));
    });
    req.setTimeout(TIMEOUT_MS, () => req.destroy(new InstallError(`Timed out after ${TIMEOUT_MS / 1000}s fetching ${url}; aborting.`)));
    req.on('error', reject);
  });
}

function pgrepRunning() {
  return spawnSync('pgrep', ['-x', 'Desklamp']).status === 0;
}

function sleep(ms) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}

function quitApp() {
  spawnSync('pkill', ['-x', 'Desklamp']);
  for (let i = 0; i < 20 && pgrepRunning(); i++) sleep(250);
  if (pgrepRunning()) fail('Desklamp did not quit; aborting.');
}

async function main() {
  if (process.platform !== 'darwin') fail('Desklamp is for macOS only.');

  const NEW = path.join(INSTALL_DIR, '.Desklamp.app.new');
  const OLD = path.join(INSTALL_DIR, '.Desklamp.app.old');
  const DEST = path.join(INSTALL_DIR, 'Desklamp.app');
  let work = null;
  try {
    console.log('Downloading Desklamp.zip...');
    const zip = await get(`${BASE}/Desklamp.zip`);
    if (!zip) fail(NO_RELEASE);
    console.log('Downloading SHA256SUMS...');
    const sums = await get(`${BASE}/SHA256SUMS`);
    if (!sums) fail('Release is missing SHA256SUMS; aborting.');

    console.log('Verifying checksum...');
    const line = sums.toString().split('\n').find((l) => l.trim().split(/\s+/)[1] === 'Desklamp.zip');
    if (!line) fail('SHA256SUMS has no entry for Desklamp.zip; aborting.');
    const expected = line.trim().split(/\s+/)[0].toLowerCase();
    const actual = crypto.createHash('sha256').update(zip).digest('hex');
    if (actual !== expected) fail(`Checksum mismatch (expected ${expected}, got ${actual}); aborting.`);

    work = fs.mkdtempSync(path.join(os.tmpdir(), 'desklamp-'));
    fs.writeFileSync(path.join(work, 'Desklamp.zip'), zip);
    console.log('Unpacking...');
    execFileSync('ditto', ['-x', '-k', path.join(work, 'Desklamp.zip'), work]);
    const unpacked = path.join(work, 'Desklamp.app');
    if (!fs.existsSync(unpacked)) fail('Desklamp.app not found in the download; aborting.');

    // Only the real /Applications install quits a running app.
    if (!CUSTOM_DIR) {
      console.log('Quitting Desklamp if it is running...');
      quitApp();
    }

    console.log(`Installing to ${DEST}...`);
    fs.rmSync(NEW, { recursive: true, force: true });
    fs.rmSync(OLD, { recursive: true, force: true });
    execFileSync('ditto', [unpacked, NEW]);
    if (fs.existsSync(DEST)) fs.renameSync(DEST, OLD);
    // Test-only hook (requires DESKLAMP_INSTALL_DIR): fail mid-swap to exercise rollback.
    if (CUSTOM_DIR && process.env.DESKLAMP_TEST_FAIL_MIDSWAP) throw new Error('simulated mid-swap failure');
    fs.renameSync(NEW, DEST);
    fs.rmSync(OLD, { recursive: true, force: true });
  } finally {
    // Runs on every path: temp download, staged .new, and a rollback if the swap died midway.
    if (work) fs.rmSync(work, { recursive: true, force: true });
    fs.rmSync(NEW, { recursive: true, force: true });
    if (fs.existsSync(OLD)) {
      if (fs.existsSync(DEST)) fs.rmSync(OLD, { recursive: true, force: true });
      else {
        fs.renameSync(OLD, DEST);
        console.error('Install failed; previous version restored.');
      }
    }
  }

  if (process.env.DESKLAMP_NO_OPEN) {
    console.log('Installed. Skipping launch (DESKLAMP_NO_OPEN set).');
  } else {
    console.log('Opening Desklamp...');
    execFileSync('open', [DEST]);
  }
}

if (require.main === module) {
  main().catch((e) => {
    console.error(e instanceof InstallError ? e.message : `Install failed: ${e.message}`);
    process.exitCode = 1;
  });
}

module.exports = { get };
