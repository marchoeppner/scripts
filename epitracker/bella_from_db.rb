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

settings = {
    "escherichia" => "--efsa",
    "salmonella" => "--efsa", 
    "listeria" => "",
    "campylobacter" => ""
}

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

# Dumping nomenclature of last analysis
nomenclature = "nomenclature_#{xref.cluster_analysis.created_at.strftime("%F")}.tsv" 
f = File.new(nomenclature, "w+")
f.puts "sequence\tgroup"
clusters.uniq.each do |cluster|
    cluster.cgmlst_profiles.each do |profile|
        f.puts "#{profile.assembly.sample.name}\t#{cluster.name}"
    end
end
f.close

# Dumping assemblies

organism = schema.organism
species = organism.genus.downcase
samples = organism.samples
assemblies = samples.collect {|s| s.assemblies.first }

abort "No assemblies found for this organism #{schema.organism.name}" if assemblies.empty?

command = "mkdir -p assemblies"
system(command)

files = []
Dir.chdir("assemblies") do |dir|

    assemblies.each do |assembly|
        next if assembly.assembly_info.qc == "fail"
        fasta = assembly.fasta_unzip.split("\n").select {|l| l.length > 0 }.join("\n")
        afile = "#{assembly.sample.name}.fasta"
        f = File.new(afile, "w+")
        f.puts fasta
        f.close
        files << [ assembly.sample.name, File.expand_path(afile)]
    end
end

f = File.new("samples.tsv", "w+")
f.puts "sample\tassembly"
files.each do |s,fpath|
    f.puts "#{s}\t#{fpath}"
end
f.close

f = File.new("run.sh", "w+")
s = settings[species]
command = "nextflow run $HOME/git/bella/main.nf -profile lsh --input samples.tsv --nomenclature #{nomenclature} --species #{species} #{s} --run_name #{organism.name}"
f.puts command
f.close