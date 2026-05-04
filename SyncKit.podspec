Pod::Spec.new do |s|
  s.name             = 'SyncKit'
  s.version          = '2.0.0'
  s.summary          = 'CloudKit synchronization for your RealmSwift model.'

  s.description      = <<-DESC
SyncKit automates the process of synchronizing your RealmSwift models using CloudKit. It can easily be plugged into (and removed from) your existing stack.
                       DESC

  s.homepage         = 'https://github.com/mentrena/SyncKit'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Manuel Entrena' => 'manuel@mentrena.com' }
  s.source           = { :git => 'https://github.com/mentrena/SyncKit.git', :tag => s.version.to_s }
  s.swift_version    = '5.0'
  s.module_name		 = 'SyncKit'

  s.ios.deployment_target = '12.0'
  s.osx.deployment_target = '10.13'
  s.tvos.deployment_target = '12.0'
  s.watchos.deployment_target = '4.0'

  s.source_files = 'SyncKit/Classes/**/*.swift'
  s.frameworks = 'CloudKit'
  s.dependency 'RealmSwift', '~> 20.0'
end
