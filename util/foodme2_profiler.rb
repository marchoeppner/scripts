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

json = JSON.parse(IO.readlines(options.infile).join)

command = json["command"]
clustering = json["clustering"]
composition = json["composition"]
cutadapt = json["cutadapt"]
fastp = json["fastp"]

# Get basic run information


# Get read cleaning info

# Get read trimming info



