# DAPI Endpoint Management System

This directory contains the dynamic DAPI endpoint management system that replaces hardcoded endpoint URLs with a runtime-configurable, health-checked, and fault-tolerant solution.

## Overview

The system consists of three main components:

1. **DAPIConfigurationService** - Fetches endpoint configurations from various sources
2. **DAPIHealthChecker** - Monitors endpoint health and provides fallback logic
3. **DAPIEndpointManager** - Unified interface combining configuration and health checking

## Components

### DAPIConfigurationService

Responsible for fetching DAPI endpoint configurations from multiple sources:

- **Remote JSON** - Fetches from remote URLs (default for testnet/mainnet)
- **Environment Variables** - Reads from environment variables (default for devnet)
- **Plist Files** - Reads from bundled plist files (for static configurations)

#### Configuration Sources

```swift
enum ConfigurationSource {
    case remote(URL)           // Fetch from remote JSON endpoint
    case plist(String)         // Read from bundled plist file
    case environment(String)   // Read from environment variable
}
```

#### Default Sources by Network

- **Testnet**: `https://config.dash.org/testnet/dapi-endpoints.json`
- **Mainnet**: `https://config.dash.org/mainnet/dapi-endpoints.json`
- **Devnet**: `DAPI_ENDPOINTS_DEVNET` environment variable

### DAPIHealthChecker

Monitors endpoint health and provides intelligent fallback logic:

#### Features

- **Concurrent Health Checks** - Tests multiple endpoints simultaneously
- **Response Time Tracking** - Sorts endpoints by performance
- **Caching** - Caches health results for 60 seconds
- **Fallback Logic** - Automatically falls back to healthy alternatives

#### Health Check Process

1. Performs HTTP GET requests to each endpoint
2. Considers 2xx-4xx responses as healthy (server responding)
3. Considers 5xx responses and connection failures as unhealthy
4. Tracks response times for performance sorting
5. Caches results to avoid excessive network calls

### DAPIEndpointManager

Unified interface that combines configuration and health checking:

#### Key Methods

```swift
// Get healthy endpoints as comma-separated string (for FFI)
func getHealthyEndpointsString() async -> String

// Get healthy endpoints as array
func getHealthyEndpoints() async -> [String]

// Get single best endpoint
func getBestEndpoint() async -> String?

// Generate connectivity report
func getConnectivityReport() async -> DAPIConnectivityReport

// Refresh configuration and health cache
func refreshEndpoints() async
```

## Usage

### Basic Usage

```swift
let endpointManager = DAPIEndpointManager(network: .testnet)
let healthyEndpoints = await endpointManager.getHealthyEndpointsString()
```

### Custom Configuration Source

```swift
let customSource = DAPIConfigurationService.ConfigurationSource.plist("CustomEndpoints")
let endpointManager = DAPIEndpointManager(network: .testnet, configurationSource: customSource)
```

### Health Monitoring

```swift
let report = await endpointManager.getConnectivityReport()
print("Network: \(report.network)")
print("Healthy endpoints: \(report.healthyEndpoints)/\(report.totalEndpoints)")
```

## Configuration Formats

### Remote JSON Format

```json
{
  "endpoints": [
    "https://seed-1.testnet.networks.dash.org:1443",
    "https://seed-2.testnet.networks.dash.org:1443",
    "https://seed-3.testnet.networks.dash.org:1443"
  ]
}
```

### Environment Variable Format

```bash
export DAPI_ENDPOINTS_DEVNET="http://127.0.0.1:3000,http://127.0.0.1:3001"
```

### Plist Format

See `DashPayiOS/Resources/DAPIEndpoints.plist` for an example.

## Fallback Strategy

The system implements a multi-tier fallback strategy:

1. **Primary**: Configured endpoints from remote/plist/environment
2. **Health Check**: Only healthy endpoints are used
3. **Performance Sort**: Endpoints sorted by response time
4. **Fallback**: Hardcoded fallback endpoints if all else fails

## Error Handling

The system gracefully handles various failure scenarios:

- **Network Unavailable**: Falls back to cached or hardcoded endpoints
- **Invalid Configuration**: Uses fallback endpoints
- **All Endpoints Unhealthy**: Returns fallback endpoints for emergency use
- **Timeout**: Uses cached results or fallback endpoints

## Performance

- **Caching**: Configuration and health results are cached
- **Concurrent Checks**: Health checks run in parallel
- **Timeout Limits**: Configurable timeouts prevent hanging
- **Efficient Fallback**: Quick failover to healthy endpoints

## Testing

Comprehensive unit tests cover:

- Configuration fetching from all sources
- Health checking with various endpoint states
- Fallback logic and error handling
- Performance and caching behavior
- Integration testing of the complete system

Run tests with:
```bash
xcodebuild test -project DashPayiOS.xcodeproj -scheme DashPayiOS -only-testing:DashPayiOSTests/DAPIEndpointManagerTests
```

## Migration from Hardcoded Endpoints

The old hardcoded approach:
```swift
let testnetAddresses = [
    "https://seed-1.testnet.networks.dash.org:1443",
    // ... more hardcoded URLs
].joined(separator: ",")
```

The new dynamic approach:
```swift
let endpointManager = DAPIEndpointManager(network: network)
let dapiAddresses = await endpointManager.getHealthyEndpointsString()
```

## Benefits

1. **Flexibility**: Easy to update endpoints without code changes
2. **Reliability**: Automatic health checking and fallback
3. **Performance**: Endpoints sorted by response time
4. **Maintainability**: Centralized endpoint management
5. **Testability**: Comprehensive test coverage with mocking support
6. **Monitoring**: Built-in connectivity reporting

## Future Enhancements

- Load balancing across healthy endpoints
- Weighted endpoint selection
- Geographic endpoint selection
- Real-time monitoring dashboards
- Automated endpoint discovery