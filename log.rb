require 'vkontakte_api'
require 'hashie'
require 'openssl'

require './common.rb'
require './processor.rb'

OpenSSL::SSL::VERIFY_PEER = OpenSSL::SSL::VERIFY_NONE

Encoding.default_internal = Encoding::UTF_8
Encoding.default_external = Encoding::UTF_8

vk_app_config = read_json('config/vk_app.json')

VkontakteApi.configure do |config|
  config.app_id = vk_app_config['app_id']
  config.app_secret = vk_app_config['app_secret']
  config.redirect_uri = 'http://oauth.vk.com/blank.html'
  config.api_version = 5.14
end

# scopes = %i[groups photos video friends wall audio offline messages]
# url = VkontakteApi.authorization_url(type: :client, scope: scopes)
# puts url

tokens = read_json('config/tokens.json')

loop do
  puts 'iter'
  tokens.each do |user_name, token|
    p [user_name, token]
    Processor.new(token: token, user_name: user_name).call
  end
  puts "iter end #{Time.now}"
  sleep 300
end
