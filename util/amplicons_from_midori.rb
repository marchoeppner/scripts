#!/usr/bin/env ruby
# == NAME
# script.rb
#
# == AUTHOR
#  Marc Hoeppner, mphoeppner@gmail.com

require 'optparse'
require 'ostruct'

def run(command)
    warn "Running #{command}"
    system(command)
end

### Get the script arguments and open relevant files
options = OpenStruct.new()
opts = OptionParser.new()
opts.on("-i","--infile", "=INFILE","Input file") {|argument| options.infile = argument }
opts.on("-l","--list", "=LIST","list of taxa") {|argument| options.list = argument }
opts.on("-o","--outfile", "=OUTFILE","Output file") {|argument| options.outfile = argument }
opts.on("-h","--help","Display the usage information") {
    puts opts
    exit
}

opts.parse! 

taxa = IO.readlines(options.list).collect {|l| l.strip}
min_len = 60
db = options.infile
fwd = "GACGAGAAGACCCTATGGAGC"
rev = "TCCGAGGTCACCCCAACC"
crabs = "singularity exec -B /work_syn /work_syn/shared/singularity_cache/depot.galaxyproject.org-singularity-crabs-1.14.0--pyhdfd78af_0.img crabs"

# Run crabs on the database
command = "#{crabs} --in-silico-pcr --input #{db} --output crabs_insilico.txt --forward #{fwd} --reverse #{rev} --threads 4"
run(command)

data = {}
# Parse data and filter out hits for desired taxa
crabs = File.open("crabs_insilico.txt", "r")
while (line = crabs.gets)
    line.strip!
    elements = line.split("\t")
    species = elements[1]
    next unless taxa.include?(species) && !data.has_key?(species)
    amplicon = elements[-1]
    next if amplicon.length < min_len
    data[species] = amplicon
end
crabs.close

abort "No sequences found" if data.keys.empty?

db = File.open(db, "r")
untrimmed = {}

while (line = db.gets)
    line.strip!
    elements = line.split("\t")
    species = elements[1]
    next unless data.has_key?(species) && !untrimmed.has_key?(species)
    seq = elements[-1]
    amplicon = data[species]
    start_pos = seq.index(amplicon)
    if start_pos
        up = start_pos-fwd.length
        down = start_pos+amplicon.length+rev.length
        full_amplicon = seq[up..down]
        untrimmed[species] = full_amplicon
    end
end

fasta = File.new("amplicons.fasta", "w+")

untrimmed.each do |key,value|
    seq_name = key.gsub(" ", "_")
    coverage = rand(10000)
    fasta.puts ">#{seq_name} depth=#{coverage}"
    fasta.puts value.upcase
end
fasta.close

