#!/usr/bin/env ruby
# == NAME
# script.rb
#
# == AUTHOR
#  Marc Hoeppner, mphoeppner@gmail.com

require 'optparse'
require 'ostruct'
require 'rake'

### Get the script arguments and open relevant files
options = OpenStruct.new()
opts = OptionParser.new()
opts.on("-v","--version", "=VERSION","Pipeline version") {|argument| options.version = argument }
opts.on("-o","--outfile", "=OUTFILE","Output file") {|argument| options.outfile = argument }
opts.on("-h","--help","Display the usage information") {
    puts opts
    exit
}

opts.parse! 

VERSION = "1.3.3"
BASEDIR = "/work_syn/ngs/pipelines/gabi/validation/"

test_ss = "/work_syn/ngs/pipelines/gabi/data/tests/samples.tsv"

task validate: [ "#{BASEDIR}/#{VERSION}/test/results/reports/test.html" ]

file "#{BASEDIR}/#{VERSION}/test/results/reports/test.html" => [ test_ss ] do |t|
    sh "nextflow run bio-raum/gabi -profile lsh -r #{VERSION} --outdir #{BASEDIR}/#{VERSION}/test --input #{t.prerequisites.join(' ')} --run_name test"
end