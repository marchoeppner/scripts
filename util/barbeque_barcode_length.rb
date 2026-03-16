#!/usr/bin/env ruby
# == NAME
# script.rb
#
# == AUTHOR
#  Marc Hoeppner, mphoeppner@gmail.com

require 'optparse'
require 'ostruct'

def calculate_stats(numbers)
    return { mean: 0, standard_deviation: 0, min: 0, max: 0 } if numbers.empty?
  
    numbers.sort!

    # 1. Calculate the Mean (Average)
    # Use 0.0 to ensure float division
    mean = numbers.sum(0.0) / numbers.size
  
    # 2. Calculate Variance (average of squared differences from the mean)
    # Sample variance uses (size - 1) in the denominator, population uses size
    # We'll do sample variance here as it's common.
    sum_of_squared_diffs = numbers.inject(0) { |sum, num| sum + (num - mean)**2 }
    variance = sum_of_squared_diffs / (numbers.size - 1).to_f
  
    # 3. Calculate Standard Deviation (square root of variance)
    std_dev = Math.sqrt(variance)

    min = mean - (std_dev * 2)
    max = mean + (std_dev * 2)
  
    { mean: mean.round(2), standard_deviation: std_dev.round(2), min: min.round(2), max: max.round(2) }
  end
  
### Get the script arguments and open relevant files
options = OpenStruct.new()
opts = OptionParser.new()
opts.on("-i","--infile", "=INFILE","Input file") {|argument| options.infile = argument }
opts.on("-o","--outfile", "=OUTFILE","Output file") {|argument| options.outfile = argument }
opts.on("-h","--help","Display the usage information") {
    puts opts
    exit
}

opts.parse! 

lines = IO.readlines(options.infile)
header = lines.shift.strip.split("\t")
entries = []

lines.each do |line|

    elements = line.strip.split("\t")
    data = {}
    header.each_with_index do |h,i|
        data[h] = elements[i]
    end

    entries << data

end

lengths = []

entries.each do |entry|
    lengths << entry["amplicon"].length
end

stats = calculate_stats(lengths)

puts "Mean: #{stats[:mean]}, StdDev: #{stats[:standard_deviation]}, min: #{stats[:min]}, max: #{stats[:max]}"
