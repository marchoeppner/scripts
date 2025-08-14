#!/usr/bin/env ruby
# == NAME
# downsample_reads.rb
#
# == AUTHOR
#  Marc Hoeppner, mphoeppner@gmail.com

require 'optparse'
require 'ostruct'
require 'fileutils'
require 'thread'

def check_binary(binary)
    status = `which #{binary} 2>&1`
    if status.include?("no #{binary} in")
        abort "Binary #{binary} not installed, exiting."
    end
end

def run(command)
    warn "#{Time.now} - #{command}"
    system(command)
end

### Get the script arguments and open relevant files
options = OpenStruct.new()
opts = OptionParser.new()
opts.on("-f","--folder", "=FOLDER","Folder with reads to downsample") {|argument| options.folder = argument }
opts.on("-o","--outdir", "=OUTDIR","Output directory") {|argument| options.outdir = argument }
opts.on("-c","--cores", "=CORES","Number of cores to use") {|argument| options.cores = argument }
opts.on("-s","--seed", "=SEED","Random seed") {|argument| options.seed = argument }
opts.on("-h","--help","Display the usage information") {
    puts opts
    exit
}

opts.parse! 

task_queue = Queue.new

options.cores ? cores = options.cores.to_i : cores = 4
buckets = [ 1000, 2000, 5000, 10000, 15000, 20000, 25000, 30000, 40000, 50000, 75000, 100000 ]

options.seed ? seed = options.seed : seed = "123456"

check_binary("seqtk")

if !options.folder
    abort "No data folder specified, exiting"
end

reads = Dir["#{options.folder}/*.fastq.gz"].map {|f| File.expand_path(f) }

if !File.directory?(options.outdir)
    run("mkdir -p #{options.outdir}")
end 

Dir.chdir(options.outdir) do |dir|

    reads.each do |read|
        buckets.each do |bucket|
            
            b = File.basename(read).gsub(".fastq.gz", "")
            libary = b.split("_")[0]
            b.include?("_001") ? lane = b.split("_")[-2] : lane = b.split(".")[0].split("_")[-1]
            r = "#{libary}_#{bucket}_#{lane}.fastq.gz"
            task_queue << "seqtk sample -s#{seed} #{read} #{bucket} | gzip -c > #{options.outdir}/#{r}"
        end
    end
end

workers = cores.times.map do
  Thread.new do
    until task_queue.empty?
      task = task_queue.pop(true) rescue nil
      if task
        puts "Processing task #{task} by #{Thread.current.object_id}"
        run(task)
      end
    end
  end
end

workers.each(&:join)
puts "All tasks completed."
