# encoding: utf-8

require 'nokogiri'
require 'csv'

$base_name = File.split(Dir.getwd)[1]
C=:c
N=:n

def search_regex type, key1, key2
  r1 = Regexp.new(key2.empty? ? "[.]*" : key1)
  r2 = Regexp.new(key2.empty? ? key1 : key2)

  h = lambda {|s| s.is_a?(Array)}
  f = lambda do |file, r, e|
    (N if (e[0].start_with?("//")) || (r.any? && r.last == C && e[0].end_with?("*/")))||
    (C if (e[0].start_with?("/*") && !e[0].end_with?("*/")) || (r.any? && r.last == C))||
    ([r.any?(&h) ? "" : File.join($base_name, file), e[1] + 1, e[0].gsub("\"", "\"\"")] if e[0].match(r2))
  end.curry

  Dir.glob("**/#{type}").lazy.map do |file|
    g = f[file]
    lines = File.readlines(file).map(&:strip)
    next if lines.none? {|e| e.match(r1)}

    lines.each_with_index.inject([]) do |r, e|
      r + [g[r, e]]
    end.compact.select(&h)
  end.to_a.compact.flatten 1
end

def search_xpath type, key1, key2
  Dir.glob("**/#{type}").lazy.map do |file|
    body = open(file, "rt", &:read)
    Nokogiri.XML(body).xpath(key1).map.with_index do |node, idx|
      line = body.split("\n")[node.line - 1].strip
      [idx == 0 ? File.join($base_name, file) : "", node.line, line]
    end
  end.to_a.flatten 1
end

csv = CSV.open('result.csv', "wb", :encoding => 'Shift_JIS')
csv << ['ガイド章','検索手順','検索情報ID','ファイル名','行番号','コード内容']

xml = Nokogiri.XML(open(ARGV[0]))
xml.remove_namespaces!.xpath('//ChapterCategoryRefKey').each do |e|
  chap_no = e.previous_element.text
  cat_key = e.text
  kh_key  = xml.xpath("//Category[@categoryId='#{cat_key}']/KnowhowRefKey").text
  next if kh_key.empty?

  xml.xpath("//KnowhowInfomation[@knowhowId='#{kh_key}']/CheckItem").each do |check_item|
    search_key = check_item.attr('searchRefKey')
    next if search_key.nil? || search_key.empty?

    process = check_item.xpath('SearchProcess').text
    s_key = search_key
    xml.xpath("//SearchInfomation[@searchInfoId='#{search_key}']").each do |search_info|
      args = %w(FileType SearchKey1 SearchKey2).map{|e| search_info.xpath(e)[0].text}

      (search_info.xpath('PythonModule')[0].text.empty? ? search_regex(*args) : search_xpath(*args)).each_with_index do |line, idx|
        csv << (idx == 0 ? [chap_no, process, s_key] : [""]*3)+line
      end
    end
  end
end

csv.close
