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
opts.on("-s","--species", "=SPECIES","The species to use") {|argument| options.species = argument }
opts.on("-d","--db", "=DB","Path to db file") {|argument| options.db = argument }
opts.on("-o","--outfile", "=OUTFILE","Output file") {|argument| options.outfile = argument }
opts.on("-h","--help","Display the usage information") {
    puts opts
    exit
}

opts.parse! 

options.db ? db_file = options.db : db_file = "/work_syn/ngs/projects/epitracker/db/development.sqlite3"

Epitracker::DBConnection.connect({database: db_file})

species = Epitracker::Organism.find_by_name(options.species)

wd = Dir.getwd

if !species
    warn "Not a valid species, exiting..."
    exit
end

s = File.new("samples.tsv", "w+")
s.puts "sample\tassembly"

samples = species.samples

pg = ProgressBar.create(:title => "Samples", :total => samples.length)

species.samples.each do |sample|

    pg.increment

    assembly = sample.assemblies.first

    text = assembly.fasta_unzip
    
    f = File.new("#{sample.name}.fasta", "w+")
    f.puts text
    f.close

    s.puts "#{sample.name}\t#{wd}/#{sample.name}.fasta"

end

s.close

pg.finish
