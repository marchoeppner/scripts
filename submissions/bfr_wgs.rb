#!/usr/bin/env ruby
# == NAME
# bfr_wgs.rb
#
# == AUTHOR
#  Marc Hoeppner, mphoeppner@gmail.com

require 'optparse'
require 'ostruct'
require 'json'
require 'logger'

def make_folder(species)
    if !Dir.exist?(species)
        command = "mkdir -p #{species}"
        system(command)
    end
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

pretend = true

# ------------
# Logging
# ------------

this_date = DateTime.now.strftime("%d_%m_%Y_%H-%M")

logfile = Logger.new("#{this_date}.log", "w+")
logfile.level = Logger::INFO

# Customize the log message format for file_logger (optional)
logfile.formatter = proc do |severity, datetime, progname, msg|
  "#{datetime.strftime('%Y-%m-%d %H:%M:%S')} [#{severity}] #{msg}\n"
end

console_logger = Logger.neW(STDERR
console_logger.level = Logger::DEBUG)

# ------------
# Important variables
# ------------
data = {}
genera = [ "escherichia_coli", "salmonella_enterica", "campylobacter_jejuni", "campylobacter_coli", "campylobacter_larii", "listeria_monocytogenes" ]

# ------------
# Staging data 
# ------------

logfile.info "Started processing..."

# Check if folder exists
unless Dir.exist?(options.input)
    msg = "Input folder does not exist" 
    console_logger.warn msg
    abort
end

console_logger.info "Folder found, starting pre-flight check..."
gabi_folder = Dir["#{options.input}/gabi_*"].first

unless gabi_folder
    msg "No GABI analysis found under given path! Exiting..."
    console_logger.warn msg
    logfile.warn msg
    abort
end

console_logger.info "GABI analysis present"

# Guess MiSeq run name from analysis folder name
run_name = File.basename(options.input)

raw_data_folder = "/work_syn/ngs/runs/miseq/#{run_name}".gsub(/_[0-9]*$/, "")
unless Dir.exist?(raw_data_folder)
    msg = "Raw data folder not found! Exiting..." 
    console_logger.warn msg
    logfile.warn msg
    abort

end
console_logger.info "Raw data folder present"

fastqs = Dir["#{raw_data_folder}/Alignment_1/*/Fastq/*.fastq.gz"]
if fastqs.empty?
    msg = "No FastQ files found!"
    console_logger.warn msg
    logfile.warn msg
    abort
end 

console_logger.info "Read data present - looking for species information"

jsons = Dir["#{gabi_folder}/*/results/samples/*/*.json"]
if jsons.empty?
    msg = "No JSON reports in GABI folder found" 
    console_logger.warn msg
    logfile.warn msg
    abort
end

console_logger.info "QC reports found, parsing now"

species_seen = []
jsons.each do |json|
    j = JSON.parse(IO.readlines(json).join)

    sample = j["sample"]
    species = j["taxon"]
    qc = j["qc"]["call"]

    if qc == "fail"
        msg = "#{sample} failed QC, skipping..."
        console_logger.warn msg
        logfile.warn msg
        next
    end
    species_folder = species.downcase.gsub(" ", "_")
    if genera.include?(species_folder)
        species_seen << species_folder
        data[sample] = species_folder
        console_logger.info "Adding #{sample} (#{species_folder})"
    else
        msg = "#{sample} belongs to an unsupported species (#{species_folder}), skipping..."
        console_logger.warn msg
        logfile.warn msg
    end

end

species_seen.uniq!

console_logger.info "Creating folders and staging reads"

species_seen.each do |s|
    make_folder(s)
end

data.each do |sample,species|

    # Check that this sample belongs to a species of interest
    next unless genera.include?(species)

    reads = fastqs.select {|f| f.include?(sample)}.map {|f| File.expand_path(f) }
    next if reads.empty?

    console_logger.info "Sym-linking reads"

    Dir.chdir(species) {
        reads.each do |r|
            command = "ln -s #{r}"
            console_logger.info "Linking #{r}"
            if !pretend
                system(command)
            end
        end
    }

end

species_seen.each do |species|

    Dir.chdir(species) do |dir|
        command = "md5sum *.fastq.gz > md5sums"
        console_logger.info "Creating md5sums in #{species}"
        if !pretend
            system(command)
        end
    end

end






