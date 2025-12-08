#!/usr/bin/env ruby
# == NAME
# script.rb
#
# == AUTHOR
#  Marc Hoeppner, mphoeppner@gmail.com

require 'optparse'
require 'ostruct'
require 'epitracker'
require 'json'
require "zlib"
require 'base64'

@cache = []


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

    if Dir["#{folder}/chewbbaca/results_*/results_alleles.tsv"].empty?
        return false
    end

    if Dir["#{folder}/reportree/*dist_hamming.tsv"].empty?
        return false
    end

    return valid
    
end

def get_cluster(partition, name)

    cached_cluster = @cache.find { |c| c.cgmlst_partition_id == partition.id && c.name == name }
    if cached_cluster
        return cached_cluster
    else
        payload = {
            "cgmlst_partition_id" => partition.id,
            "name" => name
        }
        cluster = Epitracker::Cluster.create(payload)
        @cache << cluster
        return cluster
    end

end

def make_cgmlst_profile(sample, schema, alleles)

    data = [ alleles[0] ]
    data << alleles.find {|a| a.include?(sample.name)}

    assembly = sample.assemblies.first

    profile = data.join("\n")
    compressed_profile = Zlib::Deflate.deflate(profile)
    encoded_profile = Base64.encode64(compressed_profile)

    payload = {
        "assembly_id" => assembly.id,
        "cgmlst_schema_id" => schema.id,
        "profile" => encoded_profile,
        "pipeline" => "marchoeppner/bella",
        "pipeline_version" => "0.3.1"
    }

    cgmlst_profile = Epitracker::CgmlstProfile.create(payload)

    return cgmlst_profile

end

def compress_file(file_path)

    data = IO.readlines(file_path).join("\n")
    compressed_data = Zlib::Deflate.deflate(data)
    encoded_data = Base64.encode64(compressed_data)

    return encoded_data

end

def log(message)

    this_date = Time.now
    warn "#{this_date}: #{message}"
    sleep 1

end

### Get the script arguments and open relevant files
options = OpenStruct.new()
opts = OptionParser.new()
opts.on("-i","--input", "=INPUT","Bella results folder") {|argument| options.input = argument }
opts.on("-d","--db", "=DB","Path to db file") {|argument| options.db = argument }
opts.on("-o","--outfile", "=OUTFILE","Output file") {|argument| options.outfile = argument }
opts.on("-h","--help","Display the usage information") {
    puts opts
    exit
}

opts.parse! 

options.db ? db_file = options.db : db_file = "/home/mhoeppner/git/epitracker/storage/development.sqlite3"

Epitracker::DBConnection.connect({database: db_file})

valid = validate_bella_folder(options.input)

if !valid
    warn "Not a valid Bella output folder..."
    exit
end

json_file = Dir["#{options.input}/report/*.json"].first
json = JSON.parse(IO.readlines(json_file).join)

date_string = json["date"]
analysis_date = Date.parse(date_string)

clusters = json["clusters"]
tree = json["tree"]
schema = json["schema"].split("/")[-1]

alleles_file = Dir["#{options.input}/chewbbaca/results_*/results_alleles.tsv"].first
alleles = IO.readlines(alleles_file)

hamming_distance_file = Dir["#{options.input}/reportree/*dist_hamming.tsv"].first
distances = compress_file(hamming_distance_file)

status_matrix = {}
status_file = Dir["#{options.input}/reportree/*nomenclature_changes.tsv"].first
if status_file 
    lines = IO.readlines(status_file)
    # cluster column includes a date, remove
    header = lines.shift.split("\t").map {|h| h.gsub(/_[0-9]*-[0-9]*-[0-9]*/, "")}
    lines.each do |line|
        elements = line.split("\t")
        this_entry = {}
        elements.each_with_index do |e,i|
            this_entry[header[i]] = e
        end
        status_matrix.has_key?(this_entry["partition"]) ? status_matrix[this_entry["partition"]].append(this_entry) : status_matrix[this_entry["partition"]] = [ this_entry ]
    end
end

# Get the schema and check that it exists
cgmlst_schema = Epitracker::CgmlstSchema.find_by_name(schema)

if !cgmlst_schema
    warn "Could not find the used schema #{schema} in the database"
    exit
end

partitions = cgmlst_schema.cgmlst_partitions

if partitions.empty?
    warn "No partitions exist for this cgMLST schema (#{schema})"
    exit
end

# Create this analysis
payload = {
    "cgmlst_schema_id" => cgmlst_schema.id,
    "comments" => "",
    "hamming_distance" => distances,
    "tree" => tree.strip,
    "created_at" => analysis_date
}

analysis = Epitracker::ClusterAnalysis.create(payload)
log("Built a new analysis...")

log("Found #{partitions.length} configured partitions, iterating now...")

partitions.each do |part|

    log("Processing partition #{part.distance}...")

    # Link the partition to this analysis
    payload = {
        "cgmlst_partition_id" => part.id,
        "cluster_analysis_id" => analysis.id
    }
    xref_analysis_partition = Epitracker::XrefAnalysisPartition.create(payload)
    log("Linking partition #{part.distance} to the new analysis...")

    clusters.each do |dist,entries|

        # only get the clusters for this clustering distance
        next unless dist.to_i == part.distance

        log("Found clusters calculated for this partition...")

        entries.each do |sample_name,cluster_name|

            sample = Epitracker::Sample.find_by_name(sample_name)

            cgmlst_profiles = sample.assemblies.first.cgmlst_profiles

            this_profile = cgmlst_profiles.find {|c| c.cgmlst_schema_id == cgmlst_schema.id }
            if !this_profile
                log("Missing a cgMLST profile for #{sample_name} - building new one.")
                this_profile = make_cgmlst_profile(sample, cgmlst_schema, alleles)
            end

            # get existing cluster or create new one
            cluster = get_cluster(part, cluster_name)
            log("Checked and created Cluster #{cluster_name}...")

            xref_analysis_partition_cluster = Epitracker::XrefAnalysisPartitionCluster.where(cluster_id: cluster.id, xref_analysis_partition_id: xref_analysis_partition.id).first

            if !xref_analysis_partition_cluster
                # link cluster to analysis-partition link
                log("Cluster not yet linked to this partition analysis...")
                status = "new"
                if status_matrix.has_key?(part.partition)
                    entry = status_matrix[part.partition].find {|s| s["cluster"] == cluster_name }
                    if entry
                        status = entry["nomenclature_change"]
                        log("Updating cluster status to #{status}")
                    end
                end
                
                payload = {
                    "cluster_id" => cluster.id,
                    "xref_analysis_partition_id" => xref_analysis_partition.id,
                    "comments" => "",
                    "status" => status
                }
                xref_analysis_partition_cluster = Epitracker::XrefAnalysisPartitionCluster.create(payload)
                log("Linked cluster to the analysis partition...")
            end

            # Link cgmlst profile (=assembly) to cluster and analysis_partition
            payload = {
                "cluster_id" => cluster.id,
                "cgmlst_profile_id" => this_profile.id,
                "xref_analysis_partition_id" => xref_analysis_partition.id
            }
            xref_profile_analysis_partition_cluster = Epitracker::XrefProfileAnalysisPartitionCluster.create(payload)
            log("Linked together cgMLST profile, cluster and analysis partition...")
        end

    end

end

