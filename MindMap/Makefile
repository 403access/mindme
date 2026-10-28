SHELL := /bin/bash
PROJECT := MindMap.xcodeproj
SCHEME := MindMap
DERIVED := .build
RELEASE_DERIVED := .build-release

.PHONY: project debug release run test clean install

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

test:
	cd Core && swift test

install: release
	mkdir -p $(HOME)/Applications
	rm -rf $(HOME)/Applications/MINDME.app
	cp -R dist/MINDME.app $(HOME)/Applications/MINDME.app
	@echo "Installed to $(HOME)/Applications/MINDME.app"

clean:
	rm -rf $(DERIVED) $(RELEASE_DERIVED) dist
