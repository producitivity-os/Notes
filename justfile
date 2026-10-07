set shell := ["zsh", "-cu"]

default:
    @just --list

generate:
    xcodegen generate

build:
    zsh Tools/native-build.sh Debug build

open:
    open -n -F .build/xcode/Build/Products/Debug/Notes.app

run: build
    just open

release:
    zsh Tools/native-build.sh Release build

test:
    zsh Tools/native-build.sh Debug test

build-server:
   xcode-build-server config -project Notes.xcodeproj -scheme Notes

update-icon picture:
    zsh Tools/update-app-icon.sh "{{picture}}"

install: release
    mkdir -p ~/Applications
    rm -rf ~/Applications/Notes.app
    cp -R .build/xcode/Build/Products/Release/Notes.app ~/Applications/Notes.app
