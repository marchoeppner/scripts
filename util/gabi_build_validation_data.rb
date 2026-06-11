#!/usr/bin/env ruby
# == NAME
# script.rb
#
# == AUTHOR
#  Marc Hoeppner, mphoeppner@gmail.com

require 'optparse'
require 'ostruct'
require 'fileutils'
require 'logger'

def build_slurm_script(header, name, version) 
  
    f = File.new("slurm.sh", "w+")

    f.puts header
    f.puts "nextflow run bio-raum/gabi -profile lsh -r #{version} --input samples.tsv --run_name #{name}"
    
    f.close

    return "slurm.sh"

end

def submit_slurm_script(script, previous_job_id)
  
    job_id = nil
    
    previous_job_id ? dependency = "--dependency=afterok:#{previous_job_id}" : dependency = ""

    job = `sbatch #{dependency} #{script}`

    job_id = job.slice(/[0-9]*/)

    return job_id

end

def get_job_status(job_id)
  
    response = `scontrol show job #{job_id}`

    status = response

    return status

end

### Get the script arguments and open relevant files
options = OpenStruct.new()
opts = OptionParser.new()
opts.on("-v","--version", "=VERSION","Pipeline version") {|argument| options.infile = argument }
opts.on("-o","--outfile", "=OUTFILE","Output file") {|argument| options.outfile = argument }
opts.on("-h","--help","Display the usage information") {
    puts opts
    exit
}

opts.parse! 

BASE = "/work_syn/ngs/pipelines/gabi/validation"
VERSION = options.version

log = Logger.new File.open('bella.log', 'w')
log.level = Logger::INFO

reference_sets = {
    "BfR" => {},
    "Contamination" => {
        "set1" => "/path/to/samples.tsv",
        "set2" => "/path/to/samples.tsv",
        "set3" => "/path/to/samples.tsv",
        "set4" => "/path/to/samples.tsv",
        "campylobacter" => "/path/to/samples.tsv"
    },
    "Serotyping" => {
        "ecoli" => "/path/to/samples.tsv"
    }
}

[01..14].each do |lab|
    reference_sets["BfR"]["LC#{lab}"] => "/path/to/samples.tsv"
end

# Build Nextflow template

slurm_header = """
# SBATCH -J GABI
# 
# 
"""


# Create directories
previous_job_id = nil

reference_sets.each do |set,data|

    data.each do |subset,sheet|
        this_path = "#{BASE}/#{VERSION}/#{set}/#{subset}"

        if File.exist?("#{this_path}/samples.tsv")
            FileUtils.mkdir_p(this_path)
            Dir.chdir(this_path) do |dir|
                script = build_slurm_script(slurm_header, "#{set}_#{subset}", VERSION)
                previous_job_id = submit_slurm_script(script, previous_job_id)
            end
        else
            abort "Sample sheet missing in #{this_path}"
        end
    end

end