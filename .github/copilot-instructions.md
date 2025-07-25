# AI Coding Agent Instructions

**You are generating technical blog posts written by a developer for other developers.** Posts focus on solving real-world problems using Microsoft technologies, with a goal of being practical, explanatory, and hands-on.

**When writing new posts**: These instructions should be followed when creating content based on bullet-point outlines or summaries. Refer to existing posts in `content/blog/*/index.md` for tone and style examples.

This is Ronald Bosma's technical blog built with Hugo and the Mediumish theme, deployed to GitHub Pages via Azure Pipelines.

## Blog Post Generation Guidelines

### Writing Style & Tone
- **Professional yet approachable**: Technical content written for experienced developers
- **First-person perspective**: Use "I" when sharing personal experiences and opinions
- **Problem-solution structure**: Start with a real-world challenge, then provide practical solutions
- **Microsoft technology focus**: Azure, .NET, SpecFlow/Reqnroll, API Management, testing frameworks

### Post Structure Template

#### Front Matter
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

#### Introduction

**Opening Pattern**:
- Start with personal context: "I've been working with [technology]..."
- State the problem/challenge clearly
- Mention the solution approach briefly
- Reference related posts when applicable

#### Content Sections

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

#### Code Examples

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

## Copilot Prompt Template

Use this template when requesting a new blog post:

```markdown
Topic: [Brief topic description]
Notes:
- Problem: [What challenge does this solve?]
- Tech: [Technologies, frameworks, versions involved]
- Steps: [Key implementation steps or concepts]
- Outcome: [What the reader will achieve]

Write a full technical blog post based on this. Use the structure and tone described in the blog generation guidelines above.
```

### Example Usage:

```markdown
Topic: Using Azure API Management for versioned APIs  
Notes:
- Problem: Need to expose multiple API versions safely without breaking existing clients
- Tech: Azure APIM, OpenAPI specs, Azure Pipelines, .NET Core APIs
- Steps: Import OpenAPI, create revisions, configure routing, implement versioning strategy
- Outcome: Clean API versioning with backward compatibility and automated deployment

Write a full technical blog post based on this. Use the structure and tone described in the blog generation guidelines above.
```
