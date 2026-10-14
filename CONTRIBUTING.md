# Contributing to Household Helper

This project follows the [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/)
specification for all commit messages. A consistent history keeps changelogs and
[Semantic Versioning](https://semver.org/) automatable.

## Commit message format

```
<type>[optional scope][optional !]: <description>

[optional body]

[optional footer(s)]
```

- The **description** follows the colon-and-space and is a short, imperative summary
  ("add", not "added"/"adds").
- The **body** (after a blank line) explains the *what* and *why*, not the *how*.
- **Footers** (after a blank line) use git-trailer style: `Token: value` or `Token #value`.

### Types

| Type       | Use for                                                        | SemVer  |
| ---------- | -------------------------------------------------------------- | ------- |
| `feat`     | A new feature                                                  | MINOR   |
| `fix`      | A bug fix                                                      | PATCH   |
| `docs`     | Documentation only                                             | –       |
| `style`    | Formatting/whitespace, no code-behavior change                 | –       |
| `refactor` | Code change that neither fixes a bug nor adds a feature        | –       |
| `perf`     | A performance improvement                                      | PATCH   |
| `test`     | Adding or correcting tests                                     | –       |
| `build`    | Build system or dependencies (Go modules, SPM, Gradle)         | –       |
| `ci`       | CI configuration and scripts                                   | –       |
| `chore`    | Other changes that don't touch src or tests                    | –       |
| `revert`   | Reverts a previous commit                                      | –       |

### Scopes (this monorepo)

Scope is optional but encouraged. Use the area of the codebase affected:

- `api` — the Go API (`apps/api`)
- `db` — SQLite migrations (`apps/api/internal/store/migrations`)
- `ios` — the SwiftUI app (`apps/ios`)
- `android` — the Compose app (`apps/android`)
- `dev` — the dev toolkit and skills (`scripts/dev`, `.claude`)
- `ci` — GitHub workflows, Xcode Cloud
- `auth`, `realtime`, `push`, `list`, `shops`, `household` — finer-grained features

Example: `feat(list): group shopping items by shop`.

### Breaking changes

Breaking changes map to a **MAJOR** version bump and must be signalled in one of two ways:

1. A `!` after the type/scope:
   ```
   feat(api)!: rename shopping_list_items.status values
   ```
2. A footer (uppercase token, may be `BREAKING CHANGE` or `BREAKING-CHANGE`):
   ```
   refactor(db): drop the legacy budget view

   BREAKING CHANGE: the monthly_budget_totals view is removed; use budget_summaries instead.
   ```

You may use both. When using `!`, a `BREAKING CHANGE:` footer is optional if the
description already explains it.

## Specification rules (summary)

1. Commits MUST be prefixed with a **type**, which is a noun (`feat`, `fix`, …), followed
   by an OPTIONAL scope, an OPTIONAL `!`, and a REQUIRED terminal colon and space.
2. The type `feat` MUST be used for new features; `fix` MUST be used for bug fixes.
3. A scope MAY follow the type, inside parentheses: `fix(parser):`.
4. A **description** MUST immediately follow the colon and space.
5. A longer **body** MAY follow the description, after one blank line.
6. A body is free-form and MAY consist of multiple newline-separated paragraphs.
7. One or more **footers** MAY follow the body, after one blank line. Each footer is a
   token, then `: ` or ` #`, then a value.
8. A footer's **token** MUST use `-` in place of whitespace (e.g. `Reviewed-by`); the
   exception is `BREAKING CHANGE`.
9. A footer's value MAY contain spaces and newlines; parsing ends at the next valid
   footer token/separator.
10. Breaking changes MUST be indicated in the type/scope prefix (`!`) or as a footer.
11. As a footer, a breaking change MUST be `BREAKING CHANGE`, uppercase, followed by
    `: ` and a description.
12. With `!` in the prefix, the `BREAKING CHANGE:` footer is OPTIONAL and the description
    conveys the breaking change.
13. Types other than `feat` and `fix` MAY be used.
14. The units of information are case-**insensitive**, except `BREAKING CHANGE`, which
    MUST be uppercase.
15. `BREAKING-CHANGE` MUST be treated as synonymous with `BREAKING CHANGE` as a footer
    token.

## Examples

```
feat(api): bulk-clear bought items
fix(realtime): reconnect with a fresh token after the stream expires
docs(dev): document the emulator seed
refactor(ios): move list grouping into a pure function
build(android): bump material3 to 1.5.0-beta02
feat(api)!: require a client id on item creation
```

## Pull requests

- Keep PRs focused; a PR title SHOULD follow the same Conventional Commits format.
- Before opening a PR, make sure things pass:
  - API: `make -C apps/api test` (vet + `go test -race`); `make -C apps/api golden` after a JSON change,
    then fix the two decode tests.
  - iOS: `scripts/dev/ios.sh unit` (and `uitest SmokeTests` when a screen changed).
  - Android: `scripts/dev/android.sh unit` (and `uitest` when a screen changed).
  - A UI change has been driven and asserted in the simulator/emulator (see the verify skills).
  - `scripts/dev/secrets-check.sh` is clean (it runs as the pre-commit hook; never bypass it).
- Reference related issues in a footer: `Refs: #123` or `Closes: #123`.
