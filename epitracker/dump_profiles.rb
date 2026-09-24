#!/usr/bin/env ruby
# == NAME
# script.rb
#
# == AUTHOR
#  Marc Hoeppner, mphoeppner@gmail.com

require 'optparse'
require 'ostruct'
require 'epitracker'
require 'bio'
require 'progressbar'

### Get the script arguments and open relevant files
options = OpenStruct.new()
opts = OptionParser.new()
opts.on("-s","--schema", "=SCHEMA","The schema to use") {|argument| options.schema = argument }
opts.on("-d","--db", "=DB","Path to db file") {|argument| options.db = argument }
opts.on("-o","--outfile", "=OUTFILE","Output file") {|argument| options.outfile = argument }
opts.on("-h","--help","Display the usage information") {
    puts opts
    exit
}

opts.parse! 

options.db ? db_file = options.db : db_file = "/work_syn/ngs/projects/epitracker/db/development.sqlite3"

Epitracker::DBConnection.connect({database: db_file})

schema = Epitracker::CgmlstSchema.find_by_name(options.schema)

wd = Dir.getwd

if !schema
    warn "Not a valid schema, exiting..."
    exit
end

s = File.new("profiles.tsv", "w+")
s.puts "sample\tprofile"

profiles = schema.cgmlst_profiles

pg = ProgressBar.create(:title => "Profiles", :total => profiles.length)

profiles.each do |profile|

    pg.increment
    
    sample = profile.assembly.sample

    text =  Zlib.inflate(Base64.decode64(profile.profile))
    
    f = File.new("#{sample.name}.tsv", "w+")
    f.puts text
    f.close

    s.puts "#{sample.name}\t#{wd}/#{sample.name}.tsv"

end

s.close

pg.finish
