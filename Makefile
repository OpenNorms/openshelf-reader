# OpenShelf Reader — common tasks.
#
#   make test      engine tests (swift test)
#   make generate  regenerate the Xcode project from project.yml
#   make sim       build, install and launch on an iOS simulator
#   make deploy    build, install and launch on your iPhone
#
# Nothing personal lives in this file. Signing (your team ID) comes from
# Config/Signing.local.xcconfig; device and simulator choices can go in
# local.mk (both gitignored; see local.mk.example). With no DEVICE set,
# `make deploy` picks the first paired iPhone/iPad, over USB or Wi-Fi
# (already-connected ones first).

-include local.mk

PROJECT   := OpenShelfReader.xcodeproj
SCHEME    := OpenShelfReader
BUNDLE_ID := org.opennorms.openshelf-reader
BUILD_DIR := build
SIM_NAME  ?= iPhone 18 Pro

DEVICE_APP := $(BUILD_DIR)/device/Build/Products/Debug-iphoneos/$(SCHEME).app
SIM_APP    := $(BUILD_DIR)/sim/Build/Products/Debug-iphonesimulator/$(SCHEME).app

.PHONY: test generate sim deploy device-id clean

test:
	swift test

generate: $(PROJECT)

$(PROJECT): project.yml
	xcodegen generate

# Resolves DEVICE lazily so `make test` never touches devicectl.
device-id:
	@$(call resolve_device) && echo "$$DEVICE"

deploy: generate
	@test -f Config/Signing.local.xcconfig || { \
	  echo "error: Config/Signing.local.xcconfig missing; copy the .example and set DEVELOPMENT_TEAM"; exit 1; }
	@$(call resolve_device) && \
	echo "==> building for device $$DEVICE" && \
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination "id=$$DEVICE" \
	  -derivedDataPath $(BUILD_DIR)/device -allowProvisioningUpdates -quiet build && \
	echo "==> installing" && \
	xcrun devicectl device install app --device "$$DEVICE" $(DEVICE_APP) >/dev/null && \
	echo "==> launching" && \
	xcrun devicectl device process launch --device "$$DEVICE" $(BUNDLE_ID) >/dev/null && \
	echo "==> done"

sim: generate
	@SIM=$$(xcrun simctl list devices available -j | python3 -c 'import json,sys; \
	  d=json.load(sys.stdin)["devices"]; \
	  m=[x["udid"] for k in sorted(d,reverse=True) if ".iOS-" in k for x in d[k] if x["name"]=="$(SIM_NAME)"]; \
	  print(m[0] if m else "")'); \
	test -n "$$SIM" || { echo "error: no available simulator named '$(SIM_NAME)'"; exit 1; }; \
	echo "==> building for $(SIM_NAME) ($$SIM)" && \
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination "id=$$SIM" \
	  -derivedDataPath $(BUILD_DIR)/sim -quiet build && \
	{ xcrun simctl boot "$$SIM" 2>/dev/null; xcrun simctl bootstatus "$$SIM" -b >/dev/null; } && \
	xcrun simctl install "$$SIM" $(SIM_APP) && \
	xcrun simctl launch "$$SIM" $(BUNDLE_ID) >/dev/null && \
	echo "==> running on $(SIM_NAME)"

clean:
	rm -rf $(BUILD_DIR)

# Sets shell var DEVICE: $(DEVICE) from local.mk / command line, else the
# first paired physical iOS device (already-connected ones first;
# devicectl opens the tunnel on demand).
define resolve_device
DEVICE="$(DEVICE)"; \
if [ -z "$$DEVICE" ]; then \
  J=$$(mktemp); \
  xcrun devicectl list devices --json-output "$$J" >/dev/null 2>&1; \
  DEVICE=$$(python3 -c 'import json,sys; \
    d=json.load(open(sys.argv[1]))["result"]["devices"]; \
    p=[x for x in d \
       if x["hardwareProperties"].get("reality")=="physical" \
       and x["hardwareProperties"].get("platform")=="iOS" \
       and x["connectionProperties"].get("pairingState")=="paired"]; \
    p.sort(key=lambda x: x["connectionProperties"].get("tunnelState")!="connected"); \
    m=[x["hardwareProperties"]["udid"] for x in p]; \
    print(m[0] if m else "")' "$$J"); \
  rm -f "$$J"; \
fi; \
test -n "$$DEVICE" || { echo "error: no connected iPhone found (unlock it, same Wi-Fi, or set DEVICE in local.mk)"; exit 1; }
endef
