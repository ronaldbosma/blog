---
applyTo: "content/blog/**/index.md"
---

# Blog Post Quality Checks

These quality checks should be performed when writing and reviewing blog posts to ensure consistency, accuracy, and adherence to the established writing style and standards.

## Quality Checklist
- [ ] Front matter complete with appropriate tags
- [ ] Table of contents matches actual sections
- [ ] Code blocks have language specifications
- [ ] Personal voice and experience included
- [ ] Progressive complexity (simple → advanced)
- [ ] External links to official documentation
- [ ] Practical, working examples
- [ ] Clear problem-solution narrative
- [ ] Conclusion ties back to opening problem
- [ ] No Oxford commas used (A, B and C format)
- [ ] Minimal use of bold text in paragraphs
- [ ] Neutral descriptive language instead of emphasis words like "important" or "critical"
- [ ] Raw prompt typos and shorthand normalized without changing technical intent
- [ ] Tool and framework names are spelled and capitalized correctly
- [ ] Time-sensitive claims (versions, release dates and current limitations) are verified or clearly qualified

## Enforcement
- The final output MUST explicitly include a completed checklist section confirming each quality check item.
- Use this exact section heading in the final output: `## QUALITY CHECK RESULT`.
- The section MUST contain all checklist items from `## Quality Checklist`, each marked as either `- [x]` (completed) or `- [ ]` (not completed).
- Do not omit checklist items. If an item cannot be completed, leave it unchecked and briefly explain why.

## Quality Standards
- Technical accuracy is paramount - verify all code examples and links
- Ensure all examples are practical and runnable
- Double-check Microsoft technology references and version numbers
- Distinguish verified facts from assumptions when source material is incomplete