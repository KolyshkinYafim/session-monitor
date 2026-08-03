#!/usr/bin/env bash
#
# Build SessionMonitor (Release), install to /Applications, start at login.
# Re-runnable. Undo: ./uninstall-app.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="${ROOT}/SessionMonitor/SessionMonitor.xcodeproj"
# Deliberately outside the repo: it lives on an iCloud-synced Desktop, where every file the
# syncer touches picks up a com.apple.FinderInfo xattr, and codesign refuses those with
# "resource fork, Finder information, or similar detritus not allowed". Building into a
# non-synced path is what makes this script's outcome the same every run.
BUILD_DIR="${SM_BUILD_DIR:-${TMPDIR:-/tmp}/SessionMonitor-release}"
APP="${BUILD_DIR}/Build/Products/Release/SessionMonitor.app"
DEST="/Applications/SessionMonitor.app"
PLIST_DST="${HOME}/Library/LaunchAgents/com.agentdesktop.SessionMonitor.plist"

# Build identity: without it every copy reports the same version and nobody can tell whether
# the island running from /Applications is this working tree. stamp-build-identity.sh writes
# the revision during the build; the build number comes from here so it moves with commits.
REVISION="$(git -C "${ROOT}" rev-parse --short HEAD 2>/dev/null || echo unknown)"
BUILD_NUMBER="$(git -C "${ROOT}" rev-list --count HEAD 2>/dev/null || echo 0)"
if [ -n "$(git -C "${ROOT}" status --porcelain 2>/dev/null || true)" ]; then
    REVISION="${REVISION}-dirty"
    echo "WARNING: working tree has uncommitted changes — installing ${REVISION}."
    echo "         The installed app will match no commit; only this tree, as of now."
fi

echo "Building Release (${REVISION})..."
xcodebuild -project "${PROJECT}" -scheme SessionMonitor -configuration Release \
    -destination 'platform=macOS' -derivedDataPath "${BUILD_DIR}" \
    CURRENT_PROJECT_VERSION="${BUILD_NUMBER}" \
    CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build >/dev/null

echo "Installing to ${DEST}..."
pkill -x SessionMonitor 2>/dev/null || true
sleep 1
rm -rf "${DEST}"
cp -R "${APP}" "${DEST}"
# cp -R carries xattrs across, and /Applications is not synced but the copy came from a build
# that may have been: strip before signing, never after.
xattr -cr "${DEST}"

# Sign for real (ad-hoc) rather than leaving the linker's signature: an unsigned bundle fails
# `codesign --verify` and macOS calls it damaged the moment it is zipped or AirDropped.
# Hardened runtime stays off — it only means anything with a Developer ID and notarization.
codesign --force --deep --sign - \
    --entitlements "${ROOT}/SessionMonitor/SessionMonitor/SessionMonitor.entitlements" \
    "${DEST}"
codesign --verify --deep --strict "${DEST}" || echo "WARNING: installed bundle failed codesign --verify"

# Launch at login is the app's own SMAppService login item, driven by Settings › General.
# A LaunchAgent here would start the island no matter what that toggle says, so any plist a
# previous install left behind has to go — otherwise turning the toggle off changes nothing.
if [ -f "${PLIST_DST}" ]; then
    echo "Removing the legacy LaunchAgent (Settings › General owns launch at login now)..."
    launchctl bootout "gui/$(id -u)/com.agentdesktop.SessionMonitor" 2>/dev/null || true
    launchctl unload "${PLIST_DST}" 2>/dev/null || true
    rm -f "${PLIST_DST}"
fi
# Seed the preference only when the user has never expressed one: the app registers the login
# item from this key on first launch, and overwriting a deliberate "off" would be rude.
if ! defaults read com.agentdesktop.SessionMonitor general.launchAtLogin >/dev/null 2>&1; then
    defaults write com.agentdesktop.SessionMonitor general.launchAtLogin -bool true
fi

open "${DEST}"
IDENTITY="${DEST}/Contents/Resources/BuildIdentity.plist"
INSTALLED_REV="$(/usr/libexec/PlistBuddy -c 'Print :SMBuildRevision' "${IDENTITY}" 2>/dev/null || echo unknown)"
echo "Installed ${INSTALLED_REV} and started. Launch at login: Settings › General."
echo "  Verify what is running:  /usr/libexec/PlistBuddy -c 'Print :SMBuildRevision' '${IDENTITY}'"
echo "  Undo: ${ROOT}/packaging/uninstall-app.sh"
