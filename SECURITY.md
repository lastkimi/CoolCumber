# Security Policy

## Supported versions

Only the latest published CoolCumber release receives security updates. Beta
builds are provided for evaluation and should not be deployed on shared or
production-critical Macs.

## Reporting a vulnerability

Please report suspected vulnerabilities privately to hi@slmcamp.com. Include
the CoolCumber version, macOS version, hardware model, reproduction steps, and
the security impact. Do not include API keys, passwords, or unrelated personal
files.

We aim to acknowledge reports within three business days. Please allow time for
a fix and coordinated release before publishing exploit details.

## Release integrity

Official direct-download builds are expected to be signed with the SLMCamp
Developer ID, notarized by Apple, and distributed through the CoolCumber GitHub
Releases page. The Mac App Store edition is distributed only by Apple. Do not
install binaries obtained from third-party mirrors.

Direct 1.2 and later communicate only with the
`com.slmcamp.CoolCumber.helper.v2` service. Its XPC surface contains two
bounded, read-only SMC operations (temperature and fan-speed reads), validates
the app's Developer ID requirement and Team ID, and accepts only the active
console user. The app retires an enabled pre-v2 helper as a security migration;
installing the new v2 helper still requires an explicit user action.

## Removing a pre-v2 helper

If CoolCumber reports **Legacy Helper Manual Removal Required**, it found a
pre-v2 root-owned file that cannot be safely claimed by the current app. Quit
CoolCumber, then remove only the exact legacy files that exist on the Mac:

```bash
sudo launchctl bootout system /Library/LaunchDaemons/com.coolcumber.helper.plist
sudo launchctl bootout system /Library/LaunchDaemons/com.coolcumber.helper-fallback.plist
sudo rm -f /Library/LaunchDaemons/com.coolcumber.helper.plist
sudo rm -f /Library/LaunchDaemons/com.coolcumber.helper-fallback.plist
sudo rm -f /Library/PrivilegedHelperTools/com.coolcumber.helper
```

Do not change similarly named third-party files. Restart the Mac, reopen
CoolCumber, confirm that the warning is gone, and only then approve the new v2
read-only helper if the extra hardware readings are wanted.

Beta Preview access is not a permanent license. Direct Beta builds contain a
fixed preview window of at most 45 days and fail closed to Free if that window
is absent, malformed, not yet active, or expired.
