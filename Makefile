SHELL := /bin/zsh

APP_NAME := Language Relay
BIN_NAME := LanguageRelay
BUILD_DIR := .build
APP_DIR := $(BUILD_DIR)/$(APP_NAME).app
BUILD_STAMP := $(BUILD_DIR)/.built
SHAPERKIT := native/ShaperKit.swift
ICON_SOURCE := native/IconRenderer.swift
ICON_RENDERER := $(BUILD_DIR)/IconRenderer
ICONSET := $(BUILD_DIR)/LanguageRelay.iconset
ICON_FILE := assets/LanguageRelay.icns
SOUND_FILES := assets/Sounds/pulse.aiff assets/Sounds/relay.aiff assets/Sounds/scan.aiff assets/Sounds/flux.aiff assets/Sounds/prism.aiff assets/Sounds/tick.aiff assets/Sounds/fold.aiff assets/Sounds/nova.aiff
INSTALL_DIR := $(HOME)/Applications/$(APP_NAME).app
AGENT_LABEL := dev.alex.layout-pilot
AGENT_SOURCE := LaunchAgent.plist
AGENT_DEST := $(HOME)/Library/LaunchAgents/$(AGENT_LABEL).plist
BRIDGE_DIR := $(HOME)/.config/language-relay
USER_ID := $(shell /usr/bin/id -u)

.PHONY: all build icon test background-test integration-test live-harness shift-emitter live-integration-test install clean

all: build

build: $(BUILD_STAMP)

icon: $(ICON_FILE)

$(ICON_FILE): $(ICON_SOURCE)
	mkdir -p "$(BUILD_DIR)" assets
	swiftc -parse-as-library "$(ICON_SOURCE)" -framework AppKit -o "$(ICON_RENDERER)"
	rm -rf "$(ICONSET)"
	"$(ICON_RENDERER)" "$(ICONSET)"
	iconutil -c icns "$(ICONSET)" -o "$(ICON_FILE)"

$(BUILD_STAMP): native/LayoutPilot.swift $(SHAPERKIT) Info.plist $(ICON_FILE) $(SOUND_FILES)
	@test "$(words $(SOUND_FILES))" = "8" || (echo "expected exactly eight feedback sounds" >&2; exit 1)
	rm -rf "$(APP_DIR)"
	mkdir -p "$(APP_DIR)/Contents/MacOS" "$(APP_DIR)/Contents/Resources/Sounds"
	cp Info.plist "$(APP_DIR)/Contents/Info.plist"
	cp "$(ICON_FILE)" "$(APP_DIR)/Contents/Resources/LanguageRelay.icns"
	cp $(SOUND_FILES) "$(APP_DIR)/Contents/Resources/Sounds/"
	swiftc -parse-as-library "$(SHAPERKIT)" native/LayoutPilot.swift \
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
	sed 's|__HOME__|$(HOME)|g' "$(AGENT_SOURCE)" > "$(AGENT_DEST)"
	mkdir -p "$(BRIDGE_DIR)"
	cp hammerspoon-layout-pilot.lua "$(BRIDGE_DIR)/hammerspoon.lua"
	touch "$(BRIDGE_DIR)/hammerspoon-bridge"
	: > "$(HOME)/Library/Logs/layout-pilot/layout-pilot.out.log"
	: > "$(HOME)/Library/Logs/layout-pilot/layout-pilot.err.log"
	/bin/launchctl bootstrap gui/$(USER_ID) "$(AGENT_DEST)"
	/bin/launchctl enable gui/$(USER_ID)/$(AGENT_LABEL)

clean:
	rm -rf "$(BUILD_DIR)"
