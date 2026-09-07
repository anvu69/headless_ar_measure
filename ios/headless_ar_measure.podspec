#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint headless_ar_measure.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name = 'headless_ar_measure'
  s.version = '0.3.0'
  s.summary = 'Headless iOS AR measurement: status and distance as a stream.'
  s.description      = <<-DESC
Wraps an ARKit camera surface into a typed Dart stream of status and
distance samples. No text of its own, no exceptions, no network calls.
                       DESC
  s.homepage = 'https://github.com/anvu69/headless_ar_measure'
  s.license = { :file => '../LICENSE' }
  s.author = { 'anvu69' => 'anvu69@users.noreply.github.com' }
  s.source = { :path => '.' }
  s.source_files = 'headless_ar_measure/Sources/headless_ar_measure/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # Bản kê khai quyền riêng tư: gói này KHÔNG thu thập gì. Kê khai rõ chuyện đó
  # đỡ cho app dùng gói một câu phải tự trả lời khi nộp App Store.
  s.resource_bundles = {'headless_ar_measure_privacy' => ['headless_ar_measure/Sources/headless_ar_measure/PrivacyInfo.xcprivacy']}
end
