#!/usr/bin/env ruby
# == NAME
# script.rb
# == DESCRIPTION
# Takes a GABI JSON file and removes metadata that is specific to the executing system
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

json = JSON.parse(IO.readlines(options.infile).join)

json["pipeline_settings"].delete("max_cpus")
json["pipeline_settings"].delete("max_memory")

puts JSON.pretty_generate(json)