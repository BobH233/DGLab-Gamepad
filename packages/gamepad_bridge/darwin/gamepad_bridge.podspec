Pod::Spec.new do |s|
  s.name = 'gamepad_bridge'
  s.version = '0.1.0'
  s.summary = 'System game controller input.'
  s.description = 'Streams game controller snapshots from Apple GameController.'
  s.homepage = 'https://developer.apple.com/documentation/gamecontroller'
  s.license = { :type => 'Proprietary' }
  s.author = { 'DG-LAB' => 'development@localhost' }
  s.source = { :path => '.' }
  s.source_files = 'Classes/**/*.swift'
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.ios.deployment_target = '14.0'
  s.osx.deployment_target = '11.0'
  s.swift_version = '5.0'
  s.frameworks = 'GameController'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
