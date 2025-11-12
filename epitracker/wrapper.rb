#!/usr/bin/env ruby
# == NAME
# script.rb
#
# == AUTHOR
#  Marc Hoeppner, mphoeppner@gmail.com

require 'optparse'
require 'ostruct'
require 'date'

### Get the script arguments and open relevant files
options = OpenStruct.new()
opts = OptionParser.new()
opts.on("-i","--infile", "=SETID","Get info for this set") {|argument| options.set_id = argument }
opts.on("-o","--outfile", "=OUTFILE","Output file") {|argument| options.outfile = argument }
opts.on("-h","--help","Display the usage information") {
    puts opts
    exit
}

opts.parse! 

BASEDIR = "/work_syn/ngs/outbreak/epitracker"
RUNDIR = "/work_syn/ngs/runs/miseq"

configs = {
    "ecoli" => {
        "schema" => "escherichia --efsa"
    },
    "listeria" => {
        "schema" => "listeria"
    },
    "senterica" => {
        "schema" => "salmonella --efsa"
    },  
    "campylobacter" => {
        "schema" => "capylobacter"
    }
}

run_info = {}
runs = Dir["#{BASEDIR}/2*_*"].map{|d| File.expand_path(d)}

# Get all gabi runs
runs.each do |run|
    #date_info = run.split("_")[0].chars.each_slice(2).map(&:join)
    date_info = File.basename(run).split("_")[0]
    date = Date.parse(date_info)
    run_info[date] = File.new(run)
end

configs.each do |species, data|
    warn species

    process_runs = []
    analyses = Dir["#{BASEDIR}/#{species}/*"].map {|a| File.expand_path(a)}.sort_by{|a| File.new(a).ctime}
    recent_analysis = analyses.last

    if recent_analysis
        puts recent_analysis
    else
        puts "No analyses performed yet"
    end

end