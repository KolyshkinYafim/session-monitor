#!/bin/sh
#
# Xcode build phase: stamp the git identity of the tree that produced this build into the
# bundle. Without it every copy reports the same 0.1.0 (1) and there is no way to tell
# whether the island running from /Applications is the code you are reading.
#
# Writes Resources/BuildIdentity.plist rather than the built Info.plist: Xcode's
# ProcessInfoPlistFile task runs after every build phase, so a script phase stamping
# Info.plist is silently overwritten by the source copy before the build ends.
#
# Never fails the build — an unstamped app just reports "unknown".
set -u

[ -n "${TARGET_BUILD_DIR:-}" ] || exit 0
RESOURCES="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:-}"
PLIST="${RESOURCES}/BuildIdentity.plist"

REPO="${SRCROOT:-.}/.."
REVISION="$(git -C "${REPO}" rev-parse --short HEAD 2>/dev/null || true)"
if [ -n "${REVISION}" ]; then
    # Uncommitted work means the sha alone is a lie about what is in the binary.
    if [ -n "$(git -C "${REPO}" status --porcelain 2>/dev/null || true)" ]; then
        REVISION="${REVISION}-dirty"
    fi
else
    REVISION="unknown"
fi

mkdir -p "${RESOURCES}" || exit 0
cat > "${PLIST}" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>SMBuildRevision</key>
	<string>${REVISION}</string>
	<key>SMBuildDate</key>
	<string>$(date -u '+%Y-%m-%dT%H:%M:%SZ')</string>
</dict>
</plist>
PLISTEOF

exit 0
