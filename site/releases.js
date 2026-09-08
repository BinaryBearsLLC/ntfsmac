/* Channel selection is separate from the UI so beta/stable routing is testable. */
globalThis.NtfsmacReleases = {
  select(releases, beta) {
    if (!Array.isArray(releases)) return null;
    return releases.find((release) => {
      if (!release || release.draft !== false || release.prerelease !== beta) return false;
      const pattern = beta ? /^v3\.\d+\.\d+-beta\.[1-9]\d*$/ : /^v3\.\d+\.\d+$/;
      return pattern.test(release.tag_name) &&
        release.html_url === `https://github.com/BinaryBearsLLC/ntfsmac/releases/tag/${release.tag_name}`;
    }) || null;
  }
};
