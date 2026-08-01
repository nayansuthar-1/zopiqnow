#
# The iOS half of the live order card.
#
# `s.ios.deployment_target` is 14.0, matching the three apps, and **not** the
# 16.1 that ActivityKit requires. That is deliberate: the plugin has to compile
# and register on every device the apps support, and refuse politely on the ones
# too old for a Live Activity. Every ActivityKit call is behind
# `if #available(iOS 16.1, *)`; raising the target here instead would drag all
# three apps' floor up for one optional flourish.
#
Pod::Spec.new do |s|
  s.name             = 'zopiq_live_card'
  s.version          = '0.1.0'
  s.summary          = 'The live order card, drawn natively.'
  s.description      = <<-DESC
The live order card: a segmented delivery tracker drawn as a notification on
Android, and as an ActivityKit Live Activity on iOS.
                       DESC
  s.homepage         = 'https://zopiq.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Siteonlab' => 'hello@siteonlab.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '14.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
