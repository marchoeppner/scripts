
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
opts.on("-g","--gabi", "=GABI","Gabi summary") {|argument| options.gabi = argument }
opts.on("-a","--aquamis", "=AQUAMIS","Aquamis summarys") {|argument| options.aquamis = argument }
opts.on("-o","--outfile", "=OUTFILE","Output file") {|argument| options.outfile = argument }
opts.on("-h","--help","Display the usage information") {
    puts opts
    exit
}

opts.parse! 

aquamis = {}
gabi = {}

same = 0
different = 0

mismatch = []

IO.readlines(options.aquamis).each do |line|
	sample,status = line.strip.split("\t")
	aquamis[sample] = status
end

IO.readlines(options.gabi).each do |line|
	elements = line.strip.split("\t")
	sample,status, mlst = elements[0..1]
	status = "pass" if status == "warn"
	gabi[sample] = status
end

gabi.each do |sample,status|

	if aquamis.has_key?(sample)
		match = aquamis[sample]
		status == match ? same += 1 : different += 1

		if status != match
			mismatch << sample
		end
	else 
		abort "Missing sample #{sample}"
	end

end


accuracy = same.to_f / (same + different).to_f
puts accuracy

puts
puts mismatch.join(" ")

puts "Total samples: #{same + different}"
puts "Matches: #{same}"
puts "Mismatches: #{different}"
