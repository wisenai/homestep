# make test        everything that runs on a Mac: core, tools, checks, app
# make test-core   the decision logic and walk scenarios (no Simulator needed)
# make test-app    app unit tests and the UI test in the Simulator
# make check       safety/privacy checks, tool tests, traceability

DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
export DEVELOPER_DIR
# The first available iPhone simulator; override with SIMULATOR_ID=<udid>.
SIMULATOR_ID ?= $(shell DEVELOPER_DIR=$(DEVELOPER_DIR) xcrun simctl list devices available \
	| grep -m1 -E '^ +iPhone' | grep -oE '[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}')

.PHONY: test test-core test-app check project

test: test-core check test-app

# Optimized, with testing enabled: the walk scenarios render thousands of
# depth frames and take seconds this way instead of minutes.
test-core:
	cd Core && swift test -c release -Xswiftc -enable-testing

check:
	python3 tools/check.py
	python3 -m unittest discover -s tools/tests
	python3 tools/trace.py --write

Config/Signing.xcconfig:
	cp Config/Signing.example.xcconfig $@

project: Config/Signing.xcconfig
	xcodegen generate

test-app: project
	xcodebuild test -project HomeStep.xcodeproj -scheme HomeStep \
		-destination 'platform=iOS Simulator,id=$(SIMULATOR_ID)' -derivedDataPath build/dd
