def read_json(filepath)
  content = File.open(filepath).read.force_encoding('utf-8')
  JSON.parse(content)
end

def fix_unicode(str)
  str.gsub(/\\u([0-9a-z]{4})/) { |_s| [$1.to_i(16)].pack('U') }
end
