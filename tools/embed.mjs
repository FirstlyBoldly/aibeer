#!/usr/bin/env node
// Regenerates the web app outputs from single sources:
//   • shaders/beer-liquid.fsh      → the liquid shader (single source of truth)
//   • preview/styles.json          → BeerCore style presets (from `beerctl dump-styles`)
//   • shared/runtime.js            → the JS runtime (physics ports, GL, input, loop)
//
// Outputs (self-contained, openable from file:// with no web server):
//   • preview/index.html — dev harness (screenshot params: freeze/kick/clean)
//   • app/index.html     — the installable PWA (gyro, manifest, service worker)
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const shader = readFileSync(join(root, 'shaders/beer-liquid.fsh'), 'utf8');
const styles = JSON.stringify(JSON.parse(readFileSync(join(root, 'preview/styles.json'), 'utf8')));
const runtime = readFileSync(join(root, 'shared/runtime.js'), 'utf8');

if (!shader.includes('void main()')) {
  throw new Error('shaders/beer-liquid.fsh does not look like the liquid shader');
}
if (!runtime.includes('function createAibeer')) {
  throw new Error('shared/runtime.js does not look like the runtime');
}

function build(templatePath, outPath) {
  const template = readFileSync(join(root, templatePath), 'utf8');
  if (!template.includes('__SHADER_BODY__') || !template.includes('__STYLES_JSON__') || !template.includes('__RUNTIME__')) {
    throw new Error(`${templatePath} is missing placeholders`);
  }
  const out = template
    .replace('__RUNTIME__', () => runtime)
    .replace('__SHADER_BODY__', () => shader.replace(/`/g, '\\`'))
    .replace('__STYLES_JSON__', () => styles);
  writeFileSync(join(root, outPath), out);
  console.log(`${outPath} written`);
}

build('preview/template.html', 'preview/index.html');
build('app/template.html', 'app/index.html');
