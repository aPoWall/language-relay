SHELL := /bin/zsh
LUA ?= $(shell command -v lua || command -v lua5.5 || echo lua)

APP_NAME := Language Relay
BIN_NAME := LanguageRelay
BUILD_DIR := .build
APP_DIR := $(BUILD_DIR)/$(APP_NAME).app
BUILD_STAMP := $(BUILD_DIR)/.built
SHAPERKIT := native/ShaperKit.swift
FONT_FILES := assets/plex-mono-400.ttf assets/plex-mono-500.ttf assets/plex-mono-600.ttf assets/IBM-Plex-LICENSE.txt
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
# Shared AIM signing lane (lab-sites/internal-sites/aim-product-system/RELEASE-PIPELINE.md):
# SIGN_ID is used only when `security find-identity -v` lists it as valid; otherwise ad-hoc "-".
SIGN_ID ?= AIM Mini Apps
VALID_SIGN_ID := $(shell security find-identity -v -p codesigning 2>/dev/null | grep -F '"$(SIGN_ID)"' | head -n 1)
CODESIGN_ID := $(if $(strip $(VALID_SIGN_ID)),$(SIGN_ID),-)

.PHONY: sign-status
sign-status:
	@echo "SIGN_ID '$(SIGN_ID)': $(if $(strip $(VALID_SIGN_ID)),valid in login keychain,not valid (ad-hoc fallback))"

.PHONY: all build icon test bridge-test design-check background-test shutdown-test integration-test live-harness shift-emitter live-integration-test setup install rollback clean

all: build

build: $(BUILD_STAMP)

icon: $(ICON_FILE)

$(ICON_FILE): $(ICON_SOURCE)
	mkdir -p "$(BUILD_DIR)" assets
	swiftc -parse-as-library "$(ICON_SOURCE)" -framework AppKit -o "$(ICON_RENDERER)"
	rm -rf "$(ICONSET)"
	"$(ICON_RENDERER)" "$(ICONSET)"
	iconutil -c icns "$(ICONSET)" -o "$(ICON_FILE)"

SHELL_SOURCES := native/AIMAppMarks.swift native/AIMAppMarkView.swift native/AIMAppShell.swift
VOXEL_SOURCES := native/AIMVoxelModels.swift native/AIMVoxelView.swift native/AIMHintCard.swift

$(BUILD_STAMP): native/LayoutPilot.swift $(SHAPERKIT) native/NativeWhite.swift native/AIMMiniAppTokens.swift $(VOXEL_SOURCES) $(SHELL_SOURCES) $(FONT_FILES) Info.plist $(ICON_FILE) $(SOUND_FILES)
	@test "$(words $(SOUND_FILES))" = "8" || (echo "expected exactly eight feedback sounds" >&2; exit 1)
	rm -rf "$(APP_DIR)"
	mkdir -p "$(APP_DIR)/Contents/MacOS" "$(APP_DIR)/Contents/Resources/Sounds"
	cp Info.plist "$(APP_DIR)/Contents/Info.plist"
	cp "$(ICON_FILE)" "$(APP_DIR)/Contents/Resources/LanguageRelay.icns"
	cp $(FONT_FILES) "$(APP_DIR)/Contents/Resources/"
	cp $(SOUND_FILES) "$(APP_DIR)/Contents/Resources/Sounds/"
	swiftc -parse-as-library "$(SHAPERKIT)" native/AIMMiniAppTokens.swift $(VOXEL_SOURCES) $(SHELL_SOURCES) native/NativeWhite.swift native/LayoutPilot.swift \
		-framework AppKit \
		-framework ApplicationServices \
		-framework Carbon \
		-o "$(APP_DIR)/Contents/MacOS/$(BIN_NAME)"
	chmod +x "$(APP_DIR)/Contents/MacOS/$(BIN_NAME)"
	@echo "codesign: $(if $(strip $(VALID_SIGN_ID)),identity '$(SIGN_ID)',ad-hoc (SIGN_ID '$(SIGN_ID)' not valid))"
	codesign --force --deep --sign "$(CODESIGN_ID)" --identifier dev.alex.layout-pilot "$(APP_DIR)"
	touch "$(BUILD_STAMP)"

test: build bridge-test
	"$(APP_DIR)/Contents/MacOS/$(BIN_NAME)" --self-test
	"$(APP_DIR)/Contents/MacOS/$(BIN_NAME)" --ui-self-test

# Bridge watchdog offscreen (wave 11 B, rule 50): the lua runs against a stub Hammerspoon, so the owner's
# configuration is never loaded, reloaded or touched.
bridge-test:
	@if command -v $(LUA) >/dev/null 2>&1; then $(LUA) tests/bridge-watchdog.lua; \
	else echo "bridge-test: $(LUA) missing, skipped (install lua to run the watchdog test)"; fi

design-check:
	node scripts/sync-design-tokens.mjs --check

live-harness: $(BUILD_DIR)/LiveTextFieldHarness.app

shift-emitter: $(BUILD_DIR)/ShiftEmitter

background-test integration-test: test
	tests/background.sh

shutdown-test: test
	tests/shutdown.sh

live-integration-test: test live-harness shift-emitter
	tests/integration.sh

setup: build
	mkdir -p "$(BRIDGE_DIR)"
	cp hammerspoon-layout-pilot.lua "$(BRIDGE_DIR)/hammerspoon.lua"
	touch "$(BRIDGE_DIR)/hammerspoon-bridge"
	"$(APP_DIR)/Contents/MacOS/$(BIN_NAME)" --setup

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
	./install-runtime.sh install

rollback:
	./install-runtime.sh rollback

clean:
	rm -rf "$(BUILD_DIR)"
