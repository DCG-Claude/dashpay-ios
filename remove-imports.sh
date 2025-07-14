#!/bin/bash

# Remove SwiftDashCoreSDK and KeyWalletFFI imports from all files
FILES=$(find /Users/quantum/src/dashpay-ios/DashPayiOS -name "*.swift" -type f ! -path "*/SwiftDashCoreSDK/*" ! -path "*/KeyWalletFFI/*" -exec grep -l "import SwiftDashCoreSDK\|import KeyWalletFFI" {} \;)

for file in $FILES; do
    echo "Processing $file"
    # Remove the import lines
    sed -i '' '/^import SwiftDashCoreSDK$/d' "$file"
    sed -i '' '/^import KeyWalletFFISwift$/d' "$file"
    sed -i '' '/^import KeyWalletFFI$/d' "$file"
done

echo "Done removing imports"