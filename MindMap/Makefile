SHELL := /bin/bash
PROJECT := MindMap.xcodeproj
SCHEME := MindMap
DERIVED := .build
RELEASE_DERIVED := .build-release
TEST_DERIVED := .build-tests

.PHONY: project debug release run test test-core test-app test-all clean install

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
	rm -rf $(DERIVED) $(RELEASE_DERIVED) $(TEST_DERIVED) dist
