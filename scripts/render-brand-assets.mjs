#!/usr/bin/env node
// Renders Anemone's brand assets (the Monogram app icon) from vector sources.
//
// Writes the SVG sources to docs/brand/monogram/ and the PNGs into the asset
// catalog's "App Icon & Top Shelf Image.brandassets", rendering each SVG with
// headless Chrome. Run from the repository root:
//
//     node scripts/render-brand-assets.mjs
//
// Set CHROME to the browser binary if Chrome isn't in /Applications.

import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const root = resolve(import.meta.dirname, "..");
const sources = join(root, "docs/brand/monogram");
const brand = join(root, "App/Assets.xcassets/App Icon & Top Shelf Image.brandassets");
const chrome = process.env.CHROME ?? "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";

// ---- the mark ----------------------------------------------------------
// Drawn in a 1024-unit square centred on 0,0: two tentacles lean together to
// form the A of Anemone, and a magenta play wedge stands in for the crossbar.

// A tapered tentacle pointing along +y from `r0` to `r0 + len`, half-width `w`
// at the base, with a rounded tip that sways sideways by `sway`.
function tentaclePath(r0, len, w, sway) {
  const tip = r0 + len, tw = w * 0.52, y1 = tip - tw * 1.1;
  return `M ${-w} ${r0}
    C ${-w * 1.05} ${r0 + len * 0.4}, ${-tw + sway * 0.85} ${r0 + len * 0.72}, ${-tw + sway} ${y1}
    Q ${sway} ${tip + tw * 0.95}, ${tw + sway} ${y1}
    C ${tw + sway * 0.85} ${r0 + len * 0.72}, ${w * 1.05} ${r0 + len * 0.4}, ${w} ${r0} Z`;
}

const defs = `
  <linearGradient id="bg" x1="0" y1="-1200" x2="0" y2="1200" gradientUnits="userSpaceOnUse">
    <stop offset="0" stop-color="#4a0bb0"/><stop offset=".55" stop-color="#2a0a6a"/><stop offset="1" stop-color="#15121c"/>
  </linearGradient>
  <linearGradient id="leg" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#d2bcff"/><stop offset="1" stop-color="#f1e8ff"/>
  </linearGradient>
  <linearGradient id="wedge" x1="0" y1="0" x2="1" y2="0">
    <stop offset="0" stop-color="#b800a3"/><stop offset="1" stop-color="#ff4fb0"/>
  </linearGradient>`;

const layers = {
  back: `<rect x="-6000" y="-6000" width="12000" height="12000" fill="url(#bg)"/>`,
  // Both legs start at the bottom and point up (rotate 180), leaning in by 21 degrees.
  middle: `<g transform="translate(0 380)">
    <path d="${tentaclePath(0, 760, 78, -70)}" fill="url(#leg)" transform="translate(-250 0) rotate(201)"/>
    <path d="${tentaclePath(0, 760, 78, 70)}" fill="url(#leg)" transform="translate(250 0) rotate(159)"/>
  </g>`,
  front: `<path d="M -58 -84 L 90 0 L -58 84 Z" fill="url(#wedge)" stroke="url(#wedge)" stroke-width="30" stroke-linejoin="round" transform="translate(6 150)"/>`,
};

// An SVG of the given pixel size showing `which` layers, with the mark scaled
// so that it fills the canvas the way the 1024 square does (`scale` is the
// mark's size relative to the canvas height, 1 for the square).
function svg({ width, height, scale, which }) {
  const s = (height / 1024) * scale;
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="${-width / 2} ${-height / 2} ${width} ${height}">
  <defs>${defs}</defs>
  <g transform="scale(${s})">${which.map((k) => layers[k]).join("\n")}</g>
</svg>`;
}

// tvOS tiles show the mark at 0.72 of the square's size (the 1024 square is
// 1024 tall; a 768-tall tile shows it at 0.96 of its height).
const tv = (height) => (1024 / height) * 0.72 * (height / 768);
const all = ["back", "middle", "front"];

const renders = [
  // Sources, kept in docs/brand/monogram.
  { out: join(sources, "icon-1024.svg"), width: 1024, height: 1024, scale: 1, which: all },
  { out: join(sources, "tv-back.svg"), width: 1280, height: 768, scale: tv(768), which: ["back"] },
  { out: join(sources, "tv-middle.svg"), width: 1280, height: 768, scale: tv(768), which: ["middle"] },
  { out: join(sources, "tv-front.svg"), width: 1280, height: 768, scale: tv(768), which: ["front"] },
  { out: join(sources, "top-shelf.svg"), width: 1920, height: 720, scale: tv(720), which: all },
];

// PNGs for the asset catalog: [imagestack or imageset path, filename, width, height, layers].
const stack = (name, layer, w, h) => join(brand, `${name}.imagestack`, `${layer}.imagestacklayer`, "Content.imageset");
const pngs = [];
for (const [layer, which] of [["Back", ["back"]], ["Middle", ["middle"]], ["Front", ["front"]]]) {
  pngs.push({ dir: stack("App Icon", layer), file: `${layer.toLowerCase()}@1x.png`, width: 400, height: 240, scale: tv(240), which });
  pngs.push({ dir: stack("App Icon", layer), file: `${layer.toLowerCase()}@2x.png`, width: 800, height: 480, scale: tv(480), which });
  pngs.push({ dir: stack("App Icon - App Store", layer), file: `${layer.toLowerCase()}.png`, width: 1280, height: 768, scale: tv(768), which });
}
pngs.push({ dir: join(brand, "Top Shelf Image.imageset"), file: "top-shelf@1x.png", width: 1920, height: 720, scale: tv(720), which: all });
pngs.push({ dir: join(brand, "Top Shelf Image.imageset"), file: "top-shelf@2x.png", width: 3840, height: 1440, scale: tv(1440), which: all });
pngs.push({ dir: join(brand, "Top Shelf Image Wide.imageset"), file: "top-shelf-wide@1x.png", width: 2320, height: 720, scale: tv(720), which: all });
pngs.push({ dir: join(brand, "Top Shelf Image Wide.imageset"), file: "top-shelf-wide@2x.png", width: 4640, height: 1440, scale: tv(1440), which: all });
pngs.push({ dir: sources, file: "icon-ios-1024.png", width: 1024, height: 1024, scale: 1, which: all });

mkdirSync(sources, { recursive: true });
for (const r of renders) writeFileSync(r.out, svg(r));
console.log(`wrote ${renders.length} SVG sources to ${sources}`);

const work = mkdtempSync(join(tmpdir(), "anemone-brand-"));
try {
  for (const p of pngs) {
    const src = join(work, p.file.replace(/\.png$/, ".svg"));
    writeFileSync(src, svg(p));
    mkdirSync(p.dir, { recursive: true });
    const out = join(p.dir, p.file);
    execFileSync(chrome, [
      "--headless=new", "--disable-gpu", "--hide-scrollbars", "--no-first-run",
      `--user-data-dir=${join(work, "profile")}`,
      "--force-device-scale-factor=1", "--default-background-color=00000000",
      `--window-size=${p.width},${p.height}`, `--screenshot=${out}`, `file://${src}`,
    ], { stdio: "pipe" });
    console.log(`rendered ${p.file} (${p.width}x${p.height})`);
  }
} finally {
  rmSync(work, { recursive: true, force: true });
}
