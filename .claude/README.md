# Claude Configuration Directory

This directory contains configuration files and workflows for Claude AI assistant, similar to `.windsurf` for Windsurf.

## Structure

```
.claude/
├── rules/           # Development guidelines and best practices
│   ├── global.md           # Global coding standards
│   ├── go-dev.md          # Go-specific guidelines
│   ├── rust-dev.md        # Rust-specific guidelines
│   ├── zig-dev.md         # Zig-specific guidelines
│   ├── project-rules.md   # Project-specific rules for compare-rust-go-zig
│   └── project-structure.md # Project structure and patterns
└── workflows/       # Claude workflows (if needed)
```

## Usage

These files provide context and guidelines for Claude when working on the compare-rust-go-zig project. They ensure consistency across all language implementations and maintain the project's high standards.

### Key Files

- **project-rules.md**: Mandatory checklist and standards for all new projects
- **project-structure.md**: Directory layout, Docker standards, and benchmark patterns
- **go-dev.md/rust-dev.md/zig-dev.md**: Language-specific best practices
- **global.md**: General coding principles applicable to all languages

## Integration with Claude

Claude automatically loads these files as memories to provide context-aware assistance when working on this project. The guidelines ensure:

1. Consistent project structure across all implementations
2. Proper Docker-based benchmarking
3. Standardized statistics output format
4. Language-specific best practices
5. Common patterns and gotchas avoidance

## Maintenance

Keep these files updated when:
- New project patterns emerge
- Language best practices evolve
- New common issues are discovered
- Docker or tooling requirements change
