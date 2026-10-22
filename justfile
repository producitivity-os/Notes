set shell := ["zsh", "-cu"]

default:
    @just --list

generate:
    xcodegen generate

build-macos: generate
    xcodebuild -project Notes.xcodeproj -scheme Notes -configuration Debug -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/xcode build CODE_SIGNING_ALLOWED=NO

test-macos: generate
    xcodebuild -project Notes.xcodeproj -scheme Notes -configuration Debug -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/xcode test CODE_SIGNING_ALLOWED=NO

run-macos: build-macos
    ../../tools/apple-app.sh run-macos "$PWD" Notes Notebook com.productivity-os.notes

install-macos: release-macos
    ../../tools/apple-app.sh install-macos "$PWD" Notes Notebook com.productivity-os.notes

release-macos: generate
    xcodebuild -project Notes.xcodeproj -scheme Notes -configuration Release -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/xcode build CODE_SIGNING_ALLOWED=NO

build-sim: generate
    ../../tools/apple-app.sh build-sim "$PWD" Notes NotebookIOS com.productivity-os.notes.ios

test-sim: generate
    ../../tools/apple-app.sh test-sim "$PWD" Notes NotebookIOS com.productivity-os.notes.ios

run-sim: generate
    ../../tools/apple-app.sh run-sim "$PWD" Notes NotebookIOS com.productivity-os.notes.ios

build-device: generate
    ../../tools/apple-app.sh build-device "$PWD" Notes NotebookIOS com.productivity-os.notes.ios

install-device: generate
    ../../tools/apple-app.sh install-device "$PWD" Notes NotebookIOS com.productivity-os.notes.ios

run-device: generate
    ../../tools/apple-app.sh run-device "$PWD" Notes NotebookIOS com.productivity-os.notes.ios

update-icon picture:
    Tools/update-app-icon.sh "{{picture}}"

icons:
    @echo "Notebook uses native bundled icons"

build-server:
    xcode-build-server config -project Notes.xcodeproj -scheme Notes

build: build-macos
test: test-macos
run: run-macos
release: release-macos
