#!/usr/bin/env ruby
# == NAME
# metadata_set_to_table.rb
#
# == AUTHOR
#  Marc Hoeppner, mphoeppner@gmail.com

require 'optparse'
require 'ostruct'
require 'rest_client'
require 'json'
<<<<<<< HEAD
require "zlib"
require 'base64'
=======
require 'fileutils'
>>>>>>> 82ec382f4b08ecf76faee85a1ff1127b39cc612e

# Configuration
$server = 'localhost:3001/api/v1'

# Rate limiting metrics
$request_counter = 0
$last_request_time = 0

def rest_request(method, url, payload = nil)
  $request_counter += 1
  if $request_counter == 15
    diff = Time.now - $last_request_time
    sleep(1 - diff) if diff < 1
    $request_counter = 0
  end

  begin
    full_url = "#{$server}/#{url}"
    response = if method == :get
        RestClient.get(full_url, accept: :json)
    else
        RestClient.patch(full_url, payload, accept: :json)
    end

    $last_request_time = Time.now
    JSON.parse(response)
  rescue RestClient::Exception => e
    warn 'Failed for ' + url + '! ' + (response ? "Status code: #{response}. " : '') + 'Reason: ' + e.message

    if e.response&.headers&.[](:retry_after)
      sleep(e.response.headers[:retry_after].to_f)
      retry
    else
      abort("Quitting... #{e.inspect}")
    end
  end
end

def compress_string(data)

    compressed_data = Zlib::Deflate.deflate(data)
    encoded_data = Base64.encode64(compressed_data)

    return encoded_data

end

def build_slurm_script(job)
  sbatch_boilerplate = <<~SCRIPT
    #!/bin/bash
    #SBATCH -J Job-#{job['id']}
    #SBATCH --nodes=1
    #SBATCH --time=10:00:00
    #SBATCH --mem=4000
    #SBATCH --ntasks=1
    #SBATCH -e slurm.err
    #SBATCH --cpus-per-task=1
    #{job['command']}
  SCRIPT

  File.write("slurm.sh", sbatch_boilerplate)
  "slurm.sh"
end

def submit_job(file)
  `sbatch #{file}`.slice(/\d+/).to_i
end

def get_status(slurm_id)
  status = `scontrol show job #{slurm_id}` rescue ""
  return "unknown" if status.empty?

  status.slice(/JobState=[A-Z]*/)&.split("=")&.last&.downcase || "unknown"
end

def find_file(job, extension, filter_keywords = [])
  reports_dir = File.join(job["run_path"], "results", "reports")
  return nil unless File.directory?(reports_dir)

  files = Dir[File.join(reports_dir, "*.#{extension}")]
  return files.first if files.length == 1

  files.find { |f| filter_keywords.none? { |kw| f.include?(kw) } } if files.length > 1
end

def load_qc(job)
  
    json = nil
    if File.directory?("#{job['run_dir']}/results/reports")
      jsons = Dir["#{job['run_dir']}/results/reports/*.json"]
      if json.length > 0
        json = jsons.first
      end
    end

    if json
      json_b = compress_string(IO.readlines(json).join)
      payload = { run: { id: job["run_id"], qc_json: json_b } } 
      rest_put("run/#{job['run_id']}", payload)
    end

end

### Get the script arguments and open relevant files
options = OpenStruct.new()
opts = OptionParser.new()
opts.on("-o","--outfile", "=OUTFILE","Output file") {|argument| options.outfile = argument }
opts.on("-h","--help","Display the usage information") {
    puts opts
    exit
}

# Process jobs
jobs = rest_request(:get, "jobs")

jobs.each do |job|
  case job["status"]
  when "created"
    warn "Found new job - submitting"
    job_id = nil
    Dir.chdir(job["run_path"]) do
      file = build_slurm_script(job)
      job_id = submit_job(file)
    end
    payload = { job: { id: job["id"], job_id: job_id, status: "submitted" } }
    rest_request(:patch, "jobs/#{job['id']}", payload)

  when "submitted", "running", "pending"
    warn "Active job #{job['slurm_id']}, updating status..."
    status = get_status(job["job_id"])
    payload = { job: { id: job["id"], status: status, log: File.join(job['run_path'], "slurm.err") } }
    rest_request(:patch, "jobs/#{job['id']}", payload)

  when "failed"
    warn "Failed job #{job['slurm_id']}..."
    if job["attempts"].to_i < 3
      warn "\tResubmitting!"
      job_id = nil
      Dir.chdir(job["run_path"]) { job_id = submit_job("slurm.sh") }
      payload = { job: { id: job["id"], status: "submitted", attempts: job["attempts"].to_i + 1, job_id: job_id } }
      rest_request(:patch, "jobs/#{job['id']}", payload)
    end

  when "completed"

    next if job["completed"]
    
    # Securely remove the work directory
    wd = File.join(job['run_path'], "work")
    FileUtils.rm_rf(wd) if File.directory?(wd)

    payload = { job: { id: job["id"], completed: true } }

    if !job["report"] && job["command"].include?("nextflow")
      report = find_file(job, "html", %w[multiqc illumina nanopore krona])
      payload[:job][:report] = File.expand_path(report) if report
    end

    rest_request(:patch, "jobs/#{job['id']}", payload)

    if job["depends_on"]
      rest_request(:patch, "jobs/#{job['depends_on']}", { job: { is_archived: true } })
    end

    if job["command"].include?("read-qc")
      json = find_file(job, "json", [])
      if json
        payload = { run: { id: job["run_id"], qc_json: JSON.load_file(json) } }
        rest_request(:patch, "/runs/#{job['run_id']}", payload)
      end
    end
  end
end
