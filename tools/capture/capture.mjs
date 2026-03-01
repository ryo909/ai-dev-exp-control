#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

function getArg(name, fallback = null) {
  const idx = process.argv.indexOf(`--${name}`);
  if (idx === -1) return fallback;
  return process.argv[idx + 1] ?? fallback;
}

const url = getArg("url");
const outDir = getArg("out");
const duration = Number(getArg("duration", "8"));
const width = Number(getArg("width", "720"));
const height = Number(getArg("height", "1280"));

if (!url || !outDir) {
  console.error(JSON.stringify({ ok: false, error: "Missing --url or --out" }));
  process.exit(2);
}

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const runtimeDir = path.join(scriptDir, ".runtime");
const runtimeDebDir = path.join(runtimeDir, "debs");
const runtimeRootDir = path.join(runtimeDir, "root");
const runtimeLibDir = path.join(runtimeRootDir, "usr", "lib", "x86_64-linux-gnu");

function parseMissingLibs(text) {
  return [...text.matchAll(/^\s*(\S+)\s+=>\s+not found$/gm)].map((m) => m[1]);
}

function runOrThrow(cmd, args, opts = {}) {
  const result = spawnSync(cmd, args, { encoding: "utf8", ...opts });
  if (result.status !== 0) {
    const detail = (result.stderr || result.stdout || "").trim();
    throw new Error(detail || `${cmd} ${args.join(" ")} failed`);
  }
  return result;
}

function tryRun(cmd, args, opts = {}) {
  return spawnSync(cmd, args, { encoding: "utf8", ...opts });
}

function ensureLocalRuntimeLibsIfNeeded() {
  if (process.platform !== "linux") return;

  const needed = new Set(["libnspr4.so", "libnss3.so", "libnssutil3.so", "libasound.so.2"]);
  const browserBin = chromium.executablePath();
  const initialLdd = tryRun("ldd", [browserBin]);
  const initialMissing = parseMissingLibs(`${initialLdd.stdout || ""}\n${initialLdd.stderr || ""}`)
    .filter((name) => needed.has(name));

  if (initialMissing.length === 0) return;

  const canApt = tryRun("bash", ["-lc", "command -v apt-get >/dev/null && command -v dpkg-deb >/dev/null"]);
  if (canApt.status !== 0) {
    throw new Error(`Missing shared libraries: ${initialMissing.join(", ")}`);
  }

  fs.mkdirSync(runtimeDebDir, { recursive: true });
  fs.mkdirSync(runtimeRootDir, { recursive: true });

  const downloadIfMissing = (pkgNames) => {
    for (const pkgName of pkgNames) {
      const hasDeb = fs.readdirSync(runtimeDebDir).some(
        (f) => f.startsWith(`${pkgName}_`) && f.endsWith(".deb"),
      );
      if (hasDeb) return;

      const attempt = tryRun("apt-get", ["download", pkgName], { cwd: runtimeDebDir });
      if (attempt.status === 0) return;
    }
    throw new Error(`Failed to download package candidates: ${pkgNames.join(", ")}`);
  };

  downloadIfMissing(["libnspr4"]);
  downloadIfMissing(["libnss3"]);
  downloadIfMissing(["libasound2t64", "libasound2"]);

  for (const deb of fs.readdirSync(runtimeDebDir).filter((f) => f.endsWith(".deb"))) {
    runOrThrow("dpkg-deb", ["-x", path.join(runtimeDebDir, deb), runtimeRootDir]);
  }

  const mergedLdPath = process.env.LD_LIBRARY_PATH
    ? `${runtimeLibDir}:${process.env.LD_LIBRARY_PATH}`
    : runtimeLibDir;
  process.env.LD_LIBRARY_PATH = mergedLdPath;

  const verifiedLdd = tryRun("ldd", [browserBin], { env: { ...process.env, LD_LIBRARY_PATH: mergedLdPath } });
  const stillMissing = parseMissingLibs(`${verifiedLdd.stdout || ""}\n${verifiedLdd.stderr || ""}`)
    .filter((name) => needed.has(name));
  if (stillMissing.length > 0) {
    throw new Error(`Missing shared libraries after local bootstrap: ${stillMissing.join(", ")}`);
  }
}

fs.mkdirSync(outDir, { recursive: true });

const coverPath = path.join(outDir, "cover.png");
const demoWebmPath = path.join(outDir, "demo.webm");

let browser;
let context;
let video;

try {
  ensureLocalRuntimeLibsIfNeeded();
  browser = await chromium.launch({
    headless: true,
    chromiumSandbox: false,
    args: ["--disable-setuid-sandbox", "--no-zygote", "--single-process"],
  });
  context = await browser.newContext({
    viewport: { width, height },
    deviceScaleFactor: 2,
    recordVideo: { dir: outDir, size: { width, height } },
  });

  const page = await context.newPage();
  video = page.video();

  await page.goto(url, { waitUntil: "domcontentloaded", timeout: 60000 });

  // ちょい動きを作る（汎用デモ）
  await page.waitForTimeout(800);
  await page.mouse.wheel(0, Math.floor(height * 0.6));
  await page.waitForTimeout(400);
  await page.mouse.wheel(0, -Math.floor(height * 0.3));
  await page.waitForTimeout(400);

  const clickable = await page.$("button, a[role='button'], input[type='button'], input[type='submit']");
  if (clickable) {
    await clickable.click({ timeout: 1500 }).catch(() => {});
    await page.waitForTimeout(500);
  }

  const input = await page.$("textarea, input[type='text'], input:not([type])");
  if (input) {
    await input.fill("サンプル入力").catch(() => {});
    await page.waitForTimeout(400);
  }

  await page.waitForTimeout(Math.max(1, duration) * 1000);
  await page.screenshot({ path: coverPath, fullPage: false });
} catch (e) {
  console.error(JSON.stringify({ ok: false, error: String(e) }));
  await context?.close().catch(() => {});
  await browser?.close().catch(() => {});
  process.exit(1);
}

// ★録画確定
await context?.close();
await browser?.close();

// 録画ファイルを固定名にリネーム
try {
  const vpath = await video?.path();
  if (vpath && fs.existsSync(vpath)) {
    if (fs.existsSync(demoWebmPath)) fs.rmSync(demoWebmPath);
    fs.renameSync(vpath, demoWebmPath);
  }
} catch {}

console.log(JSON.stringify({ ok: true, cover: coverPath, demo_webm: demoWebmPath }));
