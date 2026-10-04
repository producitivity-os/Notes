xcodebuild \
  -project Notes.xcodeproj \
  -scheme Notes \
  -configuration Debug \
  -derivedDataPath .build/xcode \
  CODE_SIGNING_ALLOWED=NO \
  build
