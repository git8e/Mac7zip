.PHONY: build app dmg run clean engine icon

# Compile the Swift package (debug).
build:
	swift build

# Assemble build/Mac7zip.app (release) with the bundled 7-Zip engine.
app:
	Scripts/build_app.sh release

# Assemble the .app and wrap it in a distributable DMG.
dmg: app
	Scripts/make_dmg.sh 1.0

# Run from source (uses Vendor/7zz).
run:
	swift run Mac7zip

# Re-download the official 7-Zip macOS engine into Vendor/.
engine:
	Scripts/fetch_engine.sh

# Regenerate Resources/AppIcon.icns from the official 7-Zip program icon.
icon:
	swift Scripts/make_icon.swift Resources/7-Zip-Icon.svg Resources/AppIcon.icns

clean:
	rm -rf .build build
