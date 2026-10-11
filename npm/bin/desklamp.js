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
const BASE = process.env.DESKLAMP_RELEASE_BASE || `${REPO}/releases/latest/download`;
const CUSTOM_DIR = process.env.DESKLAMP_INSTALL_DIR;
const INSTALL_DIR = CUSTOM_DIR || '/Applications';
const NO_RELEASE = `No Desklamp release yet. See ${REPO}`;

function fail(msg) {
  console.error(msg);
  process.exit(1);
}

function get(url, redirects = 0) {
  return new Promise((resolve, reject) => {
    const lib = url.startsWith('http:') ? http : https;
    lib.get(url, { headers: { 'User-Agent': 'desklamp-installer' } }, (res) => {
      if ([301, 302, 303, 307, 308].includes(res.statusCode) && res.headers.location) {
        res.resume();
        if (redirects > 10) return reject(new Error('Too many redirects'));
        return resolve(get(new URL(res.headers.location, url).href, redirects + 1));
      }
      if (res.statusCode === 404) { res.resume(); return resolve(null); }
      if (res.statusCode !== 200) { res.resume(); return reject(new Error(`HTTP ${res.statusCode} from ${url}`)); }
      const chunks = [];
      res.on('data', (c) => chunks.push(c));
      res.on('end', () => resolve(Buffer.concat(chunks)));
    }).on('error', reject);
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

  console.log('Downloading Desklamp.zip...');
  const zip = await get(`${BASE}/Desklamp.zip`);
  if (!zip) fail(NO_RELEASE);
  console.log('Downloading SHA256SUMS...');
  const sums = await get(`${BASE}/SHA256SUMS`);
  if (!sums) fail(NO_RELEASE);

  console.log('Verifying checksum...');
  const line = sums.toString().split('\n').find((l) => l.trim().split(/\s+/)[1] === 'Desklamp.zip');
  if (!line) fail('SHA256SUMS has no entry for Desklamp.zip; aborting.');
  const expected = line.trim().split(/\s+/)[0].toLowerCase();
  const actual = crypto.createHash('sha256').update(zip).digest('hex');
  if (actual !== expected) fail(`Checksum mismatch (expected ${expected}, got ${actual}); aborting.`);

  const work = fs.mkdtempSync(path.join(os.tmpdir(), 'desklamp-'));
  const NEW = path.join(INSTALL_DIR, '.Desklamp.app.new');
  const OLD = path.join(INSTALL_DIR, '.Desklamp.app.old');
  const DEST = path.join(INSTALL_DIR, 'Desklamp.app');
  const cleanup = () => {
    fs.rmSync(work, { recursive: true, force: true });
    fs.rmSync(NEW, { recursive: true, force: true });
  };
  try {
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
    try {
      fs.renameSync(NEW, DEST);
    } catch (e) {
      if (fs.existsSync(OLD)) fs.renameSync(OLD, DEST);
      fail('Install failed; previous version restored.');
    }
    fs.rmSync(OLD, { recursive: true, force: true });
  } finally {
    cleanup();
  }

  if (process.env.DESKLAMP_NO_OPEN) {
    console.log('Installed. Skipping launch (DESKLAMP_NO_OPEN set).');
  } else {
    console.log('Opening Desklamp...');
    execFileSync('open', [DEST]);
  }
}

main().catch((e) => fail(`Install failed: ${e.message}`));
