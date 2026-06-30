#!/usr/bin/env ruby
# == NAME
# script.rb
#
# == AUTHOR
#  Marc Hoeppner, mphoeppner@gmail.com

require 'optparse'
require 'ostruct'
require 'json'

def validate_gabi_folder(folder)

    valid = true

    if !Dir.exist?(folder)
        return false
    end

    if !File.exist?("#{folder}/samples")
        return false
    end

    if Dir["#{folder}/samples/*/*qc.json"].empty?
        return false
    end

    if Dir["#{folder}/samples/*/assembly/*.fasta"].empty?
        return false
    end

    return valid

end

### Get the script arguments and open relevant files
options = OpenStruct.new()
opts = OptionParser.new()
opts.on("-i","--input", "=INPUT","Input folder") {|argument| options.input = argument }
opts.on("-o","--outfile", "=OUTFILE","Output file") {|argument| options.outfile = argument }
opts.on("-h","--help","Display the usage information") {
    puts opts
    exit
}

opts.parse! 

is_valid = validate_gabi_folder(options.input)

o = File.new(options.outfile, "w+")

o.puts "sample\tassembly"

if !is_valid
    warn "Not a valid GABI result folder!"
    exit
end

jsons = Dir["#{options.input}/samples/*/*.qc.json"].map {|f| File.expand_path(f)}

jsons.each do |json|
    
    j = JSON.parse(IO.readlines(json).join)

    sample = j["sample"]
    status = j["qc"]["call"] 
    
    if status == "fail"
        warn "#{sample}\t#{status}"
    end

    next if status == "fail"
    
    path = json.split("/")[0..-2].join("/")

    assembly = + "#{path}/assembly/#{sample}.fasta"

    if File.exist?(assembly)
      o.puts "#{sample}\t#{assembly}"
    end

end

o.close