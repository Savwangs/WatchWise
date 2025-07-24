#!/bin/bash

echo "🚀 Building WatchWise for App Store submission..."

# Set the project path
PROJECT_PATH="/Users/savirwangoo/Desktop/csProjects/WatchWise"
PROJECT_NAME="WatchWise"
SCHEME_NAME="WatchWise"
ARCHIVE_NAME="WatchWise.xcarchive"

cd "$PROJECT_PATH"

echo "📁 Working directory: $(pwd)"

# Clean the project
echo "🧹 Cleaning project..."
xcodebuild clean -project "$PROJECT_NAME.xcodeproj" -scheme "$SCHEME_NAME" -configuration Release

if [ $? -ne 0 ]; then
    echo "❌ Clean failed. Please check your Xcode project settings."
    exit 1
fi

echo "✅ Clean completed successfully"

# Archive the project
echo "📦 Creating archive..."
xcodebuild archive \
    -project "$PROJECT_NAME.xcodeproj" \
    -scheme "$SCHEME_NAME" \
    -configuration Release \
    -archivePath "$ARCHIVE_NAME" \
    -destination "generic/platform=iOS"

if [ $? -ne 0 ]; then
    echo "❌ Archive failed. Please check your Xcode project settings."
    exit 1
fi

echo "✅ Archive created successfully: $ARCHIVE_NAME"

# Check if archive was created
if [ -d "$ARCHIVE_NAME" ]; then
    echo "📋 Archive details:"
    echo "   Location: $(pwd)/$ARCHIVE_NAME"
    echo "   Size: $(du -sh "$ARCHIVE_NAME" | cut -f1)"
    
    echo ""
    echo "🎉 Build completed successfully!"
    echo ""
    echo "📱 Next steps:"
    echo "1. Open Xcode"
    echo "2. Go to Window → Organizer"
    echo "3. Select your archive: $ARCHIVE_NAME"
    echo "4. Click 'Distribute App'"
    echo "5. Choose 'App Store Connect'"
    echo "6. Follow the upload process"
    echo ""
    echo "💡 If you still get dSYM errors, try disabling bitcode in App Store Connect"
else
    echo "❌ Archive was not created. Please check the build logs above."
    exit 1
fi 