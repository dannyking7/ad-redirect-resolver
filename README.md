# ad-redirect-resolver

AI-agent skill: **give it only a cloaked ad-redirect URL → it reports the real content behind it.**

Install / run:

```bash
cp -r scripts /tmp/ad-resolver && cd /tmp/ad-resolver
bash resolve.sh "https://your-domain/4/1a2b3c4d5e64hex..."
```

Reads `SKILL.md` first for the full recipe, debugging table and proven chains.

Requirements: `bash`, `python3`, `curl-impersonate-chrome` (the script falls back to plain `curl` with lower pass rates).
