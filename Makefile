SHELL:=/bin/bash
.SHELLFLAGS:=-o pipefail -c
SCHEME=Stasks
BUILD_DIR=build
APP=$(BUILD_DIR)/Build/Products/Release/Stasks.app
VERSION=$(shell sed -n 's/.*MARKETING_VERSION: "\(.*\)"/\1/p' project.yml)
ARCHIVE=$(BUILD_DIR)/Stasks.xcarchive
EXPORT=$(BUILD_DIR)/export
DMG=$(BUILD_DIR)/Stasks-$(VERSION).dmg
# Notarization credentials: either a keychain profile (local, `xcrun notarytool store-credentials notary`)
# or explicit App Store Connect API key vars (CI): NOTARY_KEY (path to .p8), NOTARY_KEY_ID, NOTARY_ISSUER.
NOTARY_PROFILE=notary
SIGN_IDENTITY=Developer ID Application
NOTARY_ARGS=$(if $(NOTARY_KEY),--key "$(NOTARY_KEY)" --key-id "$(NOTARY_KEY_ID)" --issuer "$(NOTARY_ISSUER)",--keychain-profile "$(NOTARY_PROFILE)")

.PHONY: gen build test-core test-hooks test run install clean archive export dmg notarize release

gen:
	xcodegen generate

build: gen
	xcodebuild -project Stasks.xcodeproj -scheme $(SCHEME) -configuration Release -derivedDataPath $(BUILD_DIR) build | tail -5

test-core:
	cd StasksCore && swift test

test-hooks:
	bash hooks/test-hook.sh

test: test-core test-hooks

run: build
	pkill -x Stasks || true
	open $(APP)

install: build
	pkill -x Stasks || true
	rm -rf /Applications/Stasks.app
	cp -R $(APP) /Applications/Stasks.app
	open /Applications/Stasks.app

# Release pipeline: archive -> export signed with Developer ID -> dmg -> notarize + staple.
# The archive signs manually with $(SIGN_IDENTITY): dev builds use "Apple Development" (project.yml), which
# CI does not have.
# `make release` produces $(DMG), ready to attach to a GitHub release.
archive: gen
	xcodebuild -project Stasks.xcodeproj -scheme $(SCHEME) -configuration Release \
		-derivedDataPath $(BUILD_DIR) -archivePath $(ARCHIVE) \
		CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$(SIGN_IDENTITY)" archive | tail -5

export: archive
	rm -rf $(EXPORT)
	xcodebuild -exportArchive -archivePath $(ARCHIVE) -exportOptionsPlist ExportOptions.plist -exportPath $(EXPORT) | tail -5
	codesign --verify --deep --strict --verbose=2 $(EXPORT)/Stasks.app
	@test -f $(EXPORT)/Stasks.app/Contents/Resources/AppIcon.icns || { echo "AppIcon.icns missing: AppIcon.icon needs Xcode 26+ to compile"; exit 1; }

dmg: export
	rm -rf $(BUILD_DIR)/dmg $(DMG)
	mkdir -p $(BUILD_DIR)/dmg
	cp -R $(EXPORT)/Stasks.app $(BUILD_DIR)/dmg/
	ln -s /Applications $(BUILD_DIR)/dmg/Applications
	hdiutil create -volname "Stasks $(VERSION)" -srcfolder $(BUILD_DIR)/dmg -ov -format UDZO $(DMG)
	codesign --sign "$(SIGN_IDENTITY)" --timestamp $(DMG)

notarize: dmg
	xcrun notarytool submit $(DMG) $(NOTARY_ARGS) --wait
	xcrun stapler staple $(DMG)
	spctl -a -t open --context context:primary-signature -v $(DMG)

release: notarize
	@echo "Release artifact: $(DMG)"

clean:
	rm -rf $(BUILD_DIR) StasksCore/.build
