#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"
require "cgi"

project_path = ARGV.fetch(0, "project.yml")
project = YAML.load_file(project_path)
targets = project.fetch("targets")
failures = []

direct = targets.fetch("ThermFlowApp")
mas = targets.fetch("ThermFlowAppStore")
daemon = targets.fetch("ThermFlowDaemon")
widget = targets.fetch("ThermFlowWidget")

dependency_names = lambda do |target|
  Array(target["dependencies"]).map do |dependency|
    dependency.is_a?(Hash) ? dependency["target"] : dependency
  end.compact
end

setting = lambda do |target, name|
  target_settings = target["settings"] || {}
  project_settings = (project["settings"] || {})["base"] || {}
  target_settings.key?(name) ? target_settings[name] : project_settings[name]
end

enabled = lambda do |value|
  value == true || value.to_s.casecmp("yes").zero?
end

direct_dependencies = dependency_names.call(direct)
mas_dependencies = dependency_names.call(mas)

failures << "Direct target must depend on ThermFlowDaemon" unless direct_dependencies.include?("ThermFlowDaemon")
failures << "Mac App Store target must not depend on ThermFlowDaemon" if mas_dependencies.include?("ThermFlowDaemon")
failures << "Direct target must embed ThermFlowWidget" unless direct_dependencies.include?("ThermFlowWidget")
failures << "Mac App Store target must embed ThermFlowWidget" unless mas_dependencies.include?("ThermFlowWidget")

direct_scripts = Array(direct["postBuildScripts"]).map { |entry| entry.is_a?(Hash) ? entry["script"].to_s : entry.to_s }.join("\n")
mas_scripts = Array(mas["postBuildScripts"]).map { |entry| entry.is_a?(Hash) ? entry["script"].to_s : entry.to_s }.join("\n")
failures << "Direct target must embed the privileged helper" unless direct_scripts.include?("Library/LaunchServices/com.coolcumber.helper")
failures << "Direct target must embed its launchd plist" unless direct_scripts.include?("Library/LaunchDaemons/com.coolcumber.helper.plist")
failures << "Mac App Store target must not embed privileged helper assets" if mas_scripts.match?(/coolcumber\.helper|LaunchDaemons|PrivilegedHelperTools/)

mas_conditions = setting.call(mas, "SWIFT_ACTIVE_COMPILATION_CONDITIONS").to_s.split
direct_conditions = setting.call(direct, "SWIFT_ACTIVE_COMPILATION_CONDITIONS").to_s.split
failures << "Mac App Store target must compile with APPSTORE" unless mas_conditions.include?("APPSTORE")
failures << "Direct target must not compile with APPSTORE" if direct_conditions.include?("APPSTORE")
failures << "Direct target must not enable App Sandbox" if enabled.call(setting.call(direct, "ENABLE_APP_SANDBOX"))
failures << "Direct target must enable Hardened Runtime" unless enabled.call(setting.call(direct, "ENABLE_HARDENED_RUNTIME"))
failures << "Direct target must use ThermFlowApp/Direct.entitlements" unless setting.call(direct, "CODE_SIGN_ENTITLEMENTS") == "ThermFlowApp/Direct.entitlements"
failures << "Mac App Store target must enable App Sandbox" unless enabled.call(setting.call(mas, "ENABLE_APP_SANDBOX"))
failures << "Mac App Store target must use ThermFlowApp/AppStore.entitlements" unless setting.call(mas, "CODE_SIGN_ENTITLEMENTS") == "ThermFlowApp/AppStore.entitlements"
failures << "Widget target must enable App Sandbox" unless enabled.call(setting.call(widget, "ENABLE_APP_SANDBOX"))
failures << "Widget target must use ThermFlowWidget/Widget.entitlements" unless setting.call(widget, "CODE_SIGN_ENTITLEMENTS") == "ThermFlowWidget/Widget.entitlements"
failures << "Widget target must enable Hardened Runtime" unless enabled.call(setting.call(widget, "ENABLE_HARDENED_RUNTIME"))
failures << "Privileged helper must enable Hardened Runtime" unless enabled.call(setting.call(daemon, "ENABLE_HARDENED_RUNTIME"))

expected_app_group = "group.com.slmcamp.CoolCumber"
{
  "ThermFlowApp/Direct.entitlements" => direct,
  "ThermFlowApp/AppStore.entitlements" => mas,
  "ThermFlowWidget/Widget.entitlements" => widget
}.each_key do |entitlements_path|
  absolute_path = File.expand_path(entitlements_path, File.dirname(File.expand_path(project_path)))
  unless File.file?(absolute_path) && File.read(absolute_path).include?(expected_app_group)
    failures << "#{entitlements_path} must declare #{expected_app_group}"
  end
end

expected_version = ARGV[1]
expected_build = ARGV[2]
if expected_version || expected_build
  if expected_version.to_s.empty? || expected_build.to_s.empty?
    failures << "Expected marketing version and build number must be supplied together"
  else
    %w[ThermFlowApp ThermFlowAppStore ThermFlowWidget].each do |target_name|
      target = targets.fetch(target_name)
      actual_version = setting.call(target, "MARKETING_VERSION").to_s
      actual_build = setting.call(target, "CURRENT_PROJECT_VERSION").to_s
      failures << "#{target_name} MARKETING_VERSION must be #{expected_version}, got #{actual_version.empty? ? '(missing)' : actual_version}" unless actual_version == expected_version
      failures << "#{target_name} CURRENT_PROJECT_VERSION must be #{expected_build}, got #{actual_build.empty? ? '(missing)' : actual_build}" unless actual_build == expected_build
    end

    project_directory = File.dirname(File.expand_path(project_path))
    source_version_checks = {
      "ThermFlowApp" => {
        "CFBundleShortVersionString" => [expected_version, "$(MARKETING_VERSION)", "${MARKETING_VERSION}"],
        "CFBundleVersion" => [expected_build, "$(CURRENT_PROJECT_VERSION)", "${CURRENT_PROJECT_VERSION}"]
      },
      "ThermFlowWidget" => {
        "CFBundleShortVersionString" => [expected_version, "$(MARKETING_VERSION)", "${MARKETING_VERSION}"],
        "CFBundleVersion" => [expected_build, "$(CURRENT_PROJECT_VERSION)", "${CURRENT_PROJECT_VERSION}"]
      }
    }

    source_version_checks.each do |target_name, checks|
      info_path = targets.fetch(target_name).fetch("info").fetch("path")
      absolute_info_path = File.expand_path(info_path, project_directory)
      info_contents = File.read(absolute_info_path)
      checks.each do |key, allowed_values|
        match = info_contents.match(/<key>\s*#{Regexp.escape(key)}\s*<\/key>\s*<string>(.*?)<\/string>/m)
        actual = match ? CGI.unescapeHTML(match[1].strip) : nil
        next if allowed_values.include?(actual)

        failures << "#{info_path} #{key} must be #{allowed_values.join(' or ')}, got #{actual || '(missing)'}"
      end
    end
  end
end

if failures.empty?
  puts "Project channel boundary check passed."
else
  warn "Project channel boundary check failed:"
  failures.each { |failure| warn "  - #{failure}" }
  exit 1
end
