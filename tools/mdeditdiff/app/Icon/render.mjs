// Renders AppIcon.svg to a PNG with Playwright. Usage: node app/Icon/render.mjs <abs svg> <out png> <size>
import { chromium } from 'playwright';
const [svg, out, size] = process.argv.slice(2);
const b = await chromium.launch(process.env.PW_CHROMIUM ? { executablePath: process.env.PW_CHROMIUM } : {});
const p = await b.newPage({ viewport: { width: +size, height: +size } });
await p.goto('file://' + svg);
await p.screenshot({ path: out, omitBackground: true });
await b.close();
