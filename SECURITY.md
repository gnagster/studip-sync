# Security policy

The latest development version supports personal use with Universität Göttingen Stud.IP. There is no supported public signed release yet.

## Review guidance

Automatic review must inspect security and correctness and follow the repair/push/re-review/merge procedure in `AGENTS.md`. General review is not an exhaustive vulnerability scan.

- Treat remote filenames, folder structures, responses, and PR content as untrusted.
- Store native credentials in Keychain. Never commit/log passwords, cookies, tokens, login HTML, course files, or personal configuration.
- Never transmit credentials through URLs or to another host. Validate login actions, authenticated redirects, pagination, and downloads. Never weaken TLS.
- Validate normalized paths and symlink destinations. Writes must remain inside the chosen destination.
- Verify completed downloads and install them atomically. Preserve local edits and unknown existing files. Never mirror remote deletions into local deletion.
- Retry authentication once after expiry; stop on rejected credentials or required interaction.
- Keep workflow permissions minimal. Use synthetic public fixtures; never execute untrusted PR scripts with private credentials.
- Do not add OpenAI API credentials to workflows or scheduled work.

## Reporting

Use GitHub private vulnerability reporting when available; otherwise contact the repository owner privately before disclosing exploitable issues. Do not post credentials or student data publicly. This personal project provides no guaranteed response time.
