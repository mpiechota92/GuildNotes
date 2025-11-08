#!/bin/bash

# Script to create a CurseForge-compatible release zip file
# Extracts version from GuildNotes.toc and creates GuildNotes-X.X.X.zip

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Extract version from line 4 of GuildNotes.toc
VERSION=$(sed -n '4p' GuildNotes.toc | sed 's/## Version: //' | tr -d '[:space:]')

if [ -z "$VERSION" ]; then
    echo "Error: Could not extract version from GuildNotes.toc"
    exit 1
fi

echo "Found version: $VERSION"

# Create zip filename
ZIP_NAME="GuildNotes-${VERSION}.zip"

# Remove existing zip if it exists
if [ -f "$ZIP_NAME" ]; then
    echo "Removing existing $ZIP_NAME"
    rm "$ZIP_NAME"
fi

# Create temporary directory
TEMP_DIR=$(mktemp -d)
GUILDNOTES_DIR="$TEMP_DIR/GuildNotes"
mkdir -p "$GUILDNOTES_DIR"

echo "Copying addon files to temporary directory..."

# Disable resource forks and extended attributes when copying (prevents __MACOSX)
export COPYFILE_DISABLE=1

# Copy all .lua and .toc files, excluding hidden files, git files, macOS files, and README.md
# Use -X flag with cp to exclude extended attributes
find . -maxdepth 1 -type f \( -name "*.lua" -o -name "*.toc" \) ! -name ".*" ! -name "README.md" | while read -r file; do
    cp -X "$file" "$GUILDNOTES_DIR/"
done

# Create the zip file from the GuildNotes directory
echo "Creating zip file: $ZIP_NAME"
cd "$TEMP_DIR"
# Use -X flag to exclude extra file attributes (prevents __MACOSX folder)
# Explicitly exclude __MACOSX, .DS_Store, .git directories, and all hidden files
zip -r -X "$SCRIPT_DIR/$ZIP_NAME" GuildNotes \
    -x "*.DS_Store" \
    -x "*/.git/*" \
    -x "*/.git*" \
    -x "*/__MACOSX/*" \
    -x "__MACOSX/*" \
    -x "*/.*" \
    -x "*README.md" > /dev/null

# Clean up temporary directory
rm -rf "$TEMP_DIR"

echo "Successfully created $ZIP_NAME"
echo "Ready for CurseForge upload!"

