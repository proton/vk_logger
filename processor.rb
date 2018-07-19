class Processor
  attr_reader :token, :user_name

  def initialize(token:, user_name:)
    @token = token
    @user_name = user_name
  end

  def call
    Dir.mkdir(json_dir) unless Dir.exist? json_dir
    Dir.mkdir(txt_dir) unless Dir.exist? txt_dir

    @changes = []

    dlg_offset = 0
    loop do
      p ["#{__FILE__}:#{__LINE__}", { count: 200, offset: dlg_offset }, token]
      r = retrier { api.messages.get_dialogs(count: 200, offset: dlg_offset) }
      p ["#{__FILE__}:#{__LINE__}", r] unless r.items
      
      break if !r.items || r.items.empty?
      r.items.each do |dlg_item|
        dlg = dlg_item.message
        key = dlg.chat_id ? "chat#{dlg.chat_id}" : "user#{dlg.user_id}"
        path = "#{json_dir}#{key}.json"
        if File.exist?(path)
          h = JSON.parse File.open(path).read.force_encoding('utf-8')
          h = Hashie::Mash.new(h)
        else
          h = Hashie::Mash.new
          h.user_id = dlg.user_id
          h.chat_id = dlg.chat_id
          h.messages = []
        end

        next if h.messages.last && h.messages.last.id >= dlg.id
        @changes << key

        start_id = dlg.id
        new_messages = []
        break_flag = false
        until break_flag
          params = { offset: 0, count: 200, start_message_id: start_id }
          if h.chat_id
            params[:chat_id] = h.chat_id
          else
            params[:user_id] = h.user_id
          end

          r = retrier { api.messages.get_history(params) }
          r.items.each do |item|
            puts [key, item.id, item.date].inspect
            @h = h
            @params = params
            @r = r
            @new_messages = new_messages
            if !h.messages.empty? && item.id < h.messages.last.id
              break_flag = true
              break
            end
            next if !new_messages.empty? && ((new_messages.last[:id])..(new_messages.first[:id])).cover?(item.id)

            start_id = item.id
            content = item.body
            if item.attachments
              if item.attachments.size == 1 && item.attachments[0]['type'] == 'sticker'
                att = item.attachments[0].sticker
                content += " stiker: #{att.photo_512 || att.photo_64}"
              else
                content += " #{item.attachments.inspect}"
              end
            end
            content += " #{item.fwd_messages.inspect}" if item.fwd_messages
            msg = { from: item.from_id, date: Time.at(item.date), id: item.id, out: item.out, content: content }
            new_messages << msg
          end
          break if r.items.size < 100
        end
        h.messages += new_messages.uniq.reverse
        h.messages.uniq!

        File.open(path, 'w+') do |f|
          f.write(h.to_json.gsub(/\\u([0-9a-z]{4})/) { |s| [$1.to_i(16)].pack('U') })
        end
      end
      dlg_offset += 200
    end

    users = {}
    user_db_path = "#{json_dir}/users.db"
    if File.exist?(user_db_path)
      h = read_json(user_db_path)
      h.each { |k, v| users[k.to_i] = v }
    end

    @changes.map { |f| "#{json_dir}/#{f}.json" }.each do |path| # Dir[dir+'*.json']
      h = JSON.parse File.open(path).read.force_encoding('utf-8')
      h = Hashie::Mash.new(h)
      txt = h.messages.map do |message|
        unless users[message.from]
          blank_user = Hashie::Mash.new
          blank_user.first_name = "user_#{message.from}"
          u = retrier { api.users.get(user_ids: message.from).first } || blank_user
          users[message.from] = u ? "#{u.first_name} #{u.last_name}" : message.from
        end
        "(#{message.date.split(' +').first}) #{users[message.from]}: #{message.content}"
      end.join('\n') + '\n'

      File.open("#{txt_dir}/#{File.basename(path, '.json')}.txt", 'w+') do
        |f| f.write(txt)
      end
    end
    File.open(user_db_path, 'w+') do |f|
      r = users.to_json.gsub(/\\u([0-9a-z]{4})/) do |_s|
        [$1.to_i(16)].pack('U')
      end
      f.write(r)
    end
  end

  private

  def retrier
    r = nil
    begin
      r = yield
    rescue => err
      return nil if err.is_a?(VkontakteApi::Error) && err.error_code == 113
      puts err
      sleep 1
      retry
    end
    r
  end

  def json_dir
    "#{__dir__}/var/#{user_name}/"
  end

  def txt_dir
    "#{json_dir}/txt/"
  end

  def api
    @api ||= VkontakteApi::Client.new(token)
  end
end
