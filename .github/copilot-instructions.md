# AI Coding Agent Instructions

This is Ronald Bosma's technical blog built with Hugo and the Mediumish theme, deployed to GitHub Pages via Azure Pipelines.

## Architecture Overview

**Blog Structure**: Hugo static site generator with content organized as page bundles
- `content/blog/[post-name]/index.md` - Blog posts with front matter
- `content/blog/[post-name]/cover.[webp|png]` - Post cover images (must contain "cover" in filename)
- `static/images/[post-name]/` - Additional post assets
- `themes/mediumish/` - Git submodule containing theme files

**Publication Workflow**: 
- Master branch triggers Azure Pipeline → Hugo build → GitHub Pages deployment
- Pipeline uses `GitHubPagesPublish@1` task to push to `ronaldbosma.github.io` repository
- Hugo version: 0.92.2 (specified in pipeline)

## Content Creation Patterns

**New Post Command**: `hugo new blog/[post-name]/index.md`

**Post Front Matter Template** (from `archetypes/default.md`):
```yaml
---
title: "{{ replace .Name "-" " " | title }}"
date: {{ .Date }}
publishdate: {{ .Date }}
lastmod: {{ .Date }}
tags: []
summary: ""
draft: true
---
```

**Content Conventions**:
- Cover images must include "cover" in filename for theme recognition
- Tags appear in jumbotron footer and post metadata
- `publishdate` displays on post, `lastmod` shows as hint
- Reading time calculated automatically by Hugo

## Development Workflows

**Local Development**:
```powershell
hugo server -D  # Serves drafts on localhost:1313
```

**Image Management**:
- Place cover images next to `index.md` in post folder
- Additional images go in `static/images/[post-name]/`
- Theme looks for `*cover*` pattern in post resources

## Theme Customization

**Configuration** (`config.toml`):
- Base URL: `https://ronaldbosma.github.io/`
- Permalink structure: `/blog/:year/:month/:day/:slug`
- Author config with thumbnail and description
- Social links: GitHub, LinkedIn, Twitter
- Index page customization with picture, title, subtitle, markdown text

**Theme Structure**:
- `themes/mediumish/layouts/` - Template files
- `themes/mediumish/assets/css/` - Stylesheets (medium.css, additional.css)
- Custom templates: `_custom/app-insights.html`, `_custom/remove-cookies.html`

## Pipeline Configuration

**Azure Pipeline** (`azure-pipelines.yml`):
- **Stage 1**: Generate Hugo site on Ubuntu (uses hugo-extension v2)
- **Stage 2**: Publish to GitHub Pages on Windows (PowerShell requirement)
- Variables: `github-username`, `github-email`, `github-personal-access-token`, `repository`
- Only publishes from master branch
- Submodules checked out for theme

## Project Conventions

**Branch Strategy**: Feature branches for new posts, master for production
**Tech Focus**: Microsoft technologies, Azure, SpecFlow, testing, .NET
**Post Topics**: Based on folder names - API Management, Azure services, testing patterns, DevOps

## Key Files to Understand
- `config.toml` - Site configuration and theme parameters
- `azure-pipelines.yml` - CI/CD pipeline definition  
- `archetypes/default.md` - Post template structure
- `themes/mediumish/README.md` - Theme documentation and customization options

When creating content, always use page bundles (`index.md` + assets in same folder) and ensure cover images follow the naming convention for proper theme integration.
