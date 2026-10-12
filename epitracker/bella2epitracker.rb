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
require 'zlib'
require 'base64'
require 'logger'
require 'date'

# Cache database entries to avoid costly queries
@cache = []

def validate_bella_folder(folder)
  return false unless Dir.exist?(folder)
  return false unless Dir.exist?(File.join(folder, 'report'))
  return false if Dir[File.join(folder, 'report', '*.json')].empty?
  return false unless Dir.exist?(File.join(folder, 'chewbbaca'))
  return false if Dir[File.join(folder, 'reportree', '*dist_hamming.tsv')].empty?

  true
end

def get_cluster(partition, name)
  cached_cluster = @cache.find { |c| c.cgmlst_partition_id == partition.id && c.name == name }
  if cached_cluster
    warn "Cluster #{name} was cached!"
    return cached_cluster
  end

  cluster = Epitracker::Cluster.find_by(cgmlst_partition_id: partition.id, name: name)
  if cluster
    warn "Cluster #{name} found, adding to cache"
    @cache << cluster
    cluster
  else
    payload = {
      "cgmlst_partition_id" => partition.id,
      "name" => name
    }
    cluster = Epitracker::Cluster.create(payload)
    @cache << cluster
    warn "Cluster #{name} created"
    cluster
  end
end

def make_cgmlst_profile(sample, schema, data_file)
  abort "No data file for #{sample.name}" if data_file.nil?

  profile = File.read(data_file)
  assembly = sample.assemblies.first
  encoded_profile = compress_string(profile)

  payload = {
    "assembly_id" => assembly.id,
    "cgmlst_schema_id" => schema.id,
    "profile" => encoded_profile,
    "pipeline" => "marchoeppner/bella",
    "pipeline_version" => "0.3.1"
  }

  Epitracker::CgmlstProfile.create(payload)
end

def compress_file(file_path)
  compress_string(File.read(file_path))
end

def compress_string(data)
  compressed_data = Zlib::Deflate.deflate(data)
  Base64.encode64(compressed_data)
end

def build_tree(samples, matrix)
  # TODO: Implement tree building logic if needed
end

### Get the script arguments and open relevant files
options = OpenStruct.new
opts = OptionParser.new do |o|
  o.on("-i", "--input=INPUT", "Bella results folder") { |argument| options.input = argument }
  o.on("-d", "--db=DB", "Path to db file") { |argument| options.db = argument }
  o.on("-o", "--outfile=OUTFILE", "Output file") { |argument| options.outfile = argument }
  o.on("-t", "--date=DATE", "Creation date to use") { |argument| options.date = argument }
  o.on("-h", "--help", "Display the usage information") do
    puts o
    exit
  end
end
opts.parse!

db_file = options.db || "/work_syn/ngs/projects/epitracker/db/development.sqlite3"
analysis_date = options.date ? Date.parse(options.date) : nil

Epitracker::DBConnection.connect(database: db_file)

basename = File.basename(options.input)
log = Logger.new("bella_#{basename}.log", 'w')
log.level = Logger::INFO

# Validate that this is actually a Bella result
unless validate_bella_folder(options.input)
  warn "Not a valid Bella output folder (#{basename})..."
  exit 1
end

# Get the run data from the first JSON report
json_file = Dir[File.join(options.input, 'report', '*.json')].first
json = JSON.load_file(json_file)

# Set date from JSON unless we specify from command line
analysis_date ||= Date.parse(json["date"])

clusters = json["clusters"]
tree     = json["tree"]
schema   = json["schema"].split("/").last

alleles      = {}
allele_files = Dir[File.join(options.input, 'samples', '*', 'chewbbaca', '*results_alleles.tsv')]

log.error "No alleles found!" if allele_files.empty?

# Collect all cgMLST profiles
allele_files.each do |allele_file|
  this_sample = File.basename(allele_file).gsub("_results_alleles.tsv", "")
  alleles[this_sample] = File.expand_path(allele_file)
end

hamming_distance_file = Dir[File.join(options.input, 'reportree', '*dist_hamming.tsv')].first
distances             = compress_file(hamming_distance_file)

# Summary of nomenclature changes (optional)
status_matrix = Hash.new { |h, k| h[k] = [] }

status_file = Dir[File.join(options.input, 'reportree', '*nomenclature_changes.tsv')].first
if status_file 
  lines = File.readlines(status_file, chomp: true)
  # cluster column includes a date, remove
  header = lines.shift.split("\t").map { |h| h.gsub(/_[0-9]*-[0-9]*-[0-9]*/, "") }
  
  lines.each do |line|
    elements = line.split("\t")
    this_entry = header.zip(elements).to_h
    status_matrix[this_entry["partition"]] << this_entry
  end
end

# Get the schema and check that it exists
cgmlst_schema = Epitracker::CgmlstSchema.find_by(name: schema)

unless cgmlst_schema
  log.warn "Could not find the used schema #{schema} in the database"
  exit 1
end

# Get a list of pre-configured partitions (aka cluster distances)
partitions = cgmlst_schema.cgmlst_partitions

if partitions.empty?
  log.warn "No partitions exist for this cgMLST schema (#{schema})"
  exit 1
end

# Create this analysis
payload = {
  "cgmlst_schema_id" => cgmlst_schema.id,
  "comments" => "",
  "hamming_distance" => distances,
  "tree" => compress_string(tree.strip),
  "created_at" => analysis_date
}

analysis = Epitracker::ClusterAnalysis.create(payload)
log.info "Built a new analysis (id: #{analysis.id})..."

log.info "Found #{partitions.length} configured partitions, iterating now..."

partitions.each do |part|
  log.info "Processing partition #{part.distance}..."

  # Link the partition to this analysis
  payload = {
    "cgmlst_partition_id" => part.id,
    "cluster_analysis_id" => analysis.id
  }
  xref_analysis_partition = Epitracker::XrefAnalysisPartition.create(payload)
  log.info "Linking partition #{part.distance} to the new analysis (id: #{xref_analysis_partition.id})..."

  clusters.each do |dist, entries|
    # only get the clusters for this clustering distance
    next unless dist.to_i == part.distance

    log.info "Found clusters calculated for this partition..."

    entries.each do |sample_name, cluster_name|
      log.info "Processing sample #{sample_name}.."
      sample = Epitracker::Sample.find_by(name: sample_name)
      
      if sample.nil?
        log.error "Missing sample #{sample_name} in database!"
        next # Verhindert NoMethodError bei nachfolgenden Aufrufen
      end
      
      cgmlst_profiles = sample.assemblies.first.cgmlst_profiles
      this_profile = cgmlst_profiles.find { |c| c.cgmlst_schema_id == cgmlst_schema.id }
      
      unless this_profile
        log.info "Missing a cgMLST profile for #{sample_name} - building new one."
        this_profile = make_cgmlst_profile(sample, cgmlst_schema, alleles[sample_name])
      end

      # get existing cluster or create new one
      cluster = get_cluster(part, cluster_name)
      log.info "Checked and created Cluster #{cluster_name}..."

      xref_analysis_partition_cluster = Epitracker::XrefAnalysisPartitionCluster.find_by(
        cluster_id: cluster.id, 
        xref_analysis_partition_id: xref_analysis_partition.id
      )

      # link cluster to analysis-partition link
      unless xref_analysis_partition_cluster
        log.info "Cluster #{cluster_name} (#{cluster.id}) not yet linked to this partition analysis (#{xref_analysis_partition.id})..."
        status = "new"
        
        # Nutzen von part.distance.to_s, da status_matrix String-Schlüssel hält
        if status_matrix.key?(part.distance.to_s)
          # Find if this cluster has undergone a nomenclature change
          entry = status_matrix[part.distance.to_s].find { |s| s["cluster"] == cluster_name }
          if entry
            status = entry["nomenclature_change"]
            log.info "Updating cluster status to #{status}"
          end
        end
        
        payload = {
          "cluster_id" => cluster.id,
          "xref_analysis_partition_id" => xref_analysis_partition.id,
          "comments" => "",
          "status" => status
        }
        xref_analysis_partition_cluster = Epitracker::XrefAnalysisPartitionCluster.create(payload)
        log.info "Linked cluster #{cluster_name} (#{cluster.id}) to the analysis partition (#{xref_analysis_partition.id})..."
      end

      # Link cgmlst profile (=assembly) to cluster and analysis_partition
      payload = {
        "cluster_id" => cluster.id,
        "cgmlst_profile_id" => this_profile.id,
        "xref_analysis_partition_id" => xref_analysis_partition.id
      }

      Epitracker::XrefProfileAnalysisPartitionCluster.create(payload)
      log.info "Linked together cgMLST profile, cluster and analysis partition..."
    end
  end
end
