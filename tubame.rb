# encoding: utf-8

require 'nokogiri'
require 'csv'

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
    lines.each_index do |idx|
      skip = true if lines[idx].strip.start_with?("/*") && !lines[idx].strip.end_with?("*/")
      skip = false if skip == true && lines[idx].strip.end_with?("*/")
      next if skip == true
      data = lines[idx].strip if lines[idx].match(r2) && !lines[idx].strip.start_with?("//")
      line_no = idx + 1
      match_lines.push([last.empty? ? "" : File.join($base_name, last), line_no, data.gsub("\"", "\"\"")]) if !data.nil?
      last = "" if last == file && !data.nil?
    end if lines.select{|e| e.chomp.match(r1)}.size > 0
  end
  match_lines
end

def search_xpath type, key1, key2
  match_lines = []
  Dir.glob("**/#{type}").each do |file|
    last = file
    open(file, "rt") do |io|
      doc = Nokogiri.XML(io.read)
      doc.xpath(key1).each do |node|
        io.rewind
        line_no = node.line
        line = io.readlines[line_no - 1].strip
        match_lines << [last.empty? ? "" : File.join($base_name, last), line_no, line]
        last = "" if last == file
      end
    end
  end
  match_lines
end

xml = Nokogiri.XML(open(ARGV[0]))
csv = CSV.open('result.csv', "wb", :encoding => 'Shift_JIS')
csv << ['ガイド章','検索手順','検索情報ID','ファイル名','行番号','コード内容']

xml.remove_namespaces!
xml.xpath('//ChapterCategoryRefKey').each do |e|
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
      type = search_info.xpath('FileType')[0].text
      key1 = search_info.xpath('SearchKey1')[0].text
      key2 = search_info.xpath('SearchKey2')[0].text
      mod  = search_info.xpath('PythonModule')[0].text

      match_lines = search_regex(type, key1, key2) if mod.empty?
      match_lines = search_xpath(type, key1, key2) if !mod.empty?
      match_lines.each do |line|
        line.unshift(chap_no, process, s_key)
        csv << line
        chap_no = ""
        process = ""
        s_key = ""
      end if !match_lines.nil?
    end
  end
end

csv.close
