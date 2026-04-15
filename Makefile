PROJECT = View.xcodeproj
SCHEME = View
DEST = platform=macOS
DERIVED = .build
APP = $(DERIVED)/Build/Products/Release/View.app
INSTALL_DIR = /Applications
UNIVERSAL = ONLY_ACTIVE_ARCH=NO
NO_PROFILING = CLANG_ENABLE_CODE_COVERAGE=NO CLANG_COVERAGE_MAPPING=NO

XCODEBUILD = xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DEST)'

CORE_PKG = Packages/ViewCore
FMT_TARGETS = View $(CORE_PKG)/Sources $(CORE_PKG)/Tests

.DEFAULT_GOAL := debug

.PHONY: build debug run test test-core clean install zip release lsp fmt fmt-check

debug:
	$(XCODEBUILD) -configuration Debug -derivedDataPath $(DERIVED) -quiet

build:
	$(XCODEBUILD) -configuration Release -derivedDataPath $(DERIVED) $(UNIVERSAL) $(NO_PROFILING) -quiet
	@echo "Built: $(APP)"

run: debug
	open "$(DERIVED)/Build/Products/Debug/View.app"

test: test-core
	$(XCODEBUILD) -derivedDataPath $(DERIVED) -only-testing:ViewTests CODE_SIGNING_ALLOWED=NO test -quiet || true

test-core:
	swift test --package-path $(CORE_PKG)

clean:
	$(XCODEBUILD) clean -quiet
	/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -u $(APP) 2>/dev/null || true
	rm -rf $(DERIVED)
	rm -rf $(CORE_PKG)/.build

install: build
	rsync -a "$(APP)/" "$(INSTALL_DIR)/View.app/"
	@echo "Installed to $(INSTALL_DIR)/View.app"

zip: build
	ditto -c -k --keepParent "$(APP)" View.zip
	@echo "Packaged: View.zip"

lsp:
	xcode-build-server config -project $(PROJECT) -scheme $(SCHEME) --build_root $(DERIVED)

fmt:
	swift-format -i --recursive $(FMT_TARGETS)

fmt-check:
	swift-format lint --recursive --strict $(FMT_TARGETS)

# Usage: make release V=0.2
release:
ifndef V
	$(error Usage: make release V=x.y)
endif
	sed -i '' 's/MARKETING_VERSION = [^;]*/MARKETING_VERSION = $(V)/' $(PROJECT)/project.pbxproj
	git add $(PROJECT)/project.pbxproj
	git commit -m "Release v$(V)"
	@echo "Version set to $(V) and committed. Now tag and push."
