# Repository Instructions

This repository contains Ronald Bosma's Hugo blog, deployed to GitHub Pages through Azure Pipelines.

## Repository Layout

- `content/blog/<slug>/index.md` — blog posts. Each post lives in its own folder.
- `content/series/<slug>/_index.md` — series pages. Each series landing page lives in its own folder.
- `static/images/<slug>/` — images for a post (referenced from the post as `../../../../../images/<slug>/<file>`).
- `layouts/`, `themes/`, `config.toml` — Hugo site configuration and theme.
- `azure-pipelines.yml` — build and deploy pipeline.
- `archetypes/` — Hugo content archetypes.

## Agent Usage

- Use the `Blog Author` agent when writing or revising blog posts in `content/blog/<slug>/index.md`.

## Common Commands

```powershell
# Local preview (includes drafts)
hugo server -D

# Production build
hugo
```
