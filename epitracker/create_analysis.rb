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

BELLA_VERSION="1.0.1"
WD = Dir.getwd

opts.parse! 

options.db ? db_file = options.db : db_file = "/work_syn/ngs/projects/epitracker/db/development.sqlite3"

Epitracker::DBConnection.connect({database: db_file})

schema = Epitracker::CgmlstSchema.find_by_name(options.schema)
organism = schema.organism
samples = organism.samples

assemblies_only = []
   
wd = Dir.getwd

if !schema
    warn "Not a valid schema, exiting..."
    exit
end

command = [
    "nextflow run marchoeppner/bella -profile lsh -r #{BELLA_VERSION}"
]

####################################
# Dump FASTA file for samples without
# cgMLST profile for this schema
####################################

samples.each do |sample|
    assembly = sample.assemblies.first

    valid_profiles = assembly.cgmlst_profiles.select {|c| c.cgmlst_schema_id == schema.id }

    if valid_profiles.empty?
        assemblies_only << sample
    end

end

if !assemblies_only.empty?

    pg = ProgressBar.create(:title => "Assemblies", :total => assemblies_only.length)

    s = File.new("assemblies.tsv", "w+")
    s.puts "sample\tassembly"

    assemblies_only.each do |sample|

        pg.increment

        assembly = sample.assemblies.first

        if assembly.assembly_info.qc == "fail"
            warn "Skipping #{sample.name} due to QC failure"
            next
        end

        text = assembly.fasta_unzip
    
        f = File.new("#{sample.name}.fasta", "w+")
        f.puts text
        f.close

        s.puts "#{sample.name}\t#{wd}/#{sample.name}.fasta"
    end

    s.close

    pg.finish

    command.append("--input #{WD}/assemblies.tsv")
end


#################################
# Dump pre-computed allele profiles
#################################

profiles = schema.cgmlst_profiles

if !profiles.empty?

    s = File.new("profiles.tsv", "w+")
    s.puts "sample\tprofile"

    pg = ProgressBar.create(:title => "Profiles", :total => profiles.length)

    profiles.each do |profile|

        pg.increment

        sample = profile.assembly.sample

        if profile.assemby.assembly_info.qc == "fail"
            warn "Skipping sample #{sample.name} due to QC failure"
            next
        end

        text =  Zlib.inflate(Base64.decode64(profile.profile))
    
        f = File.new("#{sample.name}.tsv", "w+")
        f.puts text
        f.close

        s.puts "#{sample.name}\t#{wd}/#{sample.name}.tsv"

    end

    s.close

    pg.finish

    command.append("--alleles #{WD}/profiles.tsv")

end

###############################
# Dump existing nomenclature
###############################


partition = schema.cgmlst_partitions.find {|cp| cp.is_default }
if !partition
    warn "No partitions configured for this schema, exiting..."
    exit
end

analysis = schema.cluster_analyses.last
if !analysis
    warn "No analysis linked to this schema, not dumping nomenclature"
else 
    xref = Epitracker::XrefAnalysisPartition.where(cluster_analysis_id: analysis.id, cgmlst_partition_id: partition.id).first
    clusters = xref.clusters

    if !clusters.empty?

        s = File.new("nomenclature.tsv", "w+")
        s.puts "sequence\tgroup"
        clusters.uniq.each do |cluster|
            cluster.cgmlst_profiles.each do |profile|
                s.puts "#{profile.assembly.sample.name}\t#{cluster.name}"
            end
        end
        s.close
        command.append("--nomenclature #{WD}/nomenclature.tsv")
    end

end

command.append("--species #{organism.genus.downcase} --efsa --run_name Run")

f = File.new("run.sh", "w+")
f.puts command.join(" ")
f.close