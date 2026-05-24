# One-command workflows for remote-storage macOS app.

BRIDGE_OUT := bin/bridge/libremote_storage_bridge.dylib

.PHONY: bridge run build test clean

bridge:
	@mkdir -p bin/bridge
	go build -buildmode=c-shared -o $(BRIDGE_OUT) ./bridge

run: bridge
	DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer flutter run -d macos

build: bridge
	DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer flutter build macos

test:
	flutter test

clean:
	flutter clean
	rm -rf bin/bridge
