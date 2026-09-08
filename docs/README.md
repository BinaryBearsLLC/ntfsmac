# Documentation

## For users

- [Project README](../README.md): requirements, installation, use and support.
- [Security](../SECURITY.md): vulnerability reporting and data-safety boundaries.
- [Compatibility evidence](testing/BINARYBEARS_V3_1_3_INSTALLED_2026-09-08.md):
  exact builds, systems and operations checked for 3.1.3.

## For development

- [Contributing](../CONTRIBUTING.md): local setup and pull requests.
- [Architecture](dev/PLAN.md): components and privilege boundaries.
- [GUI contract](dev/GUI-PLAN.md): current controls and state behavior.
- [Testing](dev/TESTING.md): automated, package and hardware gates.
- [Dependency policy](dev/ANYLINUXFS_UPDATE_POLICY.md): controlled updates.
- [Release process](RELEASE.md) and [branch policy](BRANCHING.md).
- [Roadmap](BINARYBEARS_ROADMAP.md): release scope and current priorities.

## Evidence and history

`testing/` holds dated validation records; `audits/` holds security investigations.
`build/AUDIT.md` preserves dependency provenance and keep/cut decisions. These are
evidence, not an alternative current feature specification.

Superseded session diaries, TDD narratives and the original autonomous build plan
were removed from the active tree during the 3.1.3 cleanup. Their complete contents
remain recoverable at commit `90388df`. Executable regression tests were retained.
