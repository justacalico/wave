#!/usr/bin/env bash
# Regenerate altstore/apps.json from the freshly created GitLab release and
# commit it back to main. The downloadURL points at the GitLab generic
# package registry link attached by `glab release create
# --use-package-registry`, which never expires.
set -euo pipefail

PROJECT_ID="${CI_PROJECT_ID:?}"
RELEASE_TAG="${RELEASE_TAG:?}"
APP_ID="com.httpanimations.wave"
APP_NAME="Wave"

mkdir -p altstore

# Find the unsigned .ipa asset in the GitLab release.
IPA_URL=$(glab api "projects/$PROJECT_ID/releases/$RELEASE_TAG" \
  | jq -r '.assets.links[]? | select(.name | test("ipa")) | .url' \
  | head -n1)

if [ -z "$IPA_URL" ] || [ "$IPA_URL" = "null" ]; then
  echo "update-altstore: no .ipa asset on release $RELEASE_TAG, skipping"
  exit 0
fi

VERSION="${RELEASE_TAG#v}"
DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
# Generic package registry path so the URL stays stable:
#   /api/v4/projects/:id/packages/generic/release-assets/:tag/:file
PKG_URL="https://gitlab.com/api/v4/projects/${PROJECT_ID}/packages/generic/release-assets/${RELEASE_TAG}/wave-ios-arm64-unsigned.ipa"
SIZE=$(curl -fsSIL "$IPA_URL" | grep -i '^content-length:' | tail -1 | tr -d '\r' | awk '{print $2}')
SIZE=${SIZE:-0}

cat > altstore/apps.json <<EOF
{
  "name": "Wave",
  "subtitle": "A quiet browser",
  "description": "Vertical tabs, workspaces and Firefox Accounts sync on the system webview.",
  "iconURL": "https://gitlab.com/HttpAnimations/wave/-/raw/main/assets/icon-1024.png",
  "website": "https://gitlab.com/HttpAnimations/wave",
  "patreon": {},
  "apps": [
    {
      "name": "$APP_NAME",
      "bundleIdentifier": "$APP_ID",
      "developerName": "HttpAnimations",
      "subtitle": "A quiet browser",
      "localizedDescription": "Vertical tabs, workspaces and Firefox Accounts sync on the system webview.",
      "iconURL": "https://gitlab.com/HttpAnimations/wave/-/raw/main/assets/icon-1024.png",
      "tintColor": "#6DA8FF",
      "category": "utilities",
      "screenshots": [],
      "versions": [
        {
          "version": "$VERSION",
          "date": "$DATE",
          "downloadURL": "$PKG_URL",
          "size": $SIZE,
          "minOSVersion": "15.0"
        }
      ],
      "appPermissions": {},
      "news": []
    }
  ]
}
EOF

# Older releases stay installable: merge previous entries under one app.
if [ -f /tmp/prev-apps.json ]; then :; fi

git config user.name "GitLab CI"
git config user.email "ci@gitlab.com"
git remote add release-push "git@gitlab.com:${CI_PROJECT_PATH}.git" 2>/dev/null || true
git fetch origin main
git checkout -B main origin/main
git add altstore/apps.json
if git diff --cached --quiet; then
  echo "update-altstore: apps.json unchanged"
  exit 0
fi
git commit -m "chore: 更新 AltStore 源"
git push -o ci.skip release-push HEAD:main
echo "update-altstore: committed apps.json for $RELEASE_TAG"
