#!/usr/bin/env ruby
# == NAME
# bfr_wgs.rb
#
# == AUTHOR
#  Marc Hoeppner, mphoeppner@gmail.com

require 'optparse'
require 'ostruct'
require 'json'

def make_folder(species)

    if !Dir.exist?(species)
        command = "mkdir -p #{species}"
        system(command)
    end

end

def msg(text)

    warn text

end

### Get the script arguments and open relevant files
options = OpenStruct.new()
opts = OptionParser.new()
opts.on("-i","--input", "=INPUT","INPUT folder") {|argument| options.input = argument }
opts.on("-o","--outfile", "=OUTFILE","Output file") {|argument| options.outfile = argument }
opts.on("-h","--help","Display the usage information") {
    puts opts
    exit
}

opts.parse! 

data = {}
genera = [ "escherichia_coli", "salmonella_enterica", "campylobacter_jejuni", "campylobacter_coli", "campylobacter_larii", "listeria_monocytogenes" ]

# Check if folder exists
abort "Folder does not exist" unless Dir.exist?(options.input)

msg("Folder found, starting pre-flight check...")
gabi_folder = Dir["#{options.input}/gabi_*"].first

abort "No GABI analysis found under given path! Exiting..." unless gabi_folder
msg("GABI analysis present")

run_name = File.basename(options.input)

raw_data_folder = "/work_syn/ngs/runs/miseq/#{run_name}".gsub(/_[0-9]*$/, "")

abort "Raw data folder not found! Exiting..." unless Dir.exist?(raw_data_folder)
msg("Raw data folde present")

fastqs = Dir["#{raw_data_folder}/Alignment_1/*/Fastq/*.fastq.gz"]
abort "No FastQ files found" if fastqs.empty?

msg("Read data present - looking for species information")

jsons = Dir["#{gabi_folder}/*/results/samples/*/*.json"]
abort "No JSON reports in GABI folder found" unless !jsons.empty?

msg("QC reports found, parsing now")

species_seen = []
jsons.each do |json|
    j = JSON.parse(IO.readlines(json).join)

    sample = j["sample"]
    species = j["taxon"]
    qc = j["qc"]["call"]

    if qc == "fail"
        msg("#{sample} failed QC, skipping")
        next
    end
    msg("\tAdding #{sample}")
    species_folder = species.downcase.gsub(" ", "_")
    next unless genera.include?(species_folder)
    species_seen << species_folder
    data[sample] = species_folder

end

species_seen.uniq!

msg("Creating folders and staging reads")

species_seen.each do |s|
    make_folder(s)
end

data.each do |sample,species|

    # Check that this sample belongs to a species of interest
    next unless genera.include?(species)

    reads = fastqs.select {|f| f.include?(sample)}.map {|f| File.expand_path(f) }

    msg("Sym-linking reads")

    Dir.chdir(species) {
        reads.each do |r|
            command = "ln -s #{r}"
            system(command)
        end
    }

end






