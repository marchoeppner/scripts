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
opts.on("-o","--outfile", "=OUTFILE","Output file") {|argument| options.outfile = argument }
opts.on("-h","--help","Display the usage information") {
    puts opts
    exit
}

opts.parse! 

db_file = "/work_syn/ngs/projects/epitracker/db/development.sqlite3"

Epitracker::DBConnection.connect({database: db_file})

sample = Epitracker::Sample.find_by_name("LC10-22-RV4-P64-E04")

assembly = sample.assemblies.first

profile = assembly.cgmlst_profiles.first

profile_unzip = Zlib.inflate(Base64.decode64(profile.profile))

puts profile_unzip