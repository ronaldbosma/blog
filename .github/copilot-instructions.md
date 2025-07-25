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

## Blog Post Generation Guidelines

### Writing Style & Tone
- **Professional yet approachable**: Technical content written for experienced developers
- **First-person perspective**: Use "I" when sharing personal experiences and opinions
- **Problem-solution structure**: Start with a real-world challenge, then provide practical solutions
- **Microsoft technology focus**: Azure, .NET, SpecFlow/Reqnroll, API Management, testing frameworks

### Post Structure Template

**Front Matter**:
```yaml
---
title: "[Descriptive Title with Action Words]"
date: {{ current date in ISO format with timezone }}
publishdate: {{ same as date }}
lastmod: {{ same as date }}
tags: [ "Primary Tech", "Secondary Tech", "Category", "Methodology" ]
summary: "Single paragraph (2-3 sentences) explaining the problem and solution overview."
draft: true
---
```

**Opening Pattern**:
- Start with personal context: "I've been working with [technology]..."
- State the problem/challenge clearly
- Mention the solution approach briefly
- Reference related posts when applicable

**Content Structure**:
1. **Table of Contents** (using `### Table of Contents` heading)
   - Always include for posts with multiple sections
   - Use lowercase anchors with hyphens: `#section-name`

2. **Introduction/Prerequisites** sections when needed
   - Installation commands in PowerShell format
   - Prerequisites clearly listed
   - Links to official documentation

3. **Step-by-step progression**
   - Each major concept gets its own H3 section (`###`)
   - Build complexity gradually
   - Show working examples first, then explain the theory

4. **Code Examples**:
   - Use proper language tags in fenced code blocks
   - Include practical, runnable examples
   - Show both "before" and "after" code when refactoring
   - Explain non-obvious parts after code blocks

5. **Conclusion**:
   - Summarize key benefits
   - Mention areas for improvement or future exploration
   - Link to related resources or next steps

### Content Patterns

**Code Block Guidelines**:
- Always specify language: `csharp`, `bicep`, `powershell`, `gherkin`, `yaml`, `xml`
- Include context comments when helpful
- Show complete, working examples rather than fragments
- Use descriptive variable/method names

**Technical Explanations**:
- Explain the "why" before the "how"
- Include Microsoft documentation links for official features
- Reference version numbers for frameworks/tools
- Mention limitations and alternative approaches

**Image References**:
- Reference images relative to post folder: `../../../../../images/[post-name]/image.png`
- Use descriptive alt text
- Include diagrams for architectural concepts

### Common Elements

**Technology References**:
- Link to official documentation on first mention
- Use proper capitalization: "SpecFlow", "Reqnroll", "API Management", "Azure Pipelines"
- Include version numbers when relevant: "PSRule version 2.9.0"

**Step Patterns**:
- "Let's start with..." for first examples
- "Next, we'll..." for progression
- "Here's how..." for explanations
- "As you can see..." for code analysis

**Transition Phrases**:
- "Based on [reference]..." when citing sources
- "In this section, we'll explore..." for new topics
- "While [approach A] works, [approach B]..." for comparisons
- "That being said..." for caveats or limitations

### Example Generation Workflow

When provided with bullet points or notes, follow this process:

1. **Analyze the topic** - Identify primary technology, use case, and target audience
2. **Structure the content** - Create logical progression from problem to solution
3. **Generate front matter** - Include relevant tags and compelling summary
4. **Write introduction** - Personal context + problem statement
5. **Create table of contents** - Map out the learning journey
6. **Develop sections** - Each major concept with examples and explanations
7. **Add code examples** - Working, practical implementations
8. **Write conclusion** - Benefits, limitations, next steps

### Quality Checklist
- [ ] Front matter complete with appropriate tags
- [ ] Table of contents matches actual sections
- [ ] Code blocks have language specifications
- [ ] Personal voice and experience included
- [ ] Progressive complexity (simple → advanced)
- [ ] External links to official documentation
- [ ] Practical, working examples
- [ ] Clear problem-solution narrative
- [ ] Conclusion ties back to opening problem
