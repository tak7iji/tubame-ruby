# encoding: utf-8

require 'nokogiri'
require 'csv'

$base_name = File.split(Dir.getwd)[1]

def const_file cond, file
  cond ? "" : File.join($base_name, file)
end

def search_regex type, key1, key2
  reg = (key2.empty? ? ["[.]*", key1] : [key1, key2]).map{|e| Regexp.new(e)}

  h = -> s  {s.is_a?(Array)}
  i = -> r  {r.any? && r.last == :C}
  f = ->(file, r, e) do
    (:N if (e[0].start_with?("//")) || (i[r] && e[0].end_with?("*/")))||
    (:C if (e[0].start_with?("/*") && !e[0].end_with?("*/")) || i[r])||
    ([const_file(r.any?(&h), file), e[1] + 1, e[0].gsub('"', '""')] if e[0] =~ reg[1])
  end.curry

  Dir.glob("**/#{type}").lazy.map do |file|
    g = f[file]
    lines = open(file).lazy.map(&:strip).to_a
    next if lines.lazy.grep(reg[0]).first.nil?

    lines.lazy.each_with_index.inject([]) do |r, e|
      r + [g[r, e]]
    end.compact.select(&h).to_a
  end.to_a.compact.flatten 1
end

def search_xpath type, key1, key2
  Dir.glob("**/#{type}").lazy.map do |file|
    body = open(file, "rt", &:read)
    Nokogiri.XML(body).xpath(key1).lazy.with_index.map do |node, idx|
      [const_file(idx != 0, file), node.line, body.split("\n")[node.line - 1].strip]
    end.to_a
  end.to_a.flatten 1
end

csv = CSV.open('result.csv', "wb", :encoding => 'Shift_JIS')
csv << ['ガイド章','検索手順','検索情報ID','ファイル名','行番号','コード内容']

xml = Nokogiri.XML(open(ARGV[0]))
xml.remove_namespaces!.xpath('//ChapterCategoryRefKey').each do |e|
  kh_key  = xml.xpath("//Category[@categoryId='#{e.text}']/KnowhowRefKey").text
  next if kh_key.empty?

  xml.xpath("//KnowhowInfomation[@knowhowId='#{kh_key}']/CheckItem").each do |check_item|
    s_key = check_item.attr('searchRefKey')
    next if s_key.nil? || s_key.empty?

    xml.xpath("//SearchInfomation[@searchInfoId='#{s_key}']").each do |s_info|
      args = %w(FileType SearchKey1 SearchKey2).map{|e| s_info.xpath(e)[0].text}

      (s_info.xpath('PythonModule')[0].text.empty? ? search_regex(*args) : search_xpath(*args)).each_with_index do |l, i|
        csv << (i == 0 ? [e.previous_element.text, check_item.xpath('SearchProcess').text, s_key] : [""]*3) + l
      end
    end
  end
end

csv.close
