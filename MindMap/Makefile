SHELL := /bin/bash
PROJECT := MindMap.xcodeproj
SCHEME := MindMap
IOS_SCHEME := MindMapIOS
DERIVED := .build
RELEASE_DERIVED := .build-release
TEST_DERIVED := .build-tests
IOS_DERIVED := .build-ios
IOS_DEVICE_DERIVED := .build-device

.PHONY: project debug release run ios ios-device test test-core test-app test-all clean install

project:
	xcodegen generate

debug: project
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -derivedDataPath $(DERIVED) build

release: project
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release -derivedDataPath $(RELEASE_DERIVED) build
	mkdir -p dist
	rm -rf dist/MINDME.app
	cp -R $(RELEASE_DERIVED)/Build/Products/Release/MINDME.app dist/MINDME.app
	@echo "Built dist/MINDME.app"

run: debug
	open $(DERIVED)/Build/Products/Debug/MINDME.app

# iPhone app. Builds for the simulator so no signing team is required; use
# Xcode and the MindMapIOS scheme to run on a physical device.
ios: project
	xcodebuild -project $(PROJECT) -scheme $(IOS_SCHEME) -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath $(IOS_DERIVED) CODE_SIGNING_ALLOWED=NO build
	@echo "Built $(IOS_DERIVED)/Build/Products/Debug-iphonesimulator/MINDME.app"

# Install on a connected iPhone. Find DEVICE_ID with `xcrun devicectl list
# devices`, and TEAM_ID in Xcode → Settings → Accounts → your team.
ios-device: project
	@test -n "$(DEVICE_ID)" || (echo "Set DEVICE_ID (see: xcrun devicectl list devices)" && exit 1)
	@test -n "$(TEAM_ID)" || (echo "Set TEAM_ID (Xcode → Settings → Accounts)" && exit 1)
	xcodebuild -project $(PROJECT) -scheme $(IOS_SCHEME) -configuration Debug -destination 'platform=iOS,id=$(DEVICE_ID)' -derivedDataPath $(IOS_DEVICE_DERIVED) -allowProvisioningUpdates DEVELOPMENT_TEAM=$(TEAM_ID) CODE_SIGN_STYLE=Automatic build
	xcrun devicectl device install app --device $(DEVICE_ID) $(IOS_DEVICE_DERIVED)/Build/Products/Debug-iphoneos/MINDME.app
	xcrun devicectl device process launch --device $(DEVICE_ID) --activate dev.oliver.mindme

# Core suite: importers, keyword extraction, topics, graph, layout, storage.
test: test-core

test-core:
	cd Core && swift test

# App logic suite: cameras/projection, graph engine, word-cloud layouts.
# App sources are compiled into a hostless bundle, so the real app (and its
# local library) is never launched.
test-app: project
	xcodebuild test -project $(PROJECT) -scheme $(SCHEME) -destination 'platform=macOS' -derivedDataPath $(TEST_DERIVED)

test-all: test-core test-app

install: release
	mkdir -p $(HOME)/Applications
	rm -rf $(HOME)/Applications/MINDME.app
	cp -R dist/MINDME.app $(HOME)/Applications/MINDME.app
	@echo "Installed to $(HOME)/Applications/MINDME.app"

clean:
	rm -rf $(DERIVED) $(RELEASE_DERIVED) $(TEST_DERIVED) $(IOS_DERIVED) $(IOS_DEVICE_DERIVED) dist
