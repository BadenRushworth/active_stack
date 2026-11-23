# frozen_string_literal: true

source "https://rubygems.org"

gemspec

gem "rspec", "~> 3.13"

# Termux (Android) needs these pins; other environments don't.
if ENV["PREFIX"].to_s.include?("com.termux")
  gem "tzinfo-data"
  gem "nokogiri", "1.18.10"
end
