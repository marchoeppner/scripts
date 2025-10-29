#!/usr/bin/env ruby
# == NAME
# sanger_samplesheet_from_folder.rb
#
# == AUTHOR
#  Marc Hoeppner, mphoeppner@gmail.com

require 'optparse'
require 'ostruct'

### Get the script arguments and open relevant files
options = OpenStruct.new()
opts = OptionParser.new()
opts.on("-f","--folder", "=FOLDER","Folder with reads to downsample") {|argument| options.folder = argument }
opts.on("-o","--output", "=OUTPUT","Output file") {|argument| options.output = argument }
opts.on("-h","--help","Display the usage information") {
    puts opts
    exit
}

opts.parse! 

def group_files(name) 

    fname = File.basename(name).gsub(" ", "_").gsub(".ab1", "")
    elements = fname.split("_")
    pos = elements.shift
    id = elements.pop
    date = elements.pop
    primer = elements.pop
    sample = elements.join("_")
    
    return sample

end

o = File.new(options.output, "w+")
o.puts "sample\tfwd\trev"

files = Dir["#{options.folder}/*.ab1"].map { |f| File.expand_path(f) }

counter = 0

files.group_by{|f| group_files(f) } do |sample,reads|

        if reads.length != 2
            abort "Failed to properly detect file groupings - #{sample} does not map to 2 files!"
        end
        counter += 1
        o.puts "#{sample}\#t#{reads[0]}\t#{reads[1]}"

end

o.close

warn "Processed #{counter} samples - please check if this number seems correct!"