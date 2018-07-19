require './common.rb'

class MessageFormer
  attr_reader :item
  delegate :id, :out, :attachments, to: :item

  def initialize(item)
    @item = item
  end

  def call
    {
      from: from,
      date: date,
      id: id,
      out: out,
      content: content
    }
  end

  private

  def from
    item.from_id
  end

  def date
    Time.at(item.date)
  end

  def content
    @content ||= build_content
  end

  def build_content
    text = item.body
    text += " #{attachments_content}" if attachments
    text += " #{item.fwd_messages.inspect}" if item.fwd_messages
    text
  end

  def attachments_content
    if attachments.size == 1 && attachments[0]['type'] == 'sticker'
      att = attachments[0].sticker
      return "stiker: #{att.photo_512 || att.photo_64}"
    end
    attachments.inspect
  end
end
