// Renders the app icon master to every size the stores want, plus the
// Android adaptive-icon layers and the boot splash. Run via make_icons.sh.
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '../..');
const out = path.join(root, 'ui/icons');
const svg = fs.readFileSync(path.join(__dirname, 'app_icon.svg'), 'utf8');
const inner = svg.replace(/^[\s\S]*?<svg[^>]*>/, '').replace(/<\/svg>\s*$/, '');
const defs = inner.match(/<defs>[\s\S]*?<\/defs>/)[0];
// Background layer = sky + mountains; foreground = everything after them.
const cut = inner.indexOf('<g transform="translate(-50 0)">');
const bgPart = inner.slice(0, cut);
const fgPart = defs + inner.slice(cut);
const font = 'data:font/ttf;base64,' + fs.readFileSync(path.join(root, 'fonts/LilitaOne-Regular.ttf')).toString('base64');

const wrap = (body, size, opts = {}) => `<!doctype html><html><head><style>
@font-face { font-family: Lilita; src: url(${font}); }
html,body { margin:0; background:${opts.bg || 'transparent'}; }
</style></head><body>${body}</body></html>`;
const svgAt = (content, size, view = '0 0 1024 1024') =>
  `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="${view}">${content}</svg>`;

(async () => {
  const browser = await chromium.launch();
  const shot = async (html, w, h, file, transparent) => {
    const page = await browser.newPage({ viewport: { width: w, height: h } });
    await page.setContent(html);
    await page.evaluate(() => document.fonts.ready);
    await page.screenshot({ path: path.join(out, file), omitBackground: !!transparent, clip: { x: 0, y: 0, width: w, height: h } });
    await page.close();
  };
  // Square, opaque icons (iOS rounds the corners itself).
  for (const s of [1024, 512, 192, 180]) await shot(wrap(svgAt(inner, s), s), s, s, `icon_${s}.png`);
  // Android adaptive icon: 432 px layers, art kept inside the middle 66 %.
  await shot(wrap(svgAt(bgPart, 432)), 432, 432, 'adaptive_background_432.png');
  const fg = `<g transform="translate(512 512) scale(0.7) translate(-512 -540)">${fgPart}</g>`;
  await shot(wrap(svgAt(fg, 432)), 432, 432, 'adaptive_foreground_432.png', true);
  // Boot splash: icon + title on the sky colour.
  const splash = `<div style="width:1280px;height:720px;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:28px;background:linear-gradient(#3f9fe8,#bfe6ff)">
    <div style="width:300px;height:300px;border-radius:66px;overflow:hidden;box-shadow:0 10px 30px rgba(10,40,80,.35)">${svgAt(inner, 300)}</div>
    <div style="font-family:Lilita;font-size:64px;color:#fff;text-shadow:0 4px 0 #1f5f9a,0 8px 18px rgba(0,0,0,.25);letter-spacing:1px">A Game About Melting A Glacier</div>
  </div>`;
  await shot(wrap(splash, 1280), 1280, 720, 'splash.png');
  await browser.close();
})();
