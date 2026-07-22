const labels = [
  { name: "community-wallpaper", color: "1d76db", description: "Community wallpaper submission" },
  { name: "needs-review", color: "fbca04", description: "Waiting for maintainer review" },
  { name: "approved", color: "0e8a16", description: "Approved for automatic publication" },
  { name: "published", color: "5319e7", description: "Published in the community catalog" },
];

const token = process.env.GITHUB_TOKEN;
const repository = process.env.GITHUB_REPOSITORY;
if (!token || !repository) throw new Error("GITHUB_TOKEN and GITHUB_REPOSITORY are required.");

for (const label of labels) {
  const response = await fetch(`https://api.github.com/repos/${repository}/labels`, {
    method: "POST",
    headers: {
      Accept: "application/vnd.github+json",
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
      "User-Agent": "Codex-Skin-Clinet-label-setup",
      "X-GitHub-Api-Version": "2022-11-28",
    },
    body: JSON.stringify(label),
  });
  if (response.ok) {
    console.log(`Created label: ${label.name}`);
  } else if (response.status === 422) {
    console.log(`Label already exists: ${label.name}`);
  } else {
    throw new Error(`Could not create ${label.name}: HTTP ${response.status}`);
  }
}
