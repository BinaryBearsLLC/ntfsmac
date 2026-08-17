const releaseLink = document.querySelector("#release-link");
const releaseStatus = document.querySelector("#release-status");

fetch("https://api.github.com/repos/BinaryBearsLLC/ntfsmac/releases/latest", {
  headers: { Accept: "application/vnd.github+json" }
})
  .then((response) => {
    if (!response.ok) throw new Error("No published release");
    return response.json();
  })
  .then((release) => {
    if (!release || release.draft || release.prerelease || !release.html_url) return;
    releaseLink.href = release.html_url;
    releaseLink.textContent = `Get ${release.tag_name}`;
    releaseStatus.textContent = `Latest published release: ${release.tag_name}`;
  })
  .catch(() => {
    // The Releases link and pre-release message are already useful offline or under API limits.
  });
