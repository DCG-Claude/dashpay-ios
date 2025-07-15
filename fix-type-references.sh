#!/bin/bash

# Replace SwiftDashCoreSDK.Type with just Type
FILES=$(find /Users/quantum/src/dashpay-ios/DashPayiOS -name "*.swift" -type f -exec grep -l "SwiftDashCoreSDK\." {} \;)

for file in $FILES; do
    echo "Processing $file"
    # Replace SwiftDashCoreSDK.Transaction with Transaction
    sed -i '' 's/SwiftDashCoreSDK\.Transaction/Transaction/g' "$file"
    # Replace SwiftDashCoreSDK.UTXO with UTXO
    sed -i '' 's/SwiftDashCoreSDK\.UTXO/UTXO/g' "$file"
    # Replace any other SwiftDashCoreSDK references
    sed -i '' 's/SwiftDashCoreSDK\.//g' "$file"
done

echo "Done fixing type references"