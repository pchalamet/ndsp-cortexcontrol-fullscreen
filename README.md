# Cortex Control native-fullscreen patch

This directory contains a repeatable patch for Neural DSP Cortex Control on
macOS. It enables the normal macOS fullscreen behavior that Cortex Control's
JUCE window disables:

- a dedicated fullscreen Space;
- desktop switching with the trackpad or Control-Left/Right;
- the menu bar when the pointer reaches the top;
- Control-Command-F and the green window button to leave fullscreen;
- use of the display area around a MacBook camera housing.

The vendor application is never edited. The script makes a separate
`Cortex Control Patched.app`.

## Tested configuration

This patch has been tested on macOS running on Apple Silicon with Cortex
Control 4.0.1. Other macOS versions, processor architectures, and Cortex
Control releases may behave differently.

## Disclaimer

This is an unofficial modification and is not supported, endorsed, or
warranted in any way by Neural DSP or Apple. It is provided as-is, without any
guarantee of functionality, compatibility, or safety. Use it entirely at your
own risk. The authors and contributors accept no responsibility for data loss,
instability, application or device malfunction, or any other issue resulting
from its use.

## After installing a Cortex Control update

Quit both copies of Cortex Control, then run:

```sh
~/src/neuraldsp/apply-cortex-fullscreen.sh
```

The defaults are:

```text
Source: /Applications/Neural DSP/Cortex Control.app
Result: /Applications/Neural DSP/Cortex Control Patched.app
```

If an older patched copy exists, the script moves it to a timestamped backup
beside the app before installing the new copy.

Custom locations can be supplied as the first and second arguments:

```sh
~/src/neuraldsp/apply-cortex-fullscreen.sh \
  "/path/to/Cortex Control.app" \
  "/path/to/Cortex Control Patched.app"
```

The first run creates a local Python virtual environment and installs LIEF,
which is used to add the shim library to both slices of the Mach-O executable.
Xcode or the Xcode Command Line Tools must be installed.

## What the patch changes

1. Copies the original application.
2. Builds `NativeFullscreenShim.m` as a universal dynamic library.
3. Adds an `LC_LOAD_DYLIB` command to the copied executable.
4. Enables native fullscreen on the JUCE `NSWindow` and removes its conflicting
   `FullScreenNone` and `FullScreenDisallowsTiling` behavior flags.
5. Adds `NSPrefersDisplaySafeAreaCompatibilityMode = false`.
6. Gives the copy a separate bundle identifier and display name.
7. Ad-hoc signs the result while preserving the original entitlements.

Because this is a binary modification, re-run the patch after every Cortex
Control update. If Neural DSP changes framework, signing, or executable layout,
review the script before forcing it.

While Cortex Control is fullscreen, Escape is forwarded through JUCE's special
key handler and then withheld from AppKit. Cortex still receives the key, but
macOS does not use the same event to leave the fullscreen Space.

## Signing and another Mac

The patch uses:

```sh
codesign --sign -
```

The `-` means **ad-hoc signing**. It does not use a Developer ID certificate,
Apple account, private key, or any identity from your Keychain.

The resulting application and shim are universal (`arm64` and `x86_64` when
the vendor executable contains both), so the patched app can be copied to
another compatible Mac. The other Mac may quarantine the modified app because
it is not vendor-notarized. The most reliable option is to copy this directory
and run the patch there against a freshly installed official Cortex Control.

If copying the already-patched app, place it in `/Applications/Neural DSP/`,
then, only if macOS quarantined that copy, run:

```sh
xattr -dr com.apple.quarantine \
  "/Applications/Neural DSP/Cortex Control Patched.app"
codesign --verify --deep --strict --verbose=2 \
  "/Applications/Neural DSP/Cortex Control Patched.app"
```

Do not remove quarantine from unrelated software.
