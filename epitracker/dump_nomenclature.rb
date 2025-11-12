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
opts.on("-s","--schema", "=SCHEMA","The reference schema") {|argument| options.schema = argument }
opts.on("-d","--db", "=DB","Path to db file") {|argument| options.db = argument }
opts.on("-o","--outfile", "=OUTFILE","Output file") {|argument| options.outfile = argument }
opts.on("-h","--help","Display the usage information") {
    puts opts
    exit
}

opts.parse! 

options.db ? db_file = options.db : db_file = "/home/mhoeppner/git/epitracker/storage/development.sqlite3"

Epitracker::DBConnection.connect({database: db_file})

schema = Epitracker::CgmlstSchema.find_by_name(options.schema)

if !schema
    warn "Not a valid schema, exiting..."
    exit
end

analysis = schema.cluster_analyses.last
if !analysis
    warn "No analysis linked to this schema, exiting..."
    exit
end
partition = schema.cgmlst_partitions.find {|cp| cp.is_default }
if !partition
    warn "No partitions configured for this schema, exiting..."
    exit
end

xref = Epitracker::XrefAnalysisPartition.where(cluster_analysis_id: analysis.id, cgmlst_partition_id: partition.id).first
clusters = xref.clusters

puts "sequence\tgroup"
clusters.uniq.each do |cluster|
    cluster.cgmlst_profiles.each do |profile|
        puts "#{profile.assembly.sample.name}\t#{cluster.name}"
    end
end