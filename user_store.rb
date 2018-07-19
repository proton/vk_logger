require './common.rb'

class UserStore
  attr_reader :filepath

  def initialize(filepath)
    @filepath = filepath
  end

  def [](user_id)
    users[user_id]
  end

  def []=(user_id, user)
    users[user_id] = user
  end

  def save
    File.open(filepath, 'w+') do |f|
      r = fix_unicode(users.to_json)
      f.write(r)
    end
  end

  private

  def users
    @users ||= load_users
  end

  def load_users
    users = {}
    if File.exist?(filepath)
      h = read_json(filepath)
      h.each { |k, v| users[k.to_i] = v }
    end
    users
  end
end
