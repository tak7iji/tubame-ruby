# encoding: utf-8

require 'nokogiri'
require 'csv'

$base_name = File.split(Dir.getwd)[1]
C=:c
E=:e
N=:n

def search_regex type, key1, key2
  r1 = Regexp.new(key2.empty? ? "[.]*" : key1)
  r2 = Regexp.new(key2.empty? ? key1 : key2)

  proc = lambda do |file, r, e|
    (C if e[0].start_with?("/*") && !e[0].end_with?("*/"))||
    (E if !r.empty? && r.last == C && e[0].end_with?("*/"))||
    (C if !r.empty? && r.last == C)||
    (N if e[0].start_with?("//"))||
    ([r.find{|s| s != C && s != E && s != N}.nil? ? File.join($base_name, file) : "", e[1] + 1, e[0].gsub("\"", "\"\"")] if e[0].match(r2))||
    N
  end

  Dir.glob("**/#{type}").map do |file|
    lines = File.readlines(file).map{|e| e.strip}
    next if lines.none? {|e| e.chomp.match(r1)}

    lines.each_with_index.inject([]) do |r, e|
      r + [proc.call(file, r, e)]
    end.compact.select{|s| s != C && s != E && s != N}
  end.compact.flatten 1
end

def search_xpath type, key1, key2
  Dir.glob("**/#{type}").map do |file|
    body = open(file, "rt") {|io| io.read}
    Nokogiri.XML(body).xpath(key1).map.with_index do |node, idx|
      line = body.split("\n")[node.line - 1].strip
      [idx == 0 ? File.join($base_name, file) : "", node.line, line]
    end
  end.flatten 1
end

csv = CSV.open('result.csv', "wb", :encoding => 'Shift_JIS')
csv << ['ガイド章','検索手順','検索情報ID','ファイル名','行番号','コード内容']

xml = Nokogiri.XML(open(ARGV[0]))
xml.remove_namespaces!.xpath('//ChapterCategoryRefKey').each do |e|
  chap_no = e.previous_element.text
  cat_key = e.text
  kh_key  = xml.xpath("//Category[@categoryId='#{cat_key}']/KnowhowRefKey").text
  # KnowhowRefKeyが無ければスキップ
  next if kh_key.empty?

  xml.xpath("//KnowhowInfomation[@knowhowId='#{kh_key}']/CheckItem").each do |check_item|
    search_key = check_item.attr('searchRefKey')
    next if search_key.nil? || search_key.empty?

    process = check_item.xpath('SearchProcess').text
    s_key = search_key
    xml.xpath("//SearchInfomation[@searchInfoId='#{search_key}']").each do |search_info|
      proc = lambda do |f|
        send f, search_info.xpath('FileType')[0].text,
                search_info.xpath('SearchKey1')[0].text,
                search_info.xpath('SearchKey2')[0].text
      end

      proc.call(search_info.xpath('PythonModule')[0].text.empty? ?  :search_regex : :search_xpath).each_with_index do |line, idx|
        csv << (idx ==0 ? [chap_no, process, s_key] : [""]*3)+line
      end
    end
  end
end

csv.close
