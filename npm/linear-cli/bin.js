#!/usr/bin/env node
const { spawnSync } = require("child_process");
const { join, dirname } = require("path");
const { existsSync } = require("fs");

const PLATFORMS = {
  "darwin-arm64": "@0xbigboss/linear-cli-darwin-arm64",
  "darwin-x64": "@0xbigboss/linear-cli-darwin-x64",
  "linux-x64": "@0xbigboss/linear-cli-linux-x64",
  "linux-arm64": "@0xbigboss/linear-cli-linux-arm64",
};

const key = `${process.platform}-${process.arch}`;
const pkg = PLATFORMS[key];

if (!pkg) {
  console.error(`Unsupported platform: ${key}`);
  process.exit(1);
}

let bin;

// Try installed npm package first
try {
  const pkgPath = require.resolve(`${pkg}/package.json`);
  bin = join(dirname(pkgPath), "linear");
} catch {
  // Fall back to local development path
  const localPath = join(__dirname, "..", `linear-cli-${key}`, "linear");
  if (existsSync(localPath)) {
    bin = localPath;
  }
}

if (!bin || !existsSync(bin)) {
  console.error(`Binary not found for ${key}. Run: zig build npm`);
  process.exit(1);
}

const result = spawnSync(bin, process.argv.slice(2), { stdio: "inherit" });
process.exit(result.status ?? 1);
