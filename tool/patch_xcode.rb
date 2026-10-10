#!/usr/bin/env ruby
# يضبط مشروع Xcode بعد توليده (يعمل على macOS — gem xcodeproj يأتي مع CocoaPods):
#  - Bundle ID: online.ghanigroup.app
#  - iPhone فقط (TARGETED_DEVICE_FAMILY = 1)
#  - أقل إصدار iOS 15.0 (متطلب Firebase)
#  - Runner.entitlements للإشعارات الفورية إذا كان Firebase مفعّلاً
#  - إضافة PrivacyInfo.xcprivacy إلى موارد التطبيق (مطلوب من Apple)
require 'xcodeproj'

BUNDLE_ID = 'online.ghanigroup.app'
root = File.expand_path('..', __dir__)
project_path = File.join(root, 'ios', 'Runner.xcodeproj')
abort("[xcode] #{project_path} not found — run flutter create first") unless File.exist?(project_path)

project = Xcodeproj::Project.open(project_path)
runner = project.targets.find { |t| t.name == 'Runner' } or abort('[xcode] Runner target not found')

runner.build_configurations.each do |c|
  s = c.build_settings
  s['PRODUCT_BUNDLE_IDENTIFIER'] = BUNDLE_ID
  s['TARGETED_DEVICE_FAMILY'] = '1'
  s['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
  s['SUPPORTS_MACCATALYST'] = 'NO'
  s['SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD'] = 'NO'
  s['SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD'] = 'NO'
  s['INFOPLIST_KEY_CFBundleDisplayName'] = 'Ghani Group'
  s['INFOPLIST_KEY_LSApplicationCategoryType'] = 'public.app-category.business'
end

project.targets.select { |t| t.name == 'RunnerTests' }.each do |t|
  t.build_configurations.each { |c| c.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = "#{BUNDLE_ID}.RunnerTests" }
end

project.build_configurations.each { |c| c.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0' }

group = project.main_group['Runner'] || project.main_group.new_group('Runner', 'Runner')
unless group.files.any? { |f| f.path == 'PrivacyInfo.xcprivacy' }
  ref = group.new_reference('PrivacyInfo.xcprivacy')
  runner.resources_build_phase.add_file_reference(ref, true)
  puts '[xcode] PrivacyInfo.xcprivacy added to Runner resources'
end

# الإشعارات الفورية: يولّده tool/firebase_setup.py فقط عند وجود إعداد Firebase لـ iOS
entitlements = File.join(root, 'ios', 'Runner', 'Runner.entitlements')
runner.build_configurations.each do |c|
  if File.exist?(entitlements)
    c.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
  else
    c.build_settings.delete('CODE_SIGN_ENTITLEMENTS')
  end
end
if File.exist?(entitlements) && group.files.none? { |f| f.path == 'Runner.entitlements' }
  group.new_reference('Runner.entitlements')
end

project.save
puts "[xcode] Runner: #{BUNDLE_ID}, iPhone only, iOS 15.0+#{File.exist?(entitlements) ? ', Push' : ''} ✓"
