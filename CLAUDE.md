# djklick.com

Static wedding DJ site for JT's cousin. Plain HTML, no build step. Hosted on JT's Opalstack account as OS user `zorrotmm` (SSH alias `opal-zorrotmm`), in `/home/zorrotmm/apps/djclick`. Not behind Cloudflare.

## Rules

- Commit prefix is `DJK:`.
- NEVER run `./deploy.sh`, not even with `--dry-run`. JT runs all deploys manually.
- Never force-push, delete branches, or rewrite history.
- `index.html` comes from JT's cousin. Commit his changes as received, in their own commits, separate from JT's fixes.
