.PHONY: nix-add-gcroots clean nix-clean disable-githooks react-native-android react-native-ios react-native-desktop test release _list _fix-node-perms _tmpdir-mk _tmpdir-rm

help: SHELL := /bin/sh
help: ##@other Show this help
	@perl -e '$(HELP_FUN)' $(MAKEFILE_LIST)

# This is a code for automatic help generator.
# It supports ANSI colors and categories.
# To add new item into help output, simply add comments
# starting with '##'. To add category, use @category.
GREEN  := $(shell tput -Txterm setaf 2)
RED    := $(shell tput -Txterm setaf 1)
WHITE  := $(shell tput -Txterm setaf 7)
YELLOW := $(shell tput -Txterm setaf 3)
RESET  := $(shell tput -Txterm sgr0)
HELP_FUN = \
		   %help; \
		   while(<>) { push @{$$help{$$2 // 'options'}}, [$$1, $$3] if /^([a-zA-Z\-]+)\s*:.*\#\#(?:@([a-zA-Z\-]+))?\s(.*)$$/ }; \
		   print "Usage: make [target]\n\n"; \
		   for (sort keys %help) { \
			   print "${WHITE}$$_:${RESET}\n"; \
			   for (@{$$help{$$_}}) { \
				   $$sep = " " x (32 - length $$_->[0]); \
				   print "  ${YELLOW}$$_->[0]${RESET}$$sep${GREEN}$$_->[1]${RESET}\n"; \
			   }; \
			   print "\n"; \
		   }
HOST_OS := $(shell uname | tr '[:upper:]' '[:lower:]')

# This can come from Jenkins
ifndef BUILD_TAG
export BUILD_TAG := $(shell git rev-parse --short HEAD)
endif

# We don't want to use /run/user/$UID because it runs out of space too easilly
export TMPDIR = /tmp/tmp-status-react-$(BUILD_TAG)
# this has to be specified for both the Node.JS server process and the Qt process
export REACT_SERVER_PORT ?= 5001

# Our custom config is located in nix/nix.conf
export NIX_CONF_DIR = $(PWD)/nix
# Defines which variables will be kept for Nix pure shell, use semicolon as divider
export _NIX_KEEP ?= TMPDIR,BUILD_ENV,STATUS_GO_SRC_OVERRIDE,NIMBUS_SRC_OVERRIDE
export _NIX_ROOT = /nix
# legacy TARGET_OS variable support
ifdef TARGET_OS
export TARGET ?= $(TARGET_OS)
endif

# MacOS root is read-only, read nix/README.md for details
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
export NIX_IGNORE_SYMLINK_STORE=1
export _NIX_ROOT = /opt/nix
endif

# Useful for checking if we are on NixOS
OS_NAME = $(shell grep -oP '^NAME=\K\w(.*)' /etc/os-release)

#----------------
# Nix targets
#----------------

# WARNING: This has to be located right before the targets
ifdef IN_NIX_SHELL
SHELL := env bash
else
SHELL := ./nix/scripts/shell.sh
endif

shell: ##@prepare Enter into a pre-configured shell
ifndef IN_NIX_SHELL
	@ENTER_NIX_SHELL
else
	@echo "${YELLOW}Nix shell is already active$(RESET)"
endif

nix-gc: ##@nix Garbage collect all packages older than 20 days from /nix/store
	nix-collect-garbage --delete-old --delete-older-than 20d

nix-clean: ##@nix Remove all status-react build artifacts from /nix/store
	nix/scripts/clean.sh

nix-purge: SHELL := /bin/sh
nix-purge: ##@nix Completely remove the complete Nix setup
ifeq ($(OS_NAME), NixOS)
	$(error $(RED)You should not purge Nix files on NixOS!$(RESET))
else
	sudo rm -rf $(_NIX_ROOT)/* ~/.nix-profile ~/.nix-defexpr ~/.nix-channels ~/.cache/nix ~/.status .nix-gcroots
endif

nix-add-gcroots: export TARGET := default
nix-add-gcroots: ##@nix Add Nix GC roots to avoid status-react expressions being garbage collected
	scripts/add-nix-gcroots.sh

nix-update-gradle: ##@nix Update maven nix expressions based on current gradle setup
	nix/mobile/android/maven-and-npm-deps/maven/generate-nix.sh

nix-update-lein: export TARGET := lein
nix-update-lein: ##@nix Update maven nix expressions based on current lein setup
	nix/tools/lein/generate-nix.sh nix/lein

nix-update-gems: export TARGET := lein
nix-update-gems: ##@nix Update Ruby gems in fastlane/Gemfile.lock and fastlane/gemset.nix
	fastlane/update.sh

nix-update-pods: export TARGET := ios
nix-update-pods: ##@nix Update CocoaPods in ios/Podfile.lock
	cd ios && pod update

#----------------
# General targets
#----------------

_fix-node-perms: SHELL := /bin/sh
_fix-node-perms: ##@prepare Fix permissions so that directory can be cleaned
	$(shell test -d node_modules && chmod -R 744 node_modules)
	$(shell test -d node_modules.tmp && chmod -R 744 node_modules.tmp)

_tmpdir-mk: SHELL := /bin/sh
_tmpdir-mk: ##@prepare Create a TMPDIR for temporary files
	@mkdir -p "$(TMPDIR)"
# Make sure TMPDIR exists every time make is called
-include _tmpdir-mk

_tmpdir-rm: SHELL := /bin/sh
_tmpdir-rm: ##@prepare Remove TMPDIR
	rm -fr "$(TMPDIR)"

clean: SHELL := /bin/sh
clean: _fix-node-perms _tmpdir-rm ##@prepare Remove all output folders
	git clean -dxf

watchman-clean: export TARGET := watchman
watchman-clean: ##@prepare Delete repo directory from watchman
	watchman watch-del $${STATUS_REACT_HOME}

disable-githooks: SHELL := /bin/sh
disable-githooks: ##@prepare Disables lein githooks
	@rm -f ${env.WORKSPACE}/.git/hooks/pre-commit && \
	sed -i'~' -e 's|\[rasom/lein-githooks|;; [rasom/lein-githooks|' \
		-e 's|:githooks|;; :githooks|' \
		-e 's|:pre-commit|;; :pre-commit|' project.clj; \
	rm project.clj~

pod-install: export TARGET := ios
pod-install: ##@prepare Run 'pod install' to install podfiles and update Podfile.lock
	cd ios && pod install; cd --

update-fleets: ##@prepare Download up-to-date JSON file with current fleets state
	curl -s https://fleets.status.im/ \
		| jq --indent 4 --sort-keys . \
		> resources/config/fleets.json

#----------------
# Release builds
#----------------
release: release-android release-ios ##@build build release for Android and iOS

release-android: export TARGET ?= android
release-android: export BUILD_ENV ?= prod
release-android: export BUILD_TYPE ?= nightly
release-android: export BUILD_NUMBER ?= 9999
release-android: export STORE_FILE ?= $(HOME)/.gradle/status-im.keystore
release-android: export ANDROID_ABI_SPLIT ?= false
release-android: export ANDROID_ABI_INCLUDE ?= armeabi-v7a;arm64-v8a;x86
release-android: ##@build build release for Android
	scripts/release-android.sh

release-ios: export TARGET ?= ios
release-ios: export BUILD_ENV ?= prod
release-ios: watchman-clean ##@build build release for iOS release
	@git clean -dxf -f target/ios && \
	$(MAKE) jsbundle-ios && \
	scripts/copy-translations.sh && \
	xcodebuild -workspace ios/StatusIm.xcworkspace -scheme StatusIm -configuration Release -destination 'generic/platform=iOS' -UseModernBuildSystem=N clean archive

release-desktop: export TARGET ?= $(HOST_OS)
release-desktop: ##@build build release for desktop release based on TARGET
	@$(MAKE) jsbundle-desktop && \
	scripts/copy-translations.sh && \
	scripts/build-desktop.sh; \
	$(MAKE) watchman-clean

release-windows-desktop: export TARGET ?= windows
release-windows-desktop: ##@build build release for windows desktop release
	@$(MAKE) jsbundle-desktop && \
	scripts/copy-translations.sh && \
	scripts/build-desktop.sh; \
	$(MAKE) watchman-clean

prod-build-android: jsbundle-android ##@legacy temporary legacy alias for jsbundle-android
	@echo "${YELLOW}This a deprecated target name, use jsbundle-android.$(RESET)"

jsbundle-android: SHELL := /bin/sh
jsbundle-android: export TARGET ?= android
jsbundle-android: export BUILD_ENV ?= prod
jsbundle-android: ##@jsbundle Compile JavaScript and Clojure into index.android.js
	# Call nix-build to build the 'targets.mobile.android.jsbundle' attribute and copy the index.android.js file to the project root
	@git clean -dxf ./index.$(TARGET).js
	nix/scripts/build.sh targets.mobile.android.jsbundle && \
	mv result/index.$(TARGET).js ./

prod-build-ios: jsbundle-ios ##@legacy temporary legacy alias for jsbundle-ios
	@echo "${YELLOW}This a deprecated target name, use jsbundle-ios.$(RESET)"

jsbundle-ios: export TARGET ?= ios
jsbundle-ios: export BUILD_ENV ?= prod
jsbundle-ios: ##@jsbundle Compile JavaScript and Clojure into index.ios.js
	@git clean -dxf -f ./index.$(TARGET).js && \
	lein jsbundle-ios && \
	node prepare-modules.js

prod-build-desktop: jsbundle-desktop ##@legacy temporary legacy alias for jsbundle-desktop
	@echo "${YELLOW}This a deprecated target name, use jsbundle-desktop.$(RESET)"

jsbundle-desktop: export TARGET ?= $(HOST_OS)
jsbundle-desktop: export BUILD_ENV ?= prod
jsbundle-desktop: ##@jsbundle Compile JavaScript and Clojure into index.desktop.js
	git clean -qdxf -f ./index.desktop.js desktop/ && \
	lein jsbundle-desktop && \
	node prepare-modules.js

#--------------
# REPL
# -------------

_watch-%: ##@watch Start development for device
	$(eval SYSTEM := $(word 2, $(subst -, , $@)))
	$(eval DEVICE := $(word 3, $(subst -, , $@)))
	clj -R:dev build.clj watch --platform $(SYSTEM) --$(SYSTEM)-device $(DEVICE)

watch-ios-real: export TARGET := ios
watch-ios-real: _watch-ios-real ##@watch Start development for iOS real device

watch-ios-simulator: export TARGET := ios
watch-ios-simulator: _watch-ios-simulator ##@watch Start development for iOS simulator

watch-android-real: export TARGET := android
watch-android-real: _watch-android-real ##@watch Start development for Android real device

watch-android-avd: export TARGET := android
watch-android-avd: _watch-android-avd ##@watch Start development for Android AVD

watch-android-genymotion: export TARGET ?= android
watch-android-genymotion: _watch-android-genymotion ##@watch Start development for Android Genymotion

watch-desktop: export TARGET ?= $(HOST_OS)
watch-desktop: ##@watch Start development for Desktop
	clj -R:dev build.clj watch --platform desktop

desktop-server: export TARGET ?= $(HOST_OS)
desktop-server:
	node ubuntu-server.js

#--------------
# Run
# -------------
_run-%:
	$(eval SYSTEM := $(word 2, $(subst -, , $@)))
	npx react-native run-$(SYSTEM)

# TODO: Migrate this to a Nix recipe, much the same way as nix/mobile/android/targets/release-android.nix
run-android: export TARGET := android
run-android: ##@run Run Android build
	npx react-native run-android --appIdSuffix debug

run-desktop: export TARGET ?= $(HOST_OS)
run-desktop: _run-desktop ##@run Run Desktop build

SIMULATOR=
run-ios: export TARGET := ios
run-ios: ##@run Run iOS build
ifneq ("$(SIMULATOR)", "")
	npx react-native run-ios --simulator="$(SIMULATOR)"
else
	npx react-native run-ios
endif

#--------------
# Tests
#--------------

lint: export TARGET := lein
lint: ##@test Run code style checks
	lein cljfmt check

lint-fix: export TARGET := lein
lint-fix: ##@test Run code style checks and fix issues
	lein cljfmt fix

test: export TARGET := lein
test: ##@test Run tests once in NodeJS
	lein with-profile test doo node test once

test-auto: export TARGET := lein
test-auto: ##@test Run tests in interactive (auto) mode in NodeJS
	lein with-profile test doo node test

coverage: ##@test Run tests once in NodeJS generating coverage
	@scripts/run-coverage.sh

#--------------
# Other
#--------------
react-native-desktop: export TARGET ?= $(HOST_OS)
react-native-desktop: export _NIX_PURE ?= true
react-native-desktop: ##@other Start react native packager
	@scripts/start-react-native.sh

react-native-android: export TARGET := android
react-native-android: export _NIX_PURE ?= true
react-native-android: ##@other Start react native packager for Android client
	@scripts/start-react-native.sh

react-native-ios: export TARGET := ios
react-native-ios: export _NIX_PURE ?= true
react-native-ios: ##@other Start react native packager for Android client
	@scripts/start-react-native.sh

geth-connect: export TARGET := adb
geth-connect: ##@other Connect to Geth on the device
	adb forward tcp:8545 tcp:8545 && \
	build/bin/geth attach http://localhost:8545

android-clean: ##@prepare Clean Gradle state
	git clean -dxf -f ./android/app/build
	[ -d android/.gradle ] && cd android && ./gradlew clean

android-ports: export TARGET := adb
android-ports: ##@other Add proxies to Android Device/Simulator
	adb reverse tcp:8081 tcp:8081 && \
	adb reverse tcp:3449 tcp:3449 && \
	adb reverse tcp:4567 tcp:4567 && \
	adb forward tcp:5561 tcp:5561

android-devices: export TARGET := adb
android-devices: ##@other Invoke adb devices
	adb devices

android-logcat: export TARGET := adb
android-logcat: ##@other Read status-react logs from Android phone using adb
	adb logcat | grep -e RNBootstrap -e ReactNativeJS -e ReactNative -e StatusModule -e StatusNativeLogs -e 'F DEBUG   :' -e 'Go      :' -e 'GoLog   :' -e 'libc    :'

android-install: export TARGET := adb
android-install: export BUILD_TYPE ?= release
android-install:
	adb install result/app-$(BUILD_TYPE).apk

_list: SHELL := /bin/sh
_list:
	@$(MAKE) -pRrq -f $(lastword $(MAKEFILE_LIST)) : 2>/dev/null | awk -v RS= -F: '/^# File/,/^# Finished Make data base/ {if ($$1 !~ "^[#.]") {print $$1}}' | sort | egrep -v -e '^[^[:alnum:]]' -e '^$@$$'

_unknown-startdev-target-%: SHELL := /bin/sh
_unknown-startdev-target-%:
	@ echo "Unknown target device '$*'. Supported targets:"; \
	${MAKE} _list | grep "watch-" | sed s/watch-/startdev-/; \
	exit 1

_startdev-%: SHELL := /bin/sh
_startdev-%:
	$(eval SYSTEM := $(word 2, $(subst -, , $@)))
	$(eval DEVICE := $(word 3, $(subst -, , $@)))
	@ if [ -z "$(DEVICE)" ]; then \
		$(MAKE) watch-$(SYSTEM) || $(MAKE) _unknown-startdev-target-$@; \
	else \
		$(MAKE) watch-$(SYSTEM)-$(DEVICE) || $(MAKE) _unknown-startdev-target-$@; \
	fi

startdev-android-avd: export TARGET = android
startdev-android-avd: _startdev-android-avd
startdev-android-genymotion: export TARGET = android
startdev-android-genymotion: _startdev-android-genymotion
startdev-android-real: export TARGET = android
startdev-android-real: _startdev-android-real
startdev-desktop: export TARGET ?= $(HOST_OS)
startdev-desktop: _startdev-desktop
startdev-ios-real: export TARGET = ios
startdev-ios-real: _startdev-ios-real
startdev-ios-simulator: export TARGET = ios
startdev-ios-simulator: _startdev-ios-simulator
