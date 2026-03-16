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
opts.on("-f","--folder", "=FOLDER","Folder with all BfR runs") {|argument| options.folder = argument }
opts.on("-o","--outfile", "=OUTFILE","Output file") {|argument| options.outfile = argument }
opts.on("-h","--help","Display the usage information") {
    puts opts
    exit
}

opts.parse! 

abort "Input folder does not exist" unless Dir.exist?(options.folder)

jsons = Dir["#{options.folder}/*/aquamis/results/json/post_qc/*.json"]

jsons.each do |json|

    j = JSON.parse(IO.readlines(json).join)

    sample = j["sample"]["summary"]["sample"]
    status = j["sample"]["qc_assessment"]["qc_VOTE"]
    mlst = j["sample"]["summary"]["sequence_type"]

    puts "#{sample}\t#{status}\t#{mlst}"
    
end