# Builds Rook.app from the SwiftPM package.
#
# Signing matters: macOS ties the Accessibility grant to the code signature.
# Ad-hoc signing ("-") changes every build and forces you to re-grant access,
# so we use the first "Apple Development" identity in the keychain by default.
# Override with: make run SIGN_IDENTITY="Developer ID Application: ..."

CONFIG        ?= release
APP           := build/Rook.app
BIN           := .build/$(CONFIG)/Rook
SIGN_IDENTITY ?= $(shell security find-identity -v -p codesigning 2>/dev/null | grep -m1 "Apple Development" | sed -E 's/.*"(.*)"/\1/')
SIGN          := $(if $(SIGN_IDENTITY),$(SIGN_IDENTITY),-)

.PHONY: build bundle run stop install test clean release notarize

build:
	swift build -c $(CONFIG) --product Rook

bundle: build
	@rm -rf $(APP)
	@mkdir -p $(APP)/Contents/MacOS
	@cp $(BIN) $(APP)/Contents/MacOS/Rook
	@cp Resources/Info.plist $(APP)/Contents/Info.plist
	codesign --force --options runtime --sign "$(SIGN)" $(APP)
	@echo "Built $(APP) (signed with: $(SIGN))"

stop:
	@pkill -x Rook || true

run: bundle stop
	open $(APP)

install: bundle stop
	rm -rf /Applications/Rook.app
	cp -R $(APP) /Applications/Rook.app
	open /Applications/Rook.app

test:
	swift test

clean:
	rm -rf .build build

# --- Release: universal, Developer ID signed, notarized -----------------------
#
# One-time setup, stores an app-specific password in the keychain:
#   xcrun notarytool store-credentials rook --apple-id <you> --team-id <TEAM>
#
#   make release    universal build signed with Developer ID -> build/Rook-<version>.zip
#   make notarize   release + notarize + staple, then prints the cask sha256

VERSION          := $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
RELEASE_IDENTITY ?= $(shell security find-identity -v -p codesigning 2>/dev/null | grep -m1 "Developer ID Application" | sed -E 's/.*"(.*)"/\1/')
NOTARY_PROFILE   ?= rook
RELEASE_DIR      := build/release
RELEASE_APP      := $(RELEASE_DIR)/Rook.app
RELEASE_ZIP      := build/Rook-$(VERSION).zip
UNIVERSAL        := swift build -c release --arch arm64 --arch x86_64 --product Rook

release:
	@test -n "$(RELEASE_IDENTITY)" || { echo "No Developer ID Application identity found"; exit 1; }
	$(UNIVERSAL)
	@rm -rf $(RELEASE_DIR) && mkdir -p $(RELEASE_APP)/Contents/MacOS
	@cp "$$($(UNIVERSAL) --show-bin-path)/Rook" $(RELEASE_APP)/Contents/MacOS/Rook
	@cp Resources/Info.plist $(RELEASE_APP)/Contents/Info.plist
	codesign --force --timestamp --options runtime --sign "$(RELEASE_IDENTITY)" $(RELEASE_APP)
	codesign --verify --strict --verbose=2 $(RELEASE_APP)
	@rm -f $(RELEASE_ZIP)
	ditto -c -k --keepParent $(RELEASE_APP) $(RELEASE_ZIP)
	@echo "Built $(RELEASE_ZIP) ($$(lipo -archs $(RELEASE_APP)/Contents/MacOS/Rook))"

notarize: release
	xcrun notarytool submit $(RELEASE_ZIP) --keychain-profile $(NOTARY_PROFILE) --wait
	xcrun stapler staple $(RELEASE_APP)
	spctl --assess --type execute --verbose $(RELEASE_APP)
	@rm -f $(RELEASE_ZIP)
	ditto -c -k --keepParent $(RELEASE_APP) $(RELEASE_ZIP)
	@echo "sha256 for packaging/rook.rb: $$(shasum -a 256 $(RELEASE_ZIP) | cut -d' ' -f1)"
