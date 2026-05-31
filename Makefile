# Cross-platform desktop workflows for remote-storage.

FLUTTER ?= $(shell if command -v flutter >/dev/null 2>&1; then command -v flutter; elif [ -x /opt/tools/flutter/bin/flutter ]; then printf '%s\n' /opt/tools/flutter/bin/flutter; fi)

ifeq ($(OS),Windows_NT)
HOST_PLATFORM := windows
else
OS_NAME := $(shell uname -s)
ifeq ($(OS_NAME),Darwin)
HOST_PLATFORM := macos
else ifeq ($(OS_NAME),Linux)
HOST_PLATFORM := linux
else
HOST_PLATFORM := unknown
endif
endif

BRIDGE_DIR := bin/bridge
MACOS_BRIDGE_OUT := $(BRIDGE_DIR)/libremote_storage_bridge.dylib
LINUX_BRIDGE_OUT := $(BRIDGE_DIR)/libremote_storage_bridge.so
WINDOWS_BRIDGE_OUT := $(BRIDGE_DIR)/remote_storage_bridge.dll
BRIDGE_GO_ENV := CGO_ENABLED=1

ifneq ($(BRIDGE_CC),)
BRIDGE_GO_ENV += CC=$(BRIDGE_CC)
endif

ifneq ($(BRIDGE_CXX),)
BRIDGE_GO_ENV += CXX=$(BRIDGE_CXX)
endif

.PHONY: bridge bridge-macos bridge-linux bridge-windows run run-macos run-linux run-web build build-macos build-linux build-windows build-web test analyze clean

bridge:
ifeq ($(HOST_PLATFORM),macos)
	$(MAKE) bridge-macos
else ifeq ($(HOST_PLATFORM),linux)
	$(MAKE) bridge-linux
else ifeq ($(HOST_PLATFORM),windows)
	$(MAKE) bridge-windows
else
	@echo "Unsupported host OS for default bridge target: $(HOST_PLATFORM)"
	@exit 1
endif

bridge-macos:
	@mkdir -p $(BRIDGE_DIR)
	$(BRIDGE_GO_ENV) go build -buildmode=c-shared -o $(MACOS_BRIDGE_OUT) ./bridge

bridge-linux:
	@mkdir -p $(BRIDGE_DIR)
	$(BRIDGE_GO_ENV) go build -buildmode=c-shared -o $(LINUX_BRIDGE_OUT) ./bridge

bridge-windows:
ifeq ($(HOST_PLATFORM),windows)
	@mkdir -p $(BRIDGE_DIR)
	$(BRIDGE_GO_ENV) go build -buildmode=c-shared -o $(WINDOWS_BRIDGE_OUT) ./bridge
else
	@echo "bridge-windows must be run on a Windows host."
	@exit 1
endif

run: bridge
ifeq ($(HOST_PLATFORM),macos)
	DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer $(FLUTTER) run -d macos
else ifeq ($(HOST_PLATFORM),linux)
	$(FLUTTER) run -d linux
else ifeq ($(HOST_PLATFORM),windows)
	$(FLUTTER) run -d windows
else
	@echo "Unsupported host OS for default run target: $(HOST_PLATFORM)"
	@exit 1
endif

run-macos: bridge-macos
	DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer $(FLUTTER) run -d macos

run-linux: bridge-linux
ifeq ($(HOST_PLATFORM),linux)
	$(FLUTTER) run -d linux
else
	@echo "run-linux must be run on a Linux host."
	@exit 1
endif

run-windows: bridge-windows
ifeq ($(HOST_PLATFORM),windows)
	$(FLUTTER) run -d windows
else
	@echo "run-windows must be run on a Windows host."
	@exit 1
endif

run-web: build-web
	go run ./cmd/web --listen :8080 --static-root build/web

build:
ifeq ($(HOST_PLATFORM),macos)
	$(MAKE) build-macos
else ifeq ($(HOST_PLATFORM),linux)
	$(MAKE) build-linux
else ifeq ($(HOST_PLATFORM),windows)
	$(MAKE) build-windows
else
	@echo "Unsupported host OS for default build target: $(HOST_PLATFORM)"
	@exit 1
endif

build-macos: bridge-macos
	DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer $(FLUTTER) build macos

build-linux: bridge-linux
ifeq ($(HOST_PLATFORM),linux)
	$(FLUTTER) build linux
else
	@echo "build-linux must be run on a Linux host."
	@exit 1
endif

build-windows: bridge-windows
ifeq ($(HOST_PLATFORM),windows)
	$(FLUTTER) build windows
else
	@echo "build-windows must be run on a Windows host."
	@exit 1
endif

build-web:
	$(FLUTTER) build web

test:
	$(FLUTTER) test

analyze:
	$(FLUTTER) analyze

clean:
	$(FLUTTER) clean
	rm -rf $(BRIDGE_DIR)
