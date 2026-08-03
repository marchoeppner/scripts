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

reports = Dir["*_report.csv"]

reports.each do |r|

    lines = IO.readlines(r).map {|l| l.strip }

    header = lines.shift.split(",")
    data = lines.shift.split(",")

    bucket = {}
    data.each_with_index do |d,i|
        bucket[header[i]] = d
    end

    puts bucket["Sample"] + "\t" + bucket["ContamStatus"].downcase
end
