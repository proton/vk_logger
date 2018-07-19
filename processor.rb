require './common.rb'
require './user_store.rb'
require './message_former.rb'

class Processor
  attr_reader :token, :user_name

  def initialize(token:, user_name:)
    @token = token
    @user_name = user_name
  end

  def call
    create_dirs
    @changes = []
    main_loop
    generate_texts
    user_store.save
  end

  private

  def main_loop
    dlg_offset = 0
    loop do
      args = { count: 200, offset: dlg_offset }
      p ["#{__FILE__}:#{__LINE__}", args, token]
      r = retrier { api.messages.get_dialogs(args) }
      p ["#{__FILE__}:#{__LINE__}", r] unless r.items

      break if r.items.nil? || r.items.empty?
      r.items.each do |dlg_item|
        process_dialog(dlg_item)
      end
      dlg_offset += 200
    end
  end

  def generate_texts
    @changes.map { |f| "#{json_dir}/#{f}.json" }.each do |path|
      generate_text(path)
    end
  end

  def generate_text(jsonpath)
    h = read_json(jsonpath)
    h = Hashie::Mash.new(h)
    txt = h.messages.map do |message|
      user_id = message.from
      unless user_store[message.from]
        blank_user = Hashie::Mash.new(first_name: "user_#{user_id}")
        u = retrier { api.users.get(user_ids: user_id).first } || blank_user
        user_store[user_id] = "#{u.first_name} #{u.last_name}".strip
      end
      timestamp = message.date.split(' +').first
      user_name = users[user_id]
      "(#{timestamp}) #{user_name}: #{message.content}"
    end.join('\n') + '\n'

    txtpath = "#{txt_dir}/#{File.basename(jsonpath, '.json')}.txt"
    File.open(txtpath, 'w+') { |f| f.write txt }
  end

  def create_dirs
    [json_dir, txt_dir].each do |dir|
      Dir.mkdir(dir) unless Dir.exist? json_dir
    end
  end

  def process_dialog(dlg_item)
    dlg = dlg_item.message
    key = dlg.chat_id ? "chat#{dlg.chat_id}" : "user#{dlg.user_id}"
    dialog_path = "#{json_dir}#{key}.json"

    if File.exist?(dialog_path)
      h = read_json(dialog_path)
      h = Hashie::Mash.new(h)
    else
      h = Hashie::Mash.new
      h.user_id = dlg.user_id
      h.chat_id = dlg.chat_id
      h.messages = []
    end

    return if h.messages.last && h.messages.last.id >= dlg.id
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
        if !h.messages.empty? && item.id < h.messages.last.id
          break_flag = true
          break
        end
        next if !new_messages.empty? &&
                ((new_messages.last[:id])..(new_messages.first[:id])).cover?(item.id)

        start_id = item.id
        new_messages << MessageFormer.new(item).call
      end
      break if r.items.size < 100
    end
    h.messages += new_messages.uniq.reverse
    h.messages.uniq!

    File.open(dialog_path, 'w+') do |f|
      r = fix_unicode(h.to_json)
      f.write(r)
    end
  end

  def retrier
    r = nil
    begin
      r = yield
    rescue Error => err
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

  def user_store
    @user_store ||= UserStore.new("#{json_dir}/users.db")
  end
end
