#!/usr/bin/env ruby
# == NAME
# script.rb
#
# == AUTHOR
#  Marc Hoeppner, mphoeppner@gmail.com

require 'optparse'
require 'ostruct'
require 'epitracker'

### Get the script arguments and open relevant files
options = OpenStruct.new()
opts = OptionParser.new()
opts.on("-i","--infile", "=SETID","Get info for this set") {|argument| options.set_id = argument }
opts.on("-d","--db", "=DB","Path to db file") {|argument| options.db = argument }
opts.on("-o","--outfile", "=OUTFILE","Output file") {|argument| options.outfile = argument }
opts.on("-h","--help","Display the usage information") {
    puts opts
    exit
}

opts.parse! 

options.db ? db_file = options.db : db_file = "/home/mhoeppner/git/epitracker/storage/development.sqlite3"

Epitracker::DBConnection.connect({database: db_file})

analyses = Epitracker::ClusterAnalysis.all
analyses.each do |a|
	a.destroy
end

samples = Epitracker::Sample.all

samples.each do |sample|
    sample.destroy
end

