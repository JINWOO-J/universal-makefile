#!/bin/bash

# Color output functions
colorecho() {
    printf "%b%s%b\n" "\033[0;34m" "$1" "\033[0m"
}

success() {
    printf "%b%s%b\n" "\033[0;32m" "$1" "\033[0m"
}

error() {
    printf "%b%s%b\n" "\033[0;31m" "$1" "\033[0m"
    exit 1
}

# Git repository check
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    error "Not in a git repository. Please run 'git init' first."
fi

# Check develop branch
if ! git rev-parse --verify develop > /dev/null 2>&1; then
    colorecho "Develop branch not found. Creating develop branch..."
    # Create develop branch from current state or main/master
    if git rev-parse --verify main > /dev/null 2>&1; then
        git checkout -b develop main
    elif git rev-parse --verify master > /dev/null 2>&1; then
        git checkout -b develop master
    else
        git checkout -b develop
        git add .
        git commit -m "Initial commit" || true
    fi
fi

# Version determination
if [ -n "$NEW_VERSION" ]; then
    colorecho "Using version from NEW_VERSION: $NEW_VERSION"
    RELEASE_VERSION="$NEW_VERSION"
elif [ -f .NEW_VERSION.tmp ]; then
    RELEASE_VERSION=$(cat .NEW_VERSION.tmp)
    colorecho "Using version from .NEW_VERSION.tmp: $RELEASE_VERSION"
else
    error "NEW_VERSION is not set and .NEW_VERSION.tmp not found"
fi

colorecho "🌿 Creating release branch..."
colorecho "Using version: $RELEASE_VERSION"

RELEASE_BRANCH="release/$RELEASE_VERSION"

# Make sure we're on develop branch first
git checkout develop || error "Failed to checkout develop branch"

# Check if branch exists
if git rev-parse --verify "$RELEASE_BRANCH" >/dev/null 2>&1; then
    colorecho "Release branch '$RELEASE_BRANCH' already exists. Removing for idempotency..."
    git branch -D "$RELEASE_BRANCH"
fi

colorecho "Creating new release branch '$RELEASE_BRANCH' from 'develop'..."
if git checkout -b "$RELEASE_BRANCH"; then
    success "Successfully created and switched to '$RELEASE_BRANCH'"
else
    error "Failed to create release branch"
fi
