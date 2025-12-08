#!/usr/bin/env ruby
# == NAME
# script.rb
#
# == AUTHOR
#  Marc Hoeppner, mphoeppner@gmail.com

require 'optparse'
require 'ostruct'

### Get the script arguments and open relevant files
options = OpenStruct.new()
opts = OptionParser.new()
opts.on("-i","--infile", "=INFILE","Input file") {|argument| options.infile = argument }
opts.on("-r","--reference", "=REFERENCE","Reference clusters") {|argument| options.reference = argument }
opts.on("-o","--outfile", "=OUTFILE","Output file") {|argument| options.outfile = argument }
opts.on("-h","--help","Display the usage information") {
    puts opts
    exit
}

opts.parse! 

query = {}
reference = {}

IO.readlines(options.infile).each do |line|
    sample, cluster = line.strip.split("\t")
    query.has_key?(cluster) ? query[cluster] << sample : query[cluster] = [ sample ]
end

IO.readlines(options.reference).each do |line|
    sample, cluster = line.strip.split("\t")
    reference.has_key?(cluster) ? reference[cluster] << sample : reference[cluster] = [ sample ]
end

reference.each do |cluster, samples |

    matches = []

    samples.each do |sample|
        
        query.each do |qcluster, qsamples|

            if qsamples.include?(sample)
                match_cluster = qcluster
                puts "\t#{sample}\t#{qcluster}"
                matches << match_cluster
            end

        end

    end

    puts "-----------------------------"
    if matches.uniq.length > 1

        puts "#{cluster} #{matches.uniq.sort.join(' ')}"

    else

        puts "#{cluster} OK!"

    end
    puts "-----------------------------"

end
    