set shell := ["zsh", "-cu"]

default:
    @just --list

canvas:
    yarn build:native-canvas

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

export-notebooks:
    bash export-notebooks.sh

build-server:
   xcode-build-server config -project Notes.xcodeproj -scheme Notes
