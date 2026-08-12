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

def bella_status(path)
  
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
      warn "Missing Bella sample directory!"
    end

    return pass

end

### Get the script arguments and open relevant files
options = OpenStruct.new()
opts = OptionParser.new()
opts.on("-i","--input", "=INPUT","Input file") {|argument| options.input = argument }
opts.on("-o","--outfile", "=OUTFILE","Output file") {|argument| options.outfile = argument }
opts.on("-h","--help","Display the usage information") {
    puts opts
    exit
}

opts.parse! 

abort "Must provide iRODS collection name (--folder)" unless options.folder

if !check_irods
	abort "You are not authenticated with the iRODS service - please run `iinit`!".red
end

BASE_URL = "/lsh/ngs/cgmlst"

bella_status = validate_bella_folder(options.input)

if !bella_status
  abort "This does not look like a valid Bella folder!"
end

json = Dir["#{options.input}/report/*.json"].first

if !json
  abort "Missing Json from report directory, cannot proceed!"
end

metadata = JSON.parse(IO.readlines(json).join)

command = "imkdir #{BASE_URL}/#{options.folder}"
run(command)
