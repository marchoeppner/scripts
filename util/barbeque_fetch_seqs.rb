#!/usr/bin/env ruby
# == NAME
# script.rb
#
# == AUTHOR
#  Marc Hoeppner, mphoeppner@gmail.com

require 'optparse'
require 'ostruct'
require 'csv'

### Get the script arguments and open relevant files
options = OpenStruct.new()
opts = OptionParser.new()
opts.on("-i","--infile", "=INFILE","Barbeque consensus") {|argument| options.infile = argument }
opts.on("-l","--list", "=LIST","List of taxa") {|argument| options.list = argument }
opts.on("-o","--outfile", "=OUTFILE","Output file") {|argument| options.outfile = argument }
opts.on("-h","--help","Display the usage information") {
    puts opts
    exit
}

opts.parse! 

taxa = IO.readlines(options.list).map {|l| l.strip }

output = File.new(options.outfile,"w+")

refs = CSV.read(options.infile, col_sep: "\t", headers: true)

refs.each do |row|
    species = row["species"]
    if taxa.include?(species)
        output.puts ">#{species}"
        output.puts row["amplicon"].strip
        taxa.delete(species)
    end
end

output.close