# Contributing to AI·mana

Thanks for helping. Issues and pull requests are welcome in English or Spanish.

## Ground rules

- **Official data sources by default.** AI·mana reads documented outputs (such as Claude Code's statusline JSON),
  local files that the user's own tools write, and providers' public APIs with the user's own key.
- **Direct access is the only exception, and only for Claude and Codex for now.** It must be:
  - opt-in, off by default, behind the standard notice and the user's consent;
  - read-only toward other programs: never write, copy or renew another app's credentials;
  - documented, including how it fails, and covered by a parity fixture.

  Pull requests that scrape browser cookies or add other undocumented endpoints are declined.
- **No secrets in the repo**, in tests, fixtures or screenshots. Use fake values in fixtures.
- **No analytics or tracking.**
- UI text is English in code. Add translations for every language in the `.xcstrings` catalogs, or leave them for
  a translator and mention it in the PR.

## Development

```bash
brew install xcodegen
cp AImana/Config/Local.xcconfig.example AImana/Config/Local.xcconfig   # set your Team ID and bundle prefix
cd AImana && xcodegen generate
(cd AImanaCore && swift test) && (cd Relay && swift test)
```

Run `xcodegen generate` again after changing `project.yml`. Do not commit `AImana.xcodeproj` changes by hand.

## Adding or fixing a provider

1. Put the parser in its own file. Add a fixture with a real-shaped response, with all values faked, plus tests
   for the normal case, an empty account, an expired or invalid key, and an unknown field.
2. Show nothing rather than something invented. A missing value must stay missing: no guessed percentage or reset
   time.
3. Document which official endpoint or file the provider uses, and link its documentation in the PR.

## Pull requests

- Keep each PR focused on one change. Describe what changed and how you tested it.
- CI must pass: package tests and the unsigned iOS and Mac builds.
- For UI changes, add a screenshot in light and dark mode. Run the app with `-demo` to get sample data.
