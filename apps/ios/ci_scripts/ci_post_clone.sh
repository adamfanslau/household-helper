#!/bin/sh
# Xcode Cloud: materialise the git-ignored Firebase config and per-project build values.
# Secret env vars (App Store Connect -> Xcode Cloud -> workflow -> Environment):
#   GOOGLE_SERVICE_INFO_PLIST_B64  base64 of GoogleService-Info.plist (secret)
#   HH_TEAM_ID                     Apple Developer team id
set -eu
IOS="$CI_PRIMARY_REPOSITORY_PATH/apps/ios"
printf '%s' "$GOOGLE_SERVICE_INFO_PLIST_B64" | base64 -d > "$IOS/HouseholdHelper/GoogleService-Info.plist"
REVERSED=$(/usr/libexec/PlistBuddy -c 'Print :REVERSED_CLIENT_ID' "$IOS/HouseholdHelper/GoogleService-Info.plist")
{
  echo "HH_GOOGLE_REVERSED_CLIENT_ID = $REVERSED"
  echo "HH_TEAM_ID = ${HH_TEAM_ID:-}"
} > "$IOS/Config/Secrets.xcconfig"
echo "ci_post_clone: wrote GoogleService-Info.plist and Config/Secrets.xcconfig"
