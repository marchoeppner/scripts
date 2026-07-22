#!/usr/bin/env ruby
# == NAME
# script.rb
#
# == AUTHOR
#  Marc Hoeppner, mphoeppner@gmail.com

require 'optparse'
require 'ostruct'
require 'json'

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

data = JSON.parse(IO.readlines(options.infile).join)

# Remove keys that are always unique across files
data["analysis_info"].delete("finished_script_at")
data["analysis_info"].delete("started_script_at")

f = File.new(options.outfile, "w+")
f.puts JSON.pretty_generate(data)
f.close