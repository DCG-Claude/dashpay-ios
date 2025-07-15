# Quick Start: Updating FFI Libraries

## First Time Setup

1. **Build the libraries**:
   ```bash
   ./build-ios-libs.sh
   ```
   This takes a few minutes and creates all necessary libraries.

2. **Done!** The libraries are now in `DashPayiOS/Libraries/` and ready to use.

## Daily Development

By default, the libraries are configured for **iOS Simulator** (most common for development).

If you need to build for a **real device**:
```bash
./select-library.sh ios
# Then clean build folder in Xcode (⇧⌘K)
```

To switch back to **simulator**:
```bash
./select-library.sh sim
# Then clean build folder in Xcode (⇧⌘K)
```

## Updating Libraries

When rust-dashcore has updates:
```bash
cd ../rust-dashcore
git pull
cd ../dashpay-ios
./build-ios-libs.sh
```

## Troubleshooting

**"Library not found" error**: Run `./build-ios-libs.sh`

**"Building for iOS Simulator, but linking in object file built for iOS"**: 
- Run `./select-library.sh sim`
- Clean build folder (⇧⌘K)

**App crashes or shows 0 peers**: Your libraries are outdated, run `./build-ios-libs.sh`

## That's it! 

The manual approach is simple and reliable. No Xcode build phase magic needed.