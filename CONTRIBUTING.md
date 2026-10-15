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

6. `dev` is synced with `main` automatically: after every merge into `main`, the
   `sync-dev-with-main` workflow (`.github/workflows/sync-dev-with-main.yml`) opens a pull
   request from `main` into `dev` and merges it (merge commit; no content changes). Afterwards
   `git log origin/dev..origin/main` must be empty; then update your local `dev`:

       git switch dev
       git pull

   If the workflow fails, sync by hand:

       gh pr create --base dev --head main --title "Sync dev with main" --body "Sync after release."
       gh pr merge --merge <number>

Never commit directly to `dev` or `main`. `main` only accepts pull requests from `dev`: the
`source-branch-is-dev` check (`.github/workflows/main-only-from-dev.yml`) fails for any other
source branch.

## Repository settings (GitHub)

- Ruleset `protected-branches` on `main` (default branch) and `dev` (pattern `dev`): require a pull
  request before merging (0 approvals, since nobody can approve their own pull request), block
  force pushes and deletion.
- On `main` also: require the status check `source-branch-is-dev`.
- "Automatically delete head branches" on, so merged work branches are removed from GitHub.
- Settings → Actions → General → Workflow permissions: "Allow GitHub Actions to create and
  approve pull requests" on, required by `sync-dev-with-main`.
