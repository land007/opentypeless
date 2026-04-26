#!/bin/bash
# Build ARM64 package and upload to GitHub Release
# Usage: GITHUB_TOKEN=xxx ./scripts/build-and-upload-arm64.sh v0.1.25

set -e

VERSION="${1:-$(git describe --tags --abbrev=0)}"
REPO="land007/opentypeless"

echo "Building OpenTypeless ${VERSION} for ARM64..."

ARCH="$(uname -m)"
if [ "$ARCH" != "aarch64" ] && [ "$ARCH" != "arm64" ]; then
    echo "This script must run on an ARM64 Linux machine."
    echo "Cross-compiling Tauri's GTK/WebKit stack requires a target sysroot and pkg-config wrapper."
    echo "Use the release workflow's ubuntu-24.04-arm runner for automated ARM64 packages."
    exit 1
fi

# Install dependencies if needed
sudo apt-get update -qq
sudo apt-get install -y -qq libwebkit2gtk-4.1-dev libappindicator3-dev librsvg2-dev patchelf libasound2-dev libxdo-dev

# Install npm deps
npm ci

# Build for ARM64
npm run tauri build

# Find built files
DEB_FILE="src-tauri/target/release/bundle/deb"/*.deb
APPIMAGE_FILE="src-tauri/target/release/bundle/appimage"/*.AppImage

echo "Built files:"
ls -lh "$DEB_FILE" "$APPIMAGE_FILE"

# Upload to GitHub Release
echo "Uploading to GitHub Release..."

# Create or get release
RELEASE_RESPONSE=$(curl -s -X GET \
  -H "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/$REPO/releases/tags/$VERSION")

RELEASE_ID=$(echo "$RELEASE_RESPONSE" | grep -o '"id": [0-9]*' | head -1 | grep -o '[0-9]*')

if [ -z "$RELEASE_ID" ]; then
    echo "Creating release $VERSION..."
    RELEASE_RESPONSE=$(curl -s -X POST \
      -H "Authorization: token $GITHUB_TOKEN" \
      -H "Accept: application/vnd.github.v3+json" \
      "https://api.github.com/repos/$REPO/releases" \
      -d "{\"tag_name\":\"$VERSION\",\"name\":\"OpenTypeless $VERSION\",\"draft\":true}")
    RELEASE_ID=$(echo "$RELEASE_RESPONSE" | grep -o '"id": [0-9]*' | head -1 | grep -o '[0-9]*')
    UPLOAD_URL=$(echo "$RELEASE_RESPONSE" | grep -o '"upload_url":"[^"]*' | cut -d'"' -f4 | sed 's/{?name,label}//')
else
    echo "Release $VERSION exists (ID: $RELEASE_ID)"
    UPLOAD_URL=$(echo "$RELEASE_RESPONSE" | grep -o '"upload_url":"[^"]*' | cut -d'"' -f4 | sed 's/{?name,label}//')
fi

# Upload deb file
echo "Uploading $(basename "$DEB_FILE")..."
curl -s -X POST \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Content-Type: application/vnd.debian.binary-package" \
  --data-binary @"$DEB_FILE" \
  "$UPLOAD_URL?name=$(basename "$DEB_FILE")"

# Upload AppImage file
echo "Uploading $(basename "$APPIMAGE_FILE")..."
curl -s -X POST \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Content-Type: application/octet-stream" \
  --data-binary @"$APPIMAGE_FILE" \
  "$UPLOAD_URL?name=$(basename "$APPIMAGE_FILE")"

echo ""
echo "✅ Done! Files uploaded to release $VERSION"
echo "https://github.com/$REPO/releases/$VERSION"
