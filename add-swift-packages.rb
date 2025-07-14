#!/usr/bin/env ruby

require 'xcodeproj'
require 'json'

# Open the Xcode project
project_path = 'DashPayiOS.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Find the main target
main_target = project.targets.find { |t| t.name == 'DashPayiOS' }

if main_target.nil?
  puts "Error: Could not find DashPayiOS target"
  exit 1
end

# Add Swift Package reference
package_ref = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
package_ref.repositoryURL = '../rust-dashcore/swift-dash-core-sdk'
package_ref.requirement = {
  'kind' => 'branch',
  'branch' => 'main'
}

# Add to project's package references
project.root_object.package_references ||= []
project.root_object.package_references << package_ref

# Add package products to target
swift_dash_core_dep = main_target.new_package_product_dependency(package_ref, 'SwiftDashCoreSDK')
key_wallet_dep = main_target.new_package_product_dependency(package_ref, 'KeyWalletFFISwift')

main_target.package_product_dependencies ||= []
main_target.package_product_dependencies << swift_dash_core_dep
main_target.package_product_dependencies << key_wallet_dep

# Save the project
project.save

puts "Successfully added Swift package dependencies!"
puts "- SwiftDashCoreSDK"
puts "- KeyWalletFFISwift"