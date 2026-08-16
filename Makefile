APP_NAME := 含章可贞
BIN_NAME := Yixi
VERSION := 1.0
APP_DIR := dist/$(APP_NAME).app
CONTENTS := $(APP_DIR)/Contents
DMG_NAME := $(APP_NAME)-$(VERSION).dmg
DMG_ROOT := dist/dmgroot

.PHONY: app icon install dmg run clean

app: icon
	swift build -c release --product $(BIN_NAME)
	rm -rf $(APP_DIR)
	mkdir -p $(CONTENTS)/MacOS $(CONTENTS)/Resources
	cp .build/release/$(BIN_NAME) $(CONTENTS)/MacOS/$(BIN_NAME)
	cp Resources/Info.plist $(CONTENTS)/Info.plist
	cp Resources/AppIcon.icns $(CONTENTS)/Resources/AppIcon.icns
	echo APPL???? > $(CONTENTS)/PkgInfo
	codesign -s - --force --deep "$(APP_DIR)"
	@echo "已生成 $(APP_DIR)"

icon:
	mkdir -p Resources/AppIcon.iconset
	swift scripts/make_icon.swift Resources
	sips -z 16 16     Resources/AppIcon.png --out Resources/AppIcon.iconset/icon_16x16.png >/dev/null
	sips -z 32 32     Resources/AppIcon.png --out Resources/AppIcon.iconset/icon_16x16@2x.png >/dev/null
	sips -z 32 32     Resources/AppIcon.png --out Resources/AppIcon.iconset/icon_32x32.png >/dev/null
	sips -z 64 64     Resources/AppIcon.png --out Resources/AppIcon.iconset/icon_32x32@2x.png >/dev/null
	sips -z 128 128   Resources/AppIcon.png --out Resources/AppIcon.iconset/icon_128x128.png >/dev/null
	sips -z 256 256   Resources/AppIcon.png --out Resources/AppIcon.iconset/icon_128x128@2x.png >/dev/null
	sips -z 256 256   Resources/AppIcon.png --out Resources/AppIcon.iconset/icon_256x256.png >/dev/null
	sips -z 512 512   Resources/AppIcon.png --out Resources/AppIcon.iconset/icon_256x256@2x.png >/dev/null
	sips -z 512 512   Resources/AppIcon.png --out Resources/AppIcon.iconset/icon_512x512.png >/dev/null
	sips -z 1024 1024 Resources/AppIcon.png --out Resources/AppIcon.iconset/icon_512x512@2x.png >/dev/null
	iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns

install: app
	-killall $(BIN_NAME) 2>/dev/null
	rm -rf "/Applications/一息.app" "/Applications/可可望远.app" "/Applications/$(APP_NAME).app"
	cp -R "$(APP_DIR)" /Applications/
	@echo "已安装到 /Applications/$(APP_NAME).app"

dmg: app
	rm -rf "$(DMG_ROOT)" "dist/$(DMG_NAME)"
	mkdir -p "$(DMG_ROOT)"
	cp -R "$(APP_DIR)" "$(DMG_ROOT)/"
	ln -s /Applications "$(DMG_ROOT)/Applications"
	hdiutil create \
		-volname "$(APP_NAME)" \
		-srcfolder "$(DMG_ROOT)" \
		-ov -format UDZO \
		"dist/$(DMG_NAME)"
	rm -rf "$(DMG_ROOT)"
	@echo "已生成 dist/$(DMG_NAME)"

run: app
	open "$(APP_DIR)"

clean:
	rm -rf .build dist Resources/AppIcon.iconset Resources/AppIcon.png
