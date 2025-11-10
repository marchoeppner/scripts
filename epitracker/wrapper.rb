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

BASEDIR = "/work_syn/ngs/pipelines/bella"
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
runs = Dir["#{RUNDIR}/2*_*"].map{|d| File.expand_path(d)}

runs.each do |run|
    #date_info = run.split("_")[0].chars.each_slice(2).map(&:join)
    date_info = File.basename(run).split("_")[0]
    date = Date.parse(date_info)
    run_info[date] = run
end

configs.each do |species, data|

end