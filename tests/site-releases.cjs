const assert = require('node:assert/strict');
require('../site/releases.js');
const select = globalThis.NtfsmacReleases.select;
const release = (tag, beta, draft = false) => ({ tag_name: tag, prerelease: beta, draft,
  html_url: `https://github.com/BinaryBearsLLC/ntfsmac/releases/tag/${tag}` });
const stable = release('v3.1.2', false);
const beta = release('v3.1.3-beta.1', true);
assert.equal(select([beta, stable], false), stable);
assert.equal(select([stable, beta], true), beta);
assert.equal(select([release('v3.1.3-beta.2', true, true), beta], true), beta);
assert.equal(select([{ ...beta, html_url: 'https://example.com' }], true), null);
assert.equal(select([release('v3.1.3', true)], true), null);
assert.equal(select([release('v3.1.3-beta.1', false)], false), null);
assert.equal(select(null, true), null);
assert.equal(select([], true), null);
console.log('PASS: stable/beta selection, drafts, malformed data and URL boundaries');
