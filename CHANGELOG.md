# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2024-07-28

### Added
- 🎉 Initial release of Universal Makefile System
- 🔧 Modular Makefile structure with feature-specific modules
- 🐳 Complete Docker and Docker Compose integration
- 🌿 Git Flow automation with release management
- 📋 Automatic help system with categorized targets
- 🔄 Two installation methods: Git Submodule and Script installation
- 🎨 Project-specific customization via project.mk
- 🌍 Multi-environment support (development/staging/production)
- 🧹 Comprehensive cleanup system with language-specific support
- 📊 Version management with automatic bumping
- 🔒 Security features and best practices
- 📖 Complete documentation and templates

### Modules Included
- **core.mk**: Core functions and variables
- **help.mk**: Advanced help system with categorization
- **docker.mk**: Docker build, push, and management
- **compose.mk**: Docker Compose operations
- **git-flow.mk**: Git workflow automation (includes all original features)
- **version.mk**: Version management and semantic versioning
- **cleanup.mk**: Cleanup operations and maintenance

### Templates Provided
- **project.mk.template**: Project configuration template
- **.gitignore.template**: Comprehensive gitignore template
- **docker-compose.yml.template**: Full-featured Docker Compose template

### Original Features Preserved
- ✅ `bump-version` - Git tag-based automatic version increment
- ✅ `create-release-branch` - Release branch creation with auto-versioning
- ✅ `push-release-branch` - Push release branch to remote
- ✅ `finish-release` - Complete release process (merge, tag, GitHub release)
- ✅ `auto-release` - Fully automated release workflow
- ✅ `list-old-branches` - List merged release branches
- ✅ `clean-old-branches` - Clean up old release branches
- ✅ `sync-develop` - Branch synchronization
- ✅ All Docker build and deployment features
- ✅ Color output and logging system

### Language Support
- 📦 Node.js (npm, yarn)
- 🐍 Python (poetry, pip)
- 🦀 Rust (cargo)
- 🔷 Go (go modules)
- ☕ Java (maven, gradle)
- 🐘 PHP (composer)
- 💎 Ruby (bundler)
- 🐳 Generic Docker-based projects

### Installation Methods
- Git Submodule (recommended for centralized updates)
- Script installation (for standalone projects)
- Automatic detection and setup
- Existing project integration support

[Unreleased]: https://github.com/company/universal-makefile/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/company/universal-makefile/releases/tag/v1.0.0