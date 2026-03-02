# Git Resync Documentation

## Overview

This document describes the git resync that was performed to synchronize the fork with the upstream repository.

## Fork Information

- **Upstream Repository**: https://github.com/tmbb/dantzig.git
- **Fork Repository**: https://github.com/AlbaIntelligence/dantzig.git

## Resync Status

The fork has been resynced with the upstream repository. The `main` branch is now in sync with `upstream/master`.

## Branch Structure

The repository uses the following branch structure:

### main

The main branch (`main`) is synchronized with the upstream repository's master branch (`upstream/master`). This branch contains the core Dantzig library with:

- Basic constraint and variable definitions
- HiGHS solver integration
- Standard optimization problem formulations

### main-dsl-backup (main-dsl-features-backup)

This branch serves as a backup of the main branch with DSL features integrated. It was created to preserve work on the Domain-Specific Language (DSL) implementation before merging into the main development branch.

Contains:

- All upstream changes
- DSL (Domain-Specific Language) feature development
- Experimental DSL features that may be merged in future iterations

### dsl

The `dsl` branch is the current working branch for developing the Domain-Specific Language (DSL) features. This branch extends the `main` branch with:

- Custom DSL syntax for defining optimization problems
- Expression parsing for constraint definitions
- Variable management enhancements
- Generator-based problem construction
- Advanced pattern-based operations

## Current Development Workflow

1. **Sync with upstream**: Pull latest changes from `upstream/master` into `main`
2. **Feature development**: Work on `dsl` branch for new DSL features
3. **Backup**: Keep `main-dsl-features-backup` as a backup of work-in-progress

## Commands Used for Resync

```bash
# Add upstream remote (if not already present)
git remote add upstream https://github.com/tmbb/dantzig.git

# Fetch upstream changes
git fetch upstream

# Checkout main branch
git checkout main

# Merge upstream/master into main
git merge upstream/master

# Push changes to fork
git push origin main
```

## Additional Branches

Other branches in the repository include:

- `dsl-features`: Feature development branch for DSL
- `examples-enhanced-complex`: Examples with enhanced complexity
- `main-backup-20260302`: Backup from March 2, 2026
- `003-testing`: Testing branch

## Notes

- The `master` branch is a remote tracking branch for `origin/master`
- All active development happens on the `dsl` branch
- The fork is regularly resynced with upstream to keep up with the latest upstream changes
