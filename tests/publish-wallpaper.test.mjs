import assert from "node:assert/strict";
import { addCatalogItem, parseSubmission, validateImage } from "../scripts/publish-wallpaper.mjs";

const body = `### Wallpaper file / 壁纸文件

<img width="2560" height="1440" alt="Image" src="https://github.com/user-attachments/assets/11111111-1111-1111-1111-111111111111" />

### Display title / 展示名称

Night Walk

### Author or creator / 作者

iStig

### Public license / 公共许可

CC0 1.0

### Rights confirmation / 权利确认

- [x] First
- [x] Second
- [x] Third`;

const submission = parseSubmission(body);
assert.equal(submission.title, "Night Walk");
assert.equal(submission.artist, "iStig");
assert.throws(() => parseSubmission(body.replace("- [x] Third", "- [ ] Third")), /confirmations/);
assert.throws(() => parseSubmission(body.replace("CC0 1.0", "Copyright")), /license/);
assert.throws(() => parseSubmission(body.replace("github.com/user-attachments", "example.com")), /GitHub-hosted/);

const png = Buffer.alloc(24);
png.set([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
png.writeUInt32BE(13, 8);
png.write("IHDR", 12, "ascii");
png.writeUInt32BE(2560, 16);
png.writeUInt32BE(1440, 20);
assert.deepEqual(validateImage(png), { width: 2560, height: 1440, extension: "png" });
png.writeUInt32BE(1280, 16);
png.writeUInt32BE(2774, 20);
assert.throws(() => validateImage(png), /received 1280x2774/);

const catalog = { schemaVersion: 1, items: [] };
const first = addCatalogItem(catalog, submission, {
  width: 2560,
  height: 1440,
  byteCount: 123456,
  extension: "png",
}, 1);
assert.equal(first.changed, true);
assert.equal(first.item.id, 1000001);
assert.equal(first.item.detailsURL, "https://github.com/iStig/Codex-Skin-Clinet/issues/1");
assert.equal(addCatalogItem(catalog, submission, first.item, 1).changed, false);

console.log("PASS: submission parsing, image validation, catalog IDs, and deduplication.");
