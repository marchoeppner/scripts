#!/usr/bin/env ruby
# == NAME
# script.rb
#
# == AUTHOR
#  Marc Hoeppner, mphoeppner@gmail.com

require 'optparse'
require 'ostruct'

def validate_bella_folder(folder)

    valid = true

    if !Dir.exist?(folder)
        return false
    end

    if !Dir.exist?("#{folder}/report")
        return false
    end

    if Dir["#{folder}/report/*.json"].empty?
        return false
    end

    if !Dir.exist?("#{folder}/chewbbaca")
        return false
    end

    if Dir["#{folder}/reportree/*dist_hamming.tsv"].empty?
        return false
    end

    return valid
    
end

### Get the script arguments and open relevant files
options = OpenStruct.new()
opts = OptionParser.new()
opts.on("-i","--input", "=INPUT","Bella folder") {|argument| options.input = argument }
opts.on("-o","--outfile", "=OUTFILE","Output file") {|argument| options.outfile = argument }
opts.on("-h","--help","Display the usage information") {
    puts opts
    exit
}

opts.parse! 

valid = validate_bella_folder(options.input)

if !valid
    warn "Not a valid Bella output folder..."
    exit
end

