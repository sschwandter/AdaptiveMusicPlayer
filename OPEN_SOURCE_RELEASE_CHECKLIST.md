# Open Source Release Checklist

This checklist captures the remaining steps before publishing Adaptive Music Player as a public repository.

## Repository

- [x] Add a license
- [x] Add a public README
- [x] Add contributing guidelines
- [x] Add a security policy
- [x] Add GitHub issue and PR templates
- [x] Ignore local and generated files in `.gitignore`
- [x] Remove tool-specific and internal planning docs that should not ship publicly

## Project Hygiene

- [ ] Decide whether to keep the current bundle identifiers or switch to neutral/example identifiers for the public repo
- [ ] Decide whether to keep the current automatic signing settings and development team in the Xcode project, or document that contributors must set their own signing team locally
- [ ] Remove any remaining local junk files before pushing, such as `.DS_Store`

## Documentation

- [x] Update docs to reflect the current sample-rate behavior
- [ ] Add screenshots or a short demo GIF for the GitHub landing page
- [ ] Add a short "known limitations" or roadmap section if desired

## Verification

- [ ] Test a fresh clone on a clean machine or clean user account
- [ ] Confirm the app builds in Xcode without relying on local-only state
- [ ] Confirm unit tests pass from a fresh clone

## Optional

- [ ] Add a GitHub Actions workflow for unit tests
- [ ] Create an initial GitHub release, such as `v0.1.0`
