#!/usr/bin/env ruby
# == NAME
# script.rb
#
# == AUTHOR
#  Marc Hoeppner, mphoeppner@gmail.com
# The script does the following
# 1. Import any new genome assemblies into database
# 2. If new assemblies were imported, run a new cluster analysis
# 3. Import cluster information into database
# 4. Compute new per-cluster minimum spanning trees

require 'optparse'
require 'ostruct'
require 'date'
require 'epitracker'
require 'logger'
require 'fileutils'
require 'open3'

# A lightweight struct to hold the command's execution results cleanly
CommandResult = Struct.new(:success?, :stdout, :stderr, :exit_code, :error_message)

def execute_command(cmd, *args)
  # Open3.capture3 handles execution safely, separating streams and exposing exit status
  stdout_str, stderr_str, status = Open3.capture3(cmd, *args)

  if status.success?
    CommandResult.new(true, stdout_str, stderr_str, status.exitstatus, nil)
  else
    error_msg = "Command '#{cmd}' failed with exit code #{status.exitstatus}."
    CommandResult.new(false, stdout_str, stderr_str, status.exitstatus, error_msg)
  end
rescue Errno::ENOENT => e
  # Caught specifically if the binary/command executable cannot be found on the host system
  error_msg = "System dependency missing: The command '#{cmd}' was not found."
  CommandResult.new(false, '', e.message, nil, error_msg)
rescue => e
  # Catch-all for unexpected low-level environment or system exceptions
  CommandResult.new(false, '', e.message, nil, "Unexpected error: #{e.message}")
end

def rollback_database(db, backup)
    command = "cp #{backup} #{db}"
    run_command(command)
end

### Get the script arguments and open relevant files
options = OpenStruct.new()
opts = OptionParser.new()
opts.on("-d","--db", "=DB","Path to db file") {|argument| options.db = argument }
opts.on("-h","--help","Display the usage information") {
    puts opts
    exit
}

opts.parse! 

options.db ? db_file = options.db : db_file = "/work_syn/ngs/projects/epitracker/db/development.sqlite3"

warn "EPITRACKER WRAPPER SUITE"
warn "Automatically load and cluster genome samples"
warn "============================================="
warn ""

log = Logger.new File.open('epitracker_wrapper.log', 'w+')
log.level = Logger::INFO

#-------------------------------------
# Check if we can connect to datbase
#-------------------------------------

log.info "Connecting to database on #{db_file}..."

Epitracker::DBConnection.connect({database: db_file})
connection = Epitracker::DBConnection.lease_connection

if !connection
  log.warn "Could not connect to database!"
  abort
end

# -------------------------------
# list of prerequisites
# -------------------------------

BASEDIR             = "/work_syn/ngs/projects/epitracker"
DATADIR             = "/work_syn/ngs/analyses"
GABI_TO_EPITRACKER  = "/home/mhoeppner/git/scripts/epitracker/gabi2epitracker.rb"
BELLA_TO_EPITRACKER = "/home/mhoeppner/git/scripts/epitracker/bella2epitracker.rb"
BELLA_VERSION       = "1.0.1"
BELLA_CREATE_ANALYSIS = "/home/mhoeppner/git/scripts/epitracker/create_analysis.rb"
CLUSTER_TREES       = "/home/mhoeppner/git/scripts/epitracker/cluster_trees.rb"

[BASEDIR, DATADIR, GABI_TO_EPITRACKER, BELLA_TO_EPITRACKER, BELLA_CREATE_ANALYSIS, CLUSTER_TREES].each do |prereq|
    if !File.exist?(prereq)
        log.warn "Failed to find dependency #{prereq}"
        abort "Missing critical dependency: #{prereq}"
    end
end

LOGDIR = Dir.getwd + "/logs"
FileUtils.mkdir_p(LOGDIR)
LOGFILE = "#{LOGDIR}/logs.txt"

log.info "Starting processing #{Dir.getwd}"

# List of GABI runs to process
worksheet = []

# -------------------------------------------------
# Create a copy of the database so we can roll back
# any failed updates
# -------------------------------------------------
log.info "Performing a backup of the current database..."

backup_name = File.basename(db_file) + ".bak"
database_backup = Dir.getwd + "/backup/#{backup_name}"

File.mkdir_p("backup")
command = "cp #{db_file} backup/#{backup_name}"
system(command)

if File.exist?("backup/#{backup_name}")
    log.info "Backup complete!"
else
    log.error "Backup of database failed!"
    exit 1
end
# ------------------------------------------------
# Check if any of the existing GABI results are not yet in the database
# ------------------------------------------------

gabi_folders = Dir["#{DATADIR}/2*_M*/gabi_1.3.0/*/results"].map {|f| File.expand_path(f)}

log.info "Checking GABI result folders for new samples"

gabi_folders.each do |path|

    basename = path.split("/")[-4]

    samples = Dir["#{path}/samples/*"].map {|f| File.basename(f)}
    
    is_processed = false

    # If any of the samples is already in the db, 
    # we assume the run has already been processed
    samples.each do |sample|
        next if is_processed
        db = Epitracker::Sample.find_by_name(sample)
        if db
            is_processed = true
        end
    end

    # Check if this run needs to added to the database
    if !is_processed
        log.info "GABI run #{basename} not yet in database, adding to worksheet."        
        worksheet << path
    else
        log.info "GABI run #{basename} already in database, skipping."
    end

end

log.info "Compiled #{worksheet.length} new worksheet entries."

# ------------------------------------------------
# Load all the new samples into the database
# ------------------------------------------------

worksheet.each do |path|

    basename = path.split("/")[-4]
    
    log.info "Loading run #{basename} into database"

    results = execute_command(GABI_TO_EPITRACKER, "-i #{path}")

    if !result.success?
        log.error "Failed GABI import: #{result.error_message}"
        log.info "Rolling back the database and exiting..."
        rollback_database(db_file,backup_database)
        exit 1
    end

end

organisms = Epitracker::Organism.all

# ------------------------------------------------
# Check for each organism if a new Bella analysis is required
# ------------------------------------------------

# Track if a new cluster analysis is performed, requiring new cluster trees
new_trees = false

organisms.each do |o|

    log.info "Checking if we need to run a new cluster analysis for #{o.name}"

    default_schema  = o.cgmlst_schemas.first
    latest_analysis = default_schema.cluster_analyses.last
    latest_sample   = o.samples.last

    # Run Bella if the latest sample is newer than the latest analysis
    if !latest_analysis or latest_sample.created_at > latest_analysis.created_at

        new_trees = true

        log.info "Need to compute a new cluster analysis for #{o.name}"
        
        this_date       = Date.today.strftime("%F")
        run_dir         = "#{BASEDIR}/#{o.name}/#{this_date}"
        analysis_dir    = "#{run_dir}/data"
        
        # Create folder for the pipeline run
        FileUtils.mkdir_p(analysis_dir)
        
        Dir.chdir(run_dir) do |dir|

            log.info "Creating Bella analysis for schema #{default_schema.name}"

            # Export the relevant data from the database to run a new analysis; this
            # goes into a sub folder, by definition
            Dir.chdir(analysis_dir) do |adir|
                result = execute_command(BELLA_CREATE_ANALYSIS, "-s #{default_schema.name}")
                if !result.success?
                    log.error "Failed to create BELLA analysis - aborting"
                    exit 1
                end
            end

            log.info "Running Bella pipeline for #{default_schema.name}"

            # Execute the pipeline script generated by bella create analysis
            result = execute_command("bash data/run.sh")

            # If command line call failed:
            if !result.success?
                log.error "Failed to run Bella analysis!"
                rollback_database(db_file, backup_database)
                exit 1
            end
            
            log.info "Loading Bella results into database"

            # Import Bella results into database
            result = execute_command(BELLA_TO_EPITRACKER, "-i results")

            # If import failed
            if !result.success?
                log.error "Failed BELLA import: #{result.error_message}"
                log.info "Rolling back the database and exiting..."
                rollback_database(db_file,backup_database)
                exit 1
            end

        end
    else
        log.info "No #{o.name} samples added after most recent analysis, nothing to do..."   
    end

end

if new_trees
    # Now built all the missing cluster trees
    log.info "Updating cluster trees..."
    result = execute_command(CLUSTER_TREES)
    if !result.success?
        log.error "Failed to compute cluster trees"
        exit 1
    end
end