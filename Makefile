# One-command workflows for remote-storage macOS app.

.PHONY: run build test clean

run:
	DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer flutter run -d macos

build:
	DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer flutter build macos

test:
	flutter test

clean:
	flutter clean
