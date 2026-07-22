import fs from "node:fs/promises";
import { readImageMetadata } from "./image-metadata.mjs";

const MAX_BYTES = 50 * 1024 * 1024;
const LICENSES = new Set(["CC0 1.0", "CC BY 4.0", "CC BY-SA 4.0"]);
const ATTACHMENT_PATTERN = /^https:\/\/github\.com\/user-attachments\/assets\/[0-9a-f-]+$/i;
const REDIRECT_HOSTS = new Set(["github.com", "objects.githubusercontent.com"]);

function section(body, heading) {
  const marker = `### ${heading}`;
  const start = body.indexOf(marker);
  if (start < 0) throw new Error(`Missing form section: ${heading}`);
  const contentStart = start + marker.length;
  const end = body.indexOf("\n### ", contentStart);
  return body.slice(contentStart, end < 0 ? body.length : end).trim();
}

export function parseSubmission(body) {
  const imageSection = section(body, "Wallpaper file / 壁纸文件");
  const urls = [...imageSection.matchAll(/src="([^"]+)"/g)].map((match) => match[1]);
  if (urls.length !== 1 || !ATTACHMENT_PATTERN.test(urls[0])) {
    throw new Error("Submit exactly one GitHub-hosted image attachment.");
  }
  const title = section(body, "Display title / 展示名称");
  const artist = section(body, "Author or creator / 作者");
  const license = section(body, "Public license / 公共许可");
  const rights = section(body, "Rights confirmation / 权利确认");
  if (!title || title.length > 160 || !artist || artist.length > 160) {
    throw new Error("Title and author must contain 1-160 characters.");
  }
  if (!LICENSES.has(license)) throw new Error(`Unsupported license: ${license}`);
  if ((rights.match(/^- \[x\] /gim) || []).length !== 3) {
    throw new Error("All rights confirmations must be checked.");
  }
  return { originalURL: urls[0], title, artist, license };
}

async function downloadImage(url) {
  const response = await fetch(url, { redirect: "follow" });
  if (!response.ok || !response.body) throw new Error(`Image download failed: HTTP ${response.status}`);
  const finalURL = new URL(response.url);
  if (finalURL.protocol !== "https:" || !REDIRECT_HOSTS.has(finalURL.hostname.toLowerCase())) {
    throw new Error("Image download redirected to an untrusted host.");
  }
  const declaredLength = Number(response.headers.get("content-length") || 0);
  if (declaredLength > MAX_BYTES) throw new Error("Image exceeds 50 MB.");
  const chunks = [];
  let byteCount = 0;
  for await (const chunk of response.body) {
    byteCount += chunk.length;
    if (byteCount > MAX_BYTES) throw new Error("Image exceeds 50 MB.");
    chunks.push(chunk);
  }
  return Buffer.concat(chunks, byteCount);
}

export function validateImage(bytes) {
  const metadata = readImageMetadata(bytes);
  if (!metadata) throw new Error("Attachment must be a valid JPG, PNG, or WebP image.");
  const { width, height } = metadata;
  const ratio = width / height;
  if (width < 1920 || height < 900 || width > 16384 || height > 16384 ||
      width * height > 50_000_000 || ratio < 1.45 || ratio > 2.6) {
    throw new Error(`Image must be a 1920x900+ landscape image (ratio 1.45-2.6); received ${width}x${height}.`);
  }
  return metadata;
}

export function addCatalogItem(catalog, submission, image, issueNumber) {
  if (catalog.schemaVersion !== 1 || !Array.isArray(catalog.items)) {
    throw new Error("community/catalog.json has an unsupported schema.");
  }
  const detailsURL = `https://github.com/iStig/Codex-Skin-Clinet/issues/${issueNumber}`;
  const existing = catalog.items.find((item) =>
    item.detailsURL === detailsURL || item.originalURL === submission.originalURL
  );
  if (existing) return { item: existing, changed: false };
  const highestID = catalog.items.reduce((value, item) => Math.max(value, Number(item.id) || 0), 1_000_000);
  const item = {
    id: highestID + 1,
    title: submission.title,
    originalURL: submission.originalURL,
    thumbnailURL: submission.originalURL,
    detailsURL,
    width: image.width,
    height: image.height,
    byteCount: image.byteCount,
    artist: submission.artist,
    license: submission.license,
    fileExtension: image.extension,
  };
  catalog.items.push(item);
  return { item, changed: true };
}

async function githubIssue(issueNumber, token) {
  const response = await fetch(`https://api.github.com/repos/iStig/Codex-Skin-Clinet/issues/${issueNumber}`, {
    headers: {
      Accept: "application/vnd.github+json",
      Authorization: `Bearer ${token}`,
      "User-Agent": "Codex-Skin-Clinet-publisher",
      "X-GitHub-Api-Version": "2022-11-28",
    },
  });
  if (!response.ok) throw new Error(`Issue lookup failed: HTTP ${response.status}`);
  return response.json();
}

async function main() {
  const issueNumber = Number(process.env.ISSUE_NUMBER);
  const token = process.env.GITHUB_TOKEN;
  if (!Number.isSafeInteger(issueNumber) || issueNumber < 1 || !token) {
    throw new Error("ISSUE_NUMBER and GITHUB_TOKEN are required.");
  }
  const issue = await githubIssue(issueNumber, token);
  if (issue.pull_request || !issue.body) throw new Error("The selected item is not a wallpaper Issue.");
  const submission = parseSubmission(issue.body);
  const bytes = await downloadImage(submission.originalURL);
  const metadata = validateImage(bytes);
  const catalogPath = new URL("../community/catalog.json", import.meta.url);
  const catalog = JSON.parse(await fs.readFile(catalogPath, "utf8"));
  const result = addCatalogItem(catalog, submission, {
    ...metadata,
    byteCount: bytes.length,
  }, issueNumber);
  if (result.changed) await fs.writeFile(catalogPath, `${JSON.stringify(catalog, null, 2)}\n`, "utf8");
  console.log(result.changed
    ? `Published wallpaper ${result.item.id}: ${result.item.title}`
    : `Wallpaper ${result.item.id} is already published.`);
}

if (process.argv[1] && import.meta.url === new URL(`file://${process.argv[1]}`).href) {
  main().catch((error) => {
    console.error(`ERROR: ${error.message}`);
    process.exitCode = 1;
  });
}
