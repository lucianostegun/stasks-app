SCHEME=Stasks
BUILD_DIR=build
APP=$(BUILD_DIR)/Build/Products/Release/Stasks.app

.PHONY: gen build test-core test-hooks test run install clean

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

clean:
	rm -rf $(BUILD_DIR) StasksCore/.build
