require "vkontakte_api"
require "hashie"
require "openssl"

OpenSSL::SSL::VERIFY_PEER = OpenSSL::SSL::VERIFY_NONE

Encoding.default_internal = Encoding::UTF_8
Encoding.default_external = Encoding::UTF_8

#получаем токен https://vk.com/dev/standalone https://vk.com/dev/permissions (offline)

@main_dir = File.expand_path(File.dirname(__FILE__))

def read_json(filepath)
  content = File.open(filepath).read.force_encoding("utf-8")
  JSON.parse(content)
end

vk_app_config = read_json("config/vk_app.json")

VkontakteApi.configure do |config|
  config.app_id = vk_app_config["app_id"]
  config.app_secret = vk_app_config["app_secret"]
  config.redirect_uri = "http://oauth.vk.com/blank.html"
  config.api_version = 5.14
end

# url = VkontakteApi.authorization_url(type: :client, scope: %i[groups photos video friends wall audio offline messages])
# puts url

def retrier
  r = nil
  begin
    r = yield
  rescue
    if $!.is_a?(VkontakteApi::Error) && $!.error_code == 113
      return nil
    else
      puts $!
      sleep 1
      retry
    end
  end
  r
end

def processor(token, kname)
  api = VkontakteApi::Client.new(token)

  dir = "#{@main_dir}/var/#{kname}/"
  txt_dir = "#{dir}/txt/"
  Dir.mkdir(dir) unless Dir.exist? dir
  Dir.mkdir(txt_dir) unless Dir.exist? txt_dir

  @changes = []

  dlg_offset = 0
  loop do
    puts __LINE__
    p [{count: 200, offset: dlg_offset}, token]
    r = retrier { api.messages.get_dialogs(count: 200, offset: dlg_offset) }
    unless r.items
      p __LINE__
      p r
    end
    break if (!r.items || r.items.empty?)
    r.items.each do |dlg_item|
      dlg = dlg_item.message
      key = dlg.chat_id ? "chat#{dlg.chat_id}" : "user#{dlg.user_id}"
      path = "#{dir}#{key}.json"
      if File.exist?(path)
        #puts path
        h = JSON.parse File.open(path).read.force_encoding("utf-8")
        h = Hashie::Mash.new(h)
      else
        h = Hashie::Mash.new
        h.user_id = dlg.user_id
        h.chat_id = dlg.chat_id
        h.messages = []
      end

      next if h.messages.last && h.messages.last.id >= dlg.id
      @changes << key

      #Идея: идём вниз, пока не упрёмся в последний id

      start_id = dlg.id
      new_messages = []
      break_flag = false
      until break_flag
        params = {offset: 0, count: 200, start_message_id: start_id}
        if h.chat_id
          params[:chat_id] = h.chat_id
        else
          params[:user_id] = h.user_id
        end

        r = retrier { api.messages.get_history(params) }
        r.items.each do |item|
          puts [key, item.id, item.date].inspect
          $h = h
          $params = params
          $r = r
          $new_messages = new_messages
          if h.messages.size > 0 && item.id < h.messages.last.id
            break_flag = true
            break
          end
          next if new_messages.size > 0 && ((new_messages.last[:id])..(new_messages.first[:id])).include?(item.id)

          start_id = item.id
          content = item.body
          if item.attachments
            if item.attachments.size == 1 && item.attachments[0]["type"] == "sticker"
              att = item.attachments[0].sticker
              content += " stiker: #{att.photo_512 || att.photo_64}"
            else
              content += " #{item.attachments.inspect}"
            end
          end
          content += " #{item.fwd_messages.inspect}" if item.fwd_messages
          new_messages << {from: item.from_id, date: Time.at(item.date), id: item.id, out: item.out, content: content}
        end
        break if r.items.size < 100
      end
      h.messages += new_messages.uniq.reverse
      h.messages.uniq!

      File.open(path, "w+") { |f| f.write(h.to_json.gsub(/\\u([0-9a-z]{4})/) { |s| [$1.to_i(16)].pack("U") }) }
    end
    dlg_offset += 200
  end

  #print

  users = {}
  users_path = "#{dir}users.db"
  if File.exist?(users_path)
    h = read_json(users_path)
    h.each { |k, v| users[k.to_i] = v }
  end

  for path in @changes.map { |f| "#{dir}/#{f}.json" } #Dir[dir+'*.json']
    h = JSON.parse File.open(path).read.force_encoding("utf-8")
    h = Hashie::Mash.new(h)
    txt = h.messages.map do |message|
      unless users[message.from]
        blank_user = Hashie::Mash.new
        blank_user.first_name = "user_#{message.from}"
        u = retrier { api.users.get(user_ids: message.from).first } || blank_user
        users[message.from] = u ? "#{u.first_name} #{u.last_name}" : message.from
      end
      "(#{message.date.split(" +").first}) #{users[message.from]}: #{message.content}"
    end.join("\n") + "\n"

    File.open("#{txt_dir}/#{File.basename(path, ".json")}.txt", "w+") { |f| f.write(txt) }
  end
  File.open(users_path, "w+") { |f| f.write(users.to_json.gsub(/\\u([0-9a-z]{4})/) { |s| [$1.to_i(16)].pack("U") }) }
end

tokens = read_json("config/tokens.json")

#threads = []
loop do
  puts "iter"
  tokens.each do |kname, token|
    p [kname, token]
    #threads << Thread.new { processor(token,kname) }
    processor(token, kname)
  end
  puts "iter end #{Time.now}"
  sleep 300
end
#threads.each(&:join)
