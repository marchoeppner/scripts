#!/usr/bin/env ruby
# == NAME
# script.rb
#
# == AUTHOR
#  Marc Hoeppner, mphoeppner@gmail.com

require 'optparse'
require 'ostruct'
require 'progressbar'

### Get the script arguments and open relevant files
options = OpenStruct.new()
opts = OptionParser.new()
opts.on("-i","--input", "=INPUT","Bella folder") {|argument| options.input = argument }
opts.on("-o","--outfile", "=OUTFILE","Output file") {|argument| options.outfile = argument }
opts.on("-h","--help","Display the usage information") {
    puts opts
    exit
}

opts.parse! 

abort "Must specify output file name (-o)" unless options.outfile
    
profiles = Dir["#{options.input}/samples/*/chewbbaca/*_results_alleles.tsv"].map {|e| File.expand_path(e)}

if profiles.empty?
    abort "No cgMLST profiles found in #{options.input}"
end

s = File.new(options.outfile, "w+")
s.puts "sample\tprofile"

profiles.each do |profile|
    sample = File.basename(profile).split("_results_alleles.tsv")[0]
    s.puts "#{sample}\t#{profile}"
end
s.close

puts "Found #{profiles.length} cgMLST profiles - samplesheet written to #{options.outfile}"