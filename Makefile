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

.PHONY: build bundle run stop install test clean

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
