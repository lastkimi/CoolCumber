# CoolCumber source and tool notice

CoolCumber is developed and published by Hangzhou Inkblaze AI Technology Co.,
Ltd. “SLMCamp” is a product and studio brand used by the company; it is not a
different copyright owner.

The CoolCumber 1.2 build-4 candidate source tree links only Apple system
frameworks and the in-repository `ThermFlowCore` package. It does not embed a
third-party analytics SDK, advertising SDK, or third-party runtime framework.

## Build-time tool

The repository uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) to
generate the local Xcode project. XcodeGen is a developer build tool and is not
linked into or distributed inside the CoolCumber application.

## Removed historical reference

An earlier, optional screen-positioned SmartBar used display-cutout detection
adapted from ideas in
[SuperIsland](https://github.com/shobhit99/SuperIsland). CoolCumber 1.2.0 build
4 removes the SmartBar, its screen-positioned overlay, and all of that
display-cutout geometry from both Direct and Mac App Store targets. Binaries
built from the build-4 candidate source do not contain SuperIsland code or
assets.

This notice records provenance; it does not add SuperIsland as a dependency or
claim that the current CoolCumber source is derived from that removed routine.
