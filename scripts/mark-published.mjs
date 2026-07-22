const token = process.env.GITHUB_TOKEN;
const repository = process.env.GITHUB_REPOSITORY;
const issueNumber = Number(process.env.ISSUE_NUMBER);
if (!token || !repository || !Number.isSafeInteger(issueNumber)) {
  throw new Error("GITHUB_TOKEN, GITHUB_REPOSITORY, and ISSUE_NUMBER are required.");
}

const headers = {
  Accept: "application/vnd.github+json",
  Authorization: `Bearer ${token}`,
  "Content-Type": "application/json",
  "User-Agent": "Codex-Skin-Clinet-publisher",
  "X-GitHub-Api-Version": "2022-11-28",
};
const issueURL = `https://api.github.com/repos/${repository}/issues/${issueNumber}`;
const issueResponse = await fetch(issueURL, { headers });
if (!issueResponse.ok) throw new Error(`Issue lookup failed: HTTP ${issueResponse.status}`);
const issue = await issueResponse.json();
const labels = issue.labels
  .map((label) => typeof label === "string" ? label : label.name)
  .filter((label) => label && label !== "approved" && label !== "needs-review");
if (!labels.includes("published")) labels.push("published");

const updateResponse = await fetch(issueURL, {
  method: "PATCH",
  headers,
  body: JSON.stringify({ labels }),
});
if (!updateResponse.ok) throw new Error(`Issue label update failed: HTTP ${updateResponse.status}`);

const commentResponse = await fetch(`${issueURL}/comments`, {
  method: "POST",
  headers,
  body: JSON.stringify({
    body: "Published to `community/catalog.json`. It is now available to Dream Skin clients.",
  }),
});
if (!commentResponse.ok) throw new Error(`Issue comment failed: HTTP ${commentResponse.status}`);
console.log(`Marked issue #${issueNumber} as published.`);
