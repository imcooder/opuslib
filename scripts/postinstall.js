#!/usr/bin/env node

const { execSync } = require('child_process');
const path = require('path');
const fs = require('fs');

const ROOT = path.resolve(__dirname, '..');
const ARCHIVE = path.join(ROOT, 'large_files_store', 'opus-1.6.tar.gz');
const THIRDPARTY = path.join(ROOT, 'thirdparty');
const TARGET = path.join(THIRDPARTY, 'opus-1.6');

// Skip if opus-1.6 directory already exists (e.g. local development with source checked in)
if (fs.existsSync(TARGET)) {
  console.log('[opuslib] thirdparty/opus-1.6 already exists, skipping extraction.');
  process.exit(0);
}

if (!fs.existsSync(ARCHIVE)) {
  console.error(`[opuslib] Archive not found: ${ARCHIVE}`);
  console.error('[opuslib] If you cloned via git, make sure git-lfs is installed and run: git lfs pull');
  process.exit(1);
}

// Ensure thirdparty directory exists
if (!fs.existsSync(THIRDPARTY)) {
  fs.mkdirSync(THIRDPARTY, { recursive: true });
}

console.log('[opuslib] Extracting opus-1.6 source to thirdparty/...');
try {
  execSync(`tar xzf "${ARCHIVE}" -C "${THIRDPARTY}"`, { stdio: 'inherit' });
  console.log('[opuslib] thirdparty/opus-1.6 extracted successfully.');
} catch (err) {
  console.error('[opuslib] Failed to extract opus-1.6:', err.message);
  process.exit(1);
}
