SHELL := /bin/zsh

APP_NAME := Layout Pilot
BIN_NAME := LayoutPilot
BUILD_DIR := .build
APP_DIR := $(BUILD_DIR)/$(APP_NAME).app
BUILD_STAMP := $(BUILD_DIR)/.built
INSTALL_DIR := $(HOME)/Applications/$(APP_NAME).app
AGENT_LABEL := dev.alex.layout-pilot
AGENT_SOURCE := LaunchAgent.plist
AGENT_DEST := $(HOME)/Library/LaunchAgents/$(AGENT_LABEL).plist
USER_ID := $(shell /usr/bin/id -u)

.PHONY: all build test background-test integration-test live-harness shift-emitter live-integration-test install clean

all: build

build: $(BUILD_STAMP)

$(BUILD_STAMP): native/LayoutPilot.swift Info.plist
	rm -rf "$(APP_DIR)"
	mkdir -p "$(APP_DIR)/Contents/MacOS" "$(APP_DIR)/Contents/Resources"
	cp Info.plist "$(APP_DIR)/Contents/Info.plist"
	swiftc -parse-as-library native/LayoutPilot.swift \
		-framework AppKit \
		-framework ApplicationServices \
		-framework Carbon \
		-o "$(APP_DIR)/Contents/MacOS/$(BIN_NAME)"
	chmod +x "$(APP_DIR)/Contents/MacOS/$(BIN_NAME)"
	codesign --force --deep --sign - --identifier dev.alex.layout-pilot "$(APP_DIR)"
	touch "$(BUILD_STAMP)"

test: build
	"$(APP_DIR)/Contents/MacOS/$(BIN_NAME)" --self-test

live-harness: $(BUILD_DIR)/LiveTextFieldHarness.app

shift-emitter: $(BUILD_DIR)/ShiftEmitter

background-test integration-test: test
	tests/background.sh

live-integration-test: test live-harness shift-emitter
	tests/integration.sh

$(BUILD_DIR)/LiveTextFieldHarness.app: tests/LiveTextFieldHarness.swift tests/LiveTextFieldHarness.plist
	rm -rf "$@"
	mkdir -p "$@/Contents/MacOS"
	cp tests/LiveTextFieldHarness.plist "$@/Contents/Info.plist"
	swiftc -parse-as-library tests/LiveTextFieldHarness.swift -framework AppKit -o "$@/Contents/MacOS/LiveTextFieldHarness"
	codesign --force --deep --sign - --identifier dev.alex.layout-pilot-live-test "$@"

$(BUILD_DIR)/ShiftEmitter: tests/ShiftEmitter.swift
	mkdir -p "$(BUILD_DIR)"
	swiftc tests/ShiftEmitter.swift -framework ApplicationServices -o "$@"
	codesign --force --sign - --identifier dev.alex.layout-pilot-shift-emitter "$@"

install: test
	-/bin/launchctl bootout gui/$(USER_ID)/$(AGENT_LABEL) 2>/dev/null
	mkdir -p "$(HOME)/Applications"
	rm -rf "$(INSTALL_DIR)"
	ditto "$(APP_DIR)" "$(INSTALL_DIR)"
	codesign --verify --deep --strict "$(INSTALL_DIR)"
	mkdir -p "$(HOME)/Library/LaunchAgents" "$(HOME)/Library/Logs/layout-pilot"
	cp "$(AGENT_SOURCE)" "$(AGENT_DEST)"
	/bin/launchctl bootstrap gui/$(USER_ID) "$(AGENT_DEST)"
	/bin/launchctl enable gui/$(USER_ID)/$(AGENT_LABEL)

clean:
	rm -rf "$(BUILD_DIR)"
