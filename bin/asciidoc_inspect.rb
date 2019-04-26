#!/usr/bin/env ruby

require 'asciidoctor'

#doc = Asciidoctor.load_file ARGF.filename, safe: :safe, :attributes => 'revealjs_slideshow'
doc = Asciidoctor.load_file ARGF.filename, safe: :safe, :attributes => 'revealjs_slideshow'

#doc.find_by(context: :block) {|candidate| candidate.title.include? 'grade' }.each do |gblock|
#doc.find_by(context: :grade) {|candidate|}.each do |gblock|
  #puts gblock
#end
puts "by section"
puts doc.find_by( context: :section ) 

puts "by grade"
puts doc.find_by( id: :grade ) 

puts "by block"
puts doc.find_by

puts "by role"
puts doc.find_by( role: 'grade' ) 
puts doc.find_by

puts "by doc"

#puts doc.content

puts "nbsp"
doc.find_by(context: :section, id: 'cover') do |c|
  puts c.blocks[0].content
end
puts "VICTORY"
puts doc.find_by(context: :section, id: 'cover')[0].blocks[0].content
