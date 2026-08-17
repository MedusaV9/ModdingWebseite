# SoooDreamy 4.2.0 build record

- Source commit: `f864e550`
- Farm run: <https://github.com/MedusaV9/ModdingWebseite/actions/runs/31500025128>
- Conclusion: `success`
- Canonical IPA: `../SoooDreamy-4.2.0-unsigned.ipa`
- Embedded version/build: `4.2.0 (28)`
- Server tests: `246/246`
- Swift logic tests: `181/181`

Build recipe: XcodeGen, Release configuration, `iphoneos`, and
`CODE_SIGNING_ALLOWED=NO`; package `SoooDreamy.app` under `Payload/` and zip it.
The farm's quoted-version filename fallback was corrected during finalization;
the embedded plist was verified before the original 4.0.0 artifact was restored.
