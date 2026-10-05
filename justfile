set shell := ["zsh", "-cu"]

default:
    @just --list

generate:
    xcodegen generate

build:
    zsh Native/Tools/native-build.sh Debug build

open:
    open -n .build/xcode/Build/Products/Debug/Notes.app

run: build
    just open

release:
    zsh Native/Tools/native-build.sh Release build

test:
    zsh Native/Tools/native-build.sh Debug test

build-server:
   xcode-build-server config -project Notes.xcodeproj -scheme Notes

update-icon picture:
    zsh Native/Tools/update-app-icon.sh "{{picture}}"
