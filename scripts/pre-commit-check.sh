#!/bin/bash
# Pre-commit hook: scan staged files for secrets, PII, and API keys
# Install: cp scripts/pre-commit-check.sh .git/hooks/pre-commit

set -e

EXCLUDE_PATTERNS="\.env\.template|CLAUDE\.md|pre-commit-check\.sh|docs/|test_fixtures/"

STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep -vE "$EXCLUDE_PATTERNS" || true)

if [ -z "$STAGED_FILES" ]; then
    exit 0
fi

ERRORS=0

for FILE in $STAGED_FILES; do
    # Skip binary files
    if file "$FILE" | grep -q "binary"; then
        continue
    fi

    # Check for .env files (not .env.template)
    if echo "$FILE" | grep -qE '\.env$'; then
        echo "ERROR: Staging .env file: $FILE"
        ERRORS=$((ERRORS + 1))
        continue
    fi

    CONTENT=$(git show ":$FILE" 2>/dev/null || true)
    if [ -z "$CONTENT" ]; then
        continue
    fi

    # API key patterns: sk-, pk-, key- followed by 20+ alphanumeric chars
    MATCHES=$(echo "$CONTENT" | grep -nE '(sk-|pk-|key-)[A-Za-z0-9]{20,}' || true)
    if [ -n "$MATCHES" ]; then
        echo "$MATCHES" | head -5
        echo "  ^ Possible API key in: $FILE"
        ERRORS=$((ERRORS + 1))
    fi

    # Secret assignments with values
    MATCHES=$(echo "$CONTENT" | grep -nE "(password|secret|token)\s*=\s*[\"'][^\s\"']{8,}" || true)
    if [ -n "$MATCHES" ]; then
        echo "$MATCHES" | head -5
        echo "  ^ Possible secret assignment in: $FILE"
        ERRORS=$((ERRORS + 1))
    fi

    # Hardcoded auth URL parameters
    MATCHES=$(echo "$CONTENT" | grep -nE '\?(token|key|api_key|apikey)=[A-Za-z0-9]' || true)
    if [ -n "$MATCHES" ]; then
        echo "$MATCHES" | head -5
        echo "  ^ Possible hardcoded auth URL in: $FILE"
        ERRORS=$((ERRORS + 1))
    fi

    # Email addresses (simple pattern)
    MATCHES=$(echo "$CONTENT" | grep -nE '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' | grep -vE '(noreply|example\.com|test@|\.xyz)' || true)
    if [ -n "$MATCHES" ]; then
        echo "$MATCHES" | head -5
        echo "  ^ Possible email address in: $FILE"
        ERRORS=$((ERRORS + 1))
    fi

    # Private IP addresses
    MATCHES=$(echo "$CONTENT" | grep -nE '\b(10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3}|192\.168\.[0-9]{1,3}\.[0-9]{1,3})\b' || true)
    if [ -n "$MATCHES" ]; then
        echo "$MATCHES" | head -5
        echo "  ^ Possible private IP in: $FILE"
        ERRORS=$((ERRORS + 1))
    fi
done

if [ $ERRORS -gt 0 ]; then
    echo ""
    echo "Pre-commit check failed: $ERRORS potential issue(s) found."
    echo "Review the above warnings. To bypass (if safe): git commit --no-verify"
    exit 1
fi

exit 0
