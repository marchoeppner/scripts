#!/usr/bin/env ruby
# == NAME
# script.rb
#
# == AUTHOR
#  Marc Hoeppner, mphoeppner@gmail.com

require 'optparse'
require 'ostruct'
require 'open3'
require 'json'
require 'logger'
require 'date'


class String
	def black;          "\e[30m#{self}\e[0m" end
	def red;            "\e[31m#{self}\e[0m" end
	def green;          "\e[32m#{self}\e[0m" end
end

def check_irods
	stdout_str, stderr_str, status = Open3.capture3("ils")
	stderr_str.include?("Error") ? irods = false : irods = true
	return irods
end

def check_archive(path)
  
  stdout_str, stderr_str, status = Open3.capture3("tar -tzf #{path}")
  
  status.to_s.include?("exit 0") ? pass = true : pass = false
  
  return pass

end

def validate_gabi_folder(path)
  
    pass = true

    if !File.exist?(path)
      pass = false
      warn "Path provided does not exist (--input)!"
    end

    if !File.exist?("#{path}/pipeline_info")
      pass = false
      warn "Missing pipeline_info from Bella folder!"
    end

    if !File.exist?("#{path}/samples")
      pass = false
      warn "Missing Gabi sample directory!"
    end

    if Dir["#{path}/samples/*/*.json"].empty?
      pass = false
      warn "No GABI JSON files found under #{path}!"
    end

    return pass

end

def run(command)
  
  warn("Running: #{command}")
  system(command)

end

def json_to_metadata(json)
  
  data = {}

  data["sample"] = json["sample"]
  data["pipeline_version"] = json["software"]["Workflow"]["bio-raum/gabi"]
  data["pipeline"] = "bio-raum/gabi"
  data["species"] = json["taxon"]
  data["qc_call"] = json["qc"]["call"]
  data["qc_fail"] = json["qc"]["fail"].join(",")
  data["qc_warn"] = json["qc"]["warn"].join(",")
  data["qc_pass"] = json["qc"]["pass"].join(",")
  data["n50"] = json["quast"]["N50"]
  data["assembly_size"] = json["quast"]["Total length"]
  data["assembly_qc"] = json["quast"]["GC (%)"]
  data["assembly_contigs"] = json["quast"]["# contigs"]
  data["date"] = json["date"]

  fastp_command = json["fastp"]["command"].split(" ")
  fwd_read = fastp_command[2]
  rev_read = fastp_command[4]

  data["reads"] = "#{fwd_read},#{rev_read}"

  return data
  
end

### Get the script arguments and open relevant files
options = OpenStruct.new()
opts = OptionParser.new()
opts.on("-i","--input", "=INPUT","Input file") {|argument| options.input = argument }
opts.on("-p","--pretend","Simulate only") {|argument| options.pretend = true }
opts.on("-f","--folder", "=FOLDER","iRODS folder") {|argument| options.folder = argument }
opts.on("-o","--outfile", "=OUTFILE","Output file") {|argument| options.outfile = argument }
opts.on("-h","--help","Display the usage information") {
    puts opts
    exit
}

opts.parse! 

date = Date.today.strftime("%F")
logfile = "gabi2irods_#{date}.log"
user = `whoami`

log = Logger.new File.open(logfile, 'w+')
log.level = Logger::INFO

log.info "#################################"
log.info "Transferring assemblies to iRODS"
log.info "#################################"
log.info "Date: #{date}"
log.info "Log: #{logfile}"
log.info "User: #{user}"

if !options.pretend && !check_irods
	abort "You are not authenticated with the iRODS service - please run `iinit`!".red
end

BASE_URL = "/lsh/ngs/assemblies"

gabi_status = validate_gabi_folder(options.input)

if !gabi_status
  abort "This does not look like a valid Gabi folder!"
end

samples = Dir["#{options.input}/samples/*"].map {|f| File.expand_path(f)}

samples.each do |sample_path|
  
  json_file =  Dir["#{sample_path}/*.json"].first
  next unless json_file

  json = JSON.parse(IO.readlines(json_file).join)

  metadata = json_to_metadata(json)

  assembly = "#{sample_path}/assembly/#{json['sample']}.fasta"

  next unless File.exist?(assembly)

  warn assembly

  sample = json["sample"]

  metadata_file = "#{sample}.metadata"
  f = File.new("#{metadata_file}", "w+")
  metadata.each do |key,value|
    f.puts "#{key}\t#{value}"
  end
  f.close

  manifest = [ json_file, assembly, metadata_file ]

  archive = "#{sample}.tar.gz"
  command = "tar -czvf #{archive} #{manifest.join(' ')}"
  run(command)

  status = check_archive(archive)

  abort "Failed to create valid tar archive for #{sample}" unless status

  md5sum = "#{archive}.md5"
  command = "md5sum #{archive} > #{md5sum}"
  run(command)

  # Transfer to irods
  commands = [
    "iput #{archive} #{BASE_URL}/#{archive}",
    "iput #{md5sum} #{BASE_URL}/#{md5sum}",
    "iput #{metadata_file} #{BASE_URL}/#{metadata_file}"
  ]

  commands.each do |command|
    if options.pretend
      warn(command)
    else
      run(command)
    end
  end
  
  metadata.each do |key,value|
    payload = "\"#{key}\"\t\"#{value}\"\t\"string\""
    command = "imeta add -d #{BASE_URL}/archive #{payload}"
    if options.pretend
      warn(command)
    else
      run(command)
    end
  end

end