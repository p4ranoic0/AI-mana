# Security policy

AI·mana handles API keys that users enter and reads local usage files. Please report security problems
privately. Do not open a public issue for them.

## Reporting

Use GitHub's **Report a vulnerability** button (Security › Advisories) in this repository. Include:
- the affected version or commit;
- steps to reproduce;
- what an attacker could gain.

You should get a reply within 7 days. Please allow time for a fix before you disclose anything publicly.

## Scope

In scope:
- leaking API keys, for example in logs, the relay file, crash output or screenshots;
- writing credentials or prompt text to the iCloud relay file;
- the Mac app modifying user files beyond its documented statusline integration;
- anything that sends user data to a party the user did not choose.

Out of scope: problems in the providers' own services and APIs. Report those to the provider.
