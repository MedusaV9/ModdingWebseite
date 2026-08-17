# SoooDreamy 4.1.0 build record

- Source commit: `0c92d6e00d7882deb3fc76cf724b609c5f181c71`
- Farm run: <https://github.com/MedusaV9/ModdingWebseite/actions/runs/31498998618>
- Farm conclusion: `success`
- Canonical IPA: `../SoooDreamy-4.1.0-unsigned.ipa`
- Embedded version/build: `4.1.0 (27)`
- Device signing: disabled; install with a sideload signer

## Rebuild recipe

```bash
brew install xcodegen
swift SoooDreamy/ios/scripts/GenerateIcon.swift \
  SoooDreamy/ios/SoooDreamy/Resources/Assets.xcassets/AppIcon.appiconset/icon_1024.png classic
cd SoooDreamy/ios
xcodegen generate
xcodebuild \
  -project SoooDreamy.xcodeproj \
  -scheme SoooDreamy \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  DEVELOPMENT_TEAM="" \
  build
mkdir -p dist/Payload
cp -R build/Build/Products/Release-iphoneos/SoooDreamy.app dist/Payload/
(cd dist && zip -qry SoooDreamy-4.1.0-unsigned.ipa Payload)
```

The farm script in run `31498998618` misread the quoted YAML version and initially
committed this verified 4.1.0 binary under the 4.0.0 filename. Release finalization
copied the binary to its canonical 4.1.0 path and restored the original 4.0.0/26 base.
Both embedded versions were then checked directly from each IPA's `Info.plist`.
