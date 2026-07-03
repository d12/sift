.PHONY: generate build clean lint

# Generate the Xcode project from project.yml (requires: brew install xcodegen)
generate:
	xcodegen generate

# Generate then build a release archive
build: generate
	xcodebuild \
		-project Sift.xcodeproj \
		-scheme Sift \
		-configuration Release \
		-archivePath build/Sift.xcarchive \
		archive

# Export a signed .app from the archive (requires ExportOptions.plist)
export: build
	xcodebuild \
		-exportArchive \
		-archivePath build/Sift.xcarchive \
		-exportPath build/export \
		-exportOptionsPlist ExportOptions.plist

# Run in Debug without archiving
run: generate
	xcodebuild \
		-project Sift.xcodeproj \
		-scheme Sift \
		-configuration Debug \
		build

clean:
	rm -rf build/
	rm -rf Sift.xcodeproj/

lint:
	swiftlint --strict
