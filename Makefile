APP_NAME = AgentMonitor
BUILD_CONFIG = release
BUILD_DIR = .build/release
APP_BUNDLE = $(APP_NAME).app

.PHONY: build app run install clean

build:
	swift build -c $(BUILD_CONFIG)

app: build
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	@cp $(BUILD_DIR)/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/
	@cp Info.plist $(APP_BUNDLE)/Contents/
	@cp AppIcon.icns $(APP_BUNDLE)/Contents/Resources/AppIcon.icns
	@echo "✅ App bundle created: $(APP_BUNDLE)"

run: app
	@open $(APP_BUNDLE)

install: app
	@cp -r $(APP_BUNDLE) /Applications/
	@echo "✅ Installed to /Applications/$(APP_BUNDLE)"

clean:
	@rm -rf .build $(APP_BUNDLE)
	@echo "✅ Cleaned"
