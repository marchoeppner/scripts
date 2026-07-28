#!/usr/bin/env ruby
# == NAME
# script.rb
#
# == AUTHOR
#  Marc Hoeppner, mphoeppner@gmail.com

require 'optparse'
require 'ostruct'
require 'epitracker'
require 'zlib'
require 'base64'

### Get the script arguments and open relevant files
options = OpenStruct.new()
opts = OptionParser.new()
opts.on("-i","--infile", "=INFILE","Input file") {|argument| options.infile = argument }
opts.on("-d","--db", "=DB","Path to db file") {|argument| options.db = argument }
opts.on("-o","--outfile", "=OUTFILE","Output file") {|argument| options.outfile = argument }
opts.on("-h","--help","Display the usage information") {
    puts opts
    exit
}

opts.parse! 

options.db ? db_file = options.db : db_file = "/work_syn/ngs/projects/epitracker/db/development.sqlite3"

chewbbaca_container = "/work_syn/singularity_cache/depot.galaxyproject.org-singularity-chewbbaca-3.3.10--pyhdfd78af_0.img"
reportree_container = "/work_syn/singularity_cache/mhoeppner-reportree-2.6.0.img"

Epitracker::DBConnection.connect({database: db_file})

log = Logger.new File.open('cluster.log', 'w')
log.level = Logger::INFO

clusters = Epitracker::Cluster.all

clusters.each do |cluster|
  
    # Welche analysen wurden durchgeführt
    xref_analysis_partitions_clusters = cluster.xref_analysis_partition_clusters
    xref_analysis_partitions = xref_analysis_partitions_clusters.map {|x| x.xref_analysis_partition }

    xref_profile_analysis_partition_clusters = cluster.xref_profile_analysis_partition_clusters

    # für jede combination von cluster und analyse, die liste aller cgmlst Profile
    
    xref_analysis_partitions_clusters.each do |xref_apc|

        xref_ap = xref_apc.xref_analysis_partition
      
        analysis = xref_ap.cluster_analysis
        xref_profiles = Epitracker::XrefProfileAnalysisPartitionCluster.where(xref_analysis_partition_id: xref_ap.id, cluster_id: cluster.id )

        profiles = xref_profiles.map {|x| x.cgmlst_profile }
        samples = profiles.map {|profile| profile.assembly.sample}

        # Can't build a tree for less than 3 samples
        next if samples.length < 3

        sample_list = samples.map {|s| s.name }.join(",")
        puts "#{cluster.name}\t#{analysis.id}\t#{analysis.cgmlst_schema.name}\t#{sample_list}"

        # Dump profiles to tsv files
         
        profiles.each do |profile|
          f = File.new("#{profile.assembly.sample.name}.tsv", "w+")
          matrix = Zlib.inflate(Base64.decode64(profile.profile))
          f.puts matrix
          f.close
        end

        warn "Running JoinProfiles"
        # Chewbbaca join profiles
        command = "apptainer exec #{chewbbaca_container} chewBBACA.py JoinProfiles -p *.tsv -o alleles.tsv"
        system(command)

        warn "Running ExtractCgmlst"
        # Chewbbaca clean matrix
        command = "apptainer exec #{chewbbaca_container} chewBBACA.py ExtractCgMLST -i alleles.tsv --t 0 -o filtered"
        system(command)

        # Reportree
        warn "Running Reportree"
        command = "apptainer exec #{reportree_container} reportree.py -a filtered/cgMLST0.tsv -out cluster_#{cluster.id} --HC-threshold single-1-50 --loci-called 0.95 --analysis HC"
        system(command)

        nwk_file = "cluster_#{cluster.id}_single_HC.nwk"
        tree = IO.readlines(nwk_file).join

        compressed_tree = Zlib::Deflate.deflate(tree)
        encoded_tree = Base64.encode64(compressed_tree)

        xref_apc.tree = encoded_tree
        xref_apc.save

        system("rm -R *.tsv filtered")

    end
    
end