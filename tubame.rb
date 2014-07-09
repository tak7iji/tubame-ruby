# encoding: utf-8

require 'nokogiri'
require 'csv'
require 'stringio'

$base_name = File.split(Dir.getwd)[1]

def search_regex type, key1, key2
  key2 = key1 if key2.empty?
  key1 = "[.]*" if key1 == key2

  r1 = Regexp.new(key1)
  r2 = Regexp.new(key2)

  match_lines = []
  Dir.glob("**/#{type}").each do |file|
    lines = File.readlines(file)
    count=0
    skip = false
    last = file
    lines.each_with_index do |line, idx|
      skip = true if line.strip.start_with?("/*") && !line.strip.end_with?("*/")
      skip = false if skip == true && lines[idx].strip.end_with?("*/")
      next if skip == true
      data = line.strip if line.match(r2) && !line.strip.start_with?("//")
      line_no = idx + 1
      match_lines.push([last.empty? ? "" : File.join($base_name, last), line_no, data.gsub("\"", "\"\"")]) if !data.nil?
      last = "" if last == file && !data.nil?
    end if lines.select{|e| e.chomp.match(r1)}.size > 0
  end
  match_lines
end

def search_xpath type, key1, key2
  Dir.glob("**/#{type}").map do |file|
    body = open(file, "rt") {|io| io.read}
    Nokogiri.XML(body).xpath(key1).map.with_index do |node, idx|
      line_no = node.line
      line = StringIO.new(body).readlines[line_no - 1].strip
      [idx == 0 ? File.join($base_name, last) : ""] + [line_no, line]
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
        csv << (idx ==0 ? [chap_no, process, s_key] : [""]*3)+ line
      end
    end
  end
end

csv.close
