# Contributing

## Branches

| Branch | Purpose |
|---|---|
| `main` | Production. Every release is tagged `vX.Y.Z` (version from `pubspec.yaml`). |
| `dev` | Integration branch. Protected: changes arrive only through pull requests. |
| `feat/<name>`, `fix/<name>`, `refactor/<name>`, `chore/<name>` | Short-lived work branches, created from `dev`. |

Work branch names are lowercase kebab-case in English, e.g. `feat/profile-tab`,
`fix/duplicate-match-dialog`, `chore/git-workflow`.

| Prefix | Use for |
|---|---|
| `feat/` | New behavior visible to players or administrators |
| `fix/` | Bug fixes |
| `refactor/` | Code changes without behavior changes |
| `chore/` | Build, tooling, dependencies, documentation |

## Flow

1. Update `dev` and branch from it:

   ```bash
   git switch dev
   git pull
   git switch -c feat/<name>
   ```

2. Commit (messages in English, imperative mood) and run the checks:

   ```bash
   flutter analyze
   flutter test
   ```

3. Push and open a pull request into `dev`:

   ```bash
   git push -u origin feat/<name>
   gh pr create --base dev --title "<title>" --body "<description>"
   ```

4. After approval, merge the pull request and delete the work branch (on GitHub and locally):

   ```bash
   git switch dev
   git pull
   git branch -d feat/<name>
   ```

5. Release: open a pull request from `dev` into `main`. After it is merged, tag `main` with the
   version of `pubspec.yaml` (raise it for every release) and publish the builds (see `README.md`;
   the release APK is also archived to the local `releaseCopyDir`, if configured):

   ```bash
   git switch main
   git pull
   git tag -a vX.Y.Z -m "Version X.Y.Z"
   git push origin vX.Y.Z
   ```

6. Sync `dev` with `main` by hand after every merge into `main` (merge commit; no content
   changes), then check that `git log origin/dev..origin/main` is empty and update your local
   `dev`:

       gh pr create --base dev --head main --title "Sync dev with main" --body "Sync after release."
       gh pr merge --merge <number>
       git switch dev
       git pull

Never commit directly to `dev` or `main`. `main` only takes pull requests from `dev`: we check it
ourselves before merging (the workflows `main-only-from-dev` and `sync-dev-with-main` were
disabled on 2026-11-06 because GitHub Actions minutes are now billed).

## Repository settings (GitHub)

- Ruleset `protected-branches` on `main` (default branch) and `dev` (pattern `dev`): require a pull
  request before merging (0 approvals, since nobody can approve their own pull request), block
  force pushes and deletion.
- Ruleset `main-only-from-dev` on `main`: block force pushes and deletion (no required status
  check since the workflows were disabled).
- "Automatically delete head branches" on, so merged work branches are removed from GitHub.
- The `main-only-from-dev` and `sync-dev-with-main` workflows are disabled (billed Actions);
  `ios-unsigned` stays available, run by hand.
