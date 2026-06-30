#!/usr/bin/env ruby
# == NAME
# script.rb
#
# == AUTHOR
#  Marc Hoeppner, mphoeppner@gmail.com

require 'optparse'
require 'ostruct'

### Get the script arguments and open relevant files
options = OpenStruct.new()
opts = OptionParser.new()
opts.on("-i","--infile", "=INFILE","Input file") {|argument| options.infile = argument }
opts.on("-o","--outfile", "=OUTFILE","Output file") {|argument| options.outfile = argument }
opts.on("-h","--help","Display the usage information") {
    puts opts
    exit
}

opts.parse! 

rows = {}
columns = {}

lines = IO.readlines(options.infile)

samples = []
lines.each do |line|
  
    elements = line.strip.split(" ")
    sample = elements.shift
    samples.append(sample)

    rows[sample] = elements
end

sorted_samples = rows.sort.to_h.keys

sorted_rows = {}

sorted_samples.each do |sample|
  
    old_row = rows[sample]

    sorted_row = []

    sorted_samples.each do |s|
      
        old_index = samples.index(s)

        sorted_row.append(old_row[old_index].to_f.round(2))

    end

    sorted_rows[sample] = sorted_row
end

sorted_rows.each do |sample,values|
  puts sample + "\t" + values.join("\t")
end