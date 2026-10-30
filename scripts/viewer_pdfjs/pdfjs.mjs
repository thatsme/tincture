// pdf.js, the engine of Firefox, for scripts/viewer_check.py, which drives it
// and checks the bytes it saves.
//
//   node scripts/viewer_pdfjs/pdfjs.mjs render IN.pdf OUT.png
//   node scripts/viewer_pdfjs/pdfjs.mjs fill IN.pdf OUT.pdf NAME=VALUE [...]
//
// render draws page 1 with annotations, from their appearance streams unless
// pdf.js decides to regenerate them. fill sets field values the way the
// viewer's form layer does (annotationStorage) and saves, which is when
// pdf.js writes a new appearance. Values may use \uXXXX escapes.
import fs from "node:fs";
import { createRequire } from "node:module";
import { getDocument, AnnotationMode, version } from "pdfjs-dist/legacy/build/pdf.mjs";

const require = createRequire(import.meta.url);
const packageDir = require.resolve("pdfjs-dist/package.json").replace(/package\.json$/, "");
const options = {
  cMapUrl: packageDir + "cmaps/",
  cMapPacked: true,
  standardFontDataUrl: packageDir + "standard_fonts/",
  verbosity: 0,
};

const open = (path) =>
  getDocument({ data: new Uint8Array(fs.readFileSync(path)), ...options }).promise;

async function render(input, output) {
  const doc = await open(input);
  const page = await doc.getPage(1);
  const viewport = page.getViewport({ scale: 2 });
  const canvas = doc.canvasFactory.create(viewport.width, viewport.height);

  await page.render({
    canvasContext: canvas.context,
    canvas: canvas.canvas,
    viewport,
    annotationMode: AnnotationMode.ENABLE,
  }).promise;

  fs.writeFileSync(output, canvas.canvas.toBuffer("image/png"));
}

async function fill(input, output, pairs) {
  const wanted = Object.fromEntries(
    pairs.map((pair) => {
      const at = pair.indexOf("=");
      const value = pair
        .slice(at + 1)
        .replace(/\\u([0-9a-fA-F]{4})/g, (_, hex) => String.fromCharCode(parseInt(hex, 16)));
      return [pair.slice(0, at), value];
    })
  );

  const doc = await open(input);
  const page = await doc.getPage(1);
  const filled = [];

  for (const annotation of await page.getAnnotations()) {
    if (annotation.subtype === "Widget" && annotation.fieldName in wanted) {
      doc.annotationStorage.setValue(annotation.id, { value: wanted[annotation.fieldName] });
      filled.push(annotation.fieldName);
    }
  }

  fs.writeFileSync(output, await doc.saveDocument());
  console.log(JSON.stringify({ filled }));
}

const [command, ...args] = process.argv.slice(2);

if (command === "version") console.log(version);
else if (command === "render") await render(args[0], args[1]);
else if (command === "fill") await fill(args[0], args[1], args.slice(2));
else {
  console.error("usage: pdfjs.mjs version | render IN OUT | fill IN OUT NAME=VALUE...");
  process.exit(2);
}
