#!/bin/bash

# Fix TransactionStatus.confirming calls missing label
echo "Fixing TransactionStatus.confirming calls..."
find DashPayiOSTests -name "*.swift" -exec sed -i '' 's/\.confirming(\([0-9]*\))/.confirming(confirmations: \1)/g' {} \;

# Fix LocalBalance type references in tests
echo "Fixing Balance -> LocalBalance references..."
find DashPayiOSTests -name "*.swift" -exec sed -i '' 's/Balance(/LocalBalance(/g' {} \;

echo "Done fixing test issues"