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

def rest_get(url)
	
    $request_counter ||= 0   # Initialise if unset  
    $last_request_time ||= 0 # Initialise if unset

    # Rate limiting: Sleep for the remainder of a second since the last request on every third request
    $request_counter += 1
    if $request_counter == 15 
    diff = Time.now - $last_request_time
    sleep(1-diff) if diff < 1
    $request_counter = 0
    end

    begin
        response = RestClient.get "#{$server}/#{url}", {:accept => :json}

        $last_request_time = Time.now
        JSON.parse(response)
    rescue RestClient::Exception => e
        puts "Failed for #{url}! #{response ? "Status code: #{response}. " : ''}Reason: #{e.message}"

        # Sleep for specified number of seconds if there is a Retry-After header
        if e.response.headers[:retry_after]
            sleep(e.response.headers[:retry_after].to_f)
            retry # This retries from the start of the begin block
        else
            abort("Quitting... #{e.inspect}")
        end
    end
end

def rest_post(url, payload)
	
    $request_counter ||= 0   # Initialise if unset  
    $last_request_time ||= 0 # Initialise if unset

    # Rate limiting: Sleep for the remainder of a second since the last request on every third request
    $request_counter += 1
    if $request_counter == 15 
    diff = Time.now - $last_request_time
    sleep(1-diff) if diff < 1
    $request_counter = 0
    end

    begin
        response = RestClient.patch "#{$server}/#{url}", payload, {:accept => :json}

        $last_request_time = Time.now
        JSON.parse(response)
    rescue RestClient::Exception => e
        puts "Failed for #{url}! #{response ? "Status code: #{response}. " : ''}Reason: #{e.message}"

        # Sleep for specified number of seconds if there is a Retry-After header
        if e.response.headers[:retry_after]
            sleep(e.response.headers[:retry_after].to_f)
            retry # This retries from the start of the begin block
        else
            abort("Quitting... #{e.inspect}")
        end
    end
end

def build_slurm_script(job)

    command = job["command"]
    sbatch_boilerplate = [
        "#!/bin/bash",
        "#SBATCH -J #{job['name']}",
        "#SBATCH --nodes=1",
        "#SBATCH --time=10:00:00",
        "#SBATCH --mem=4000",
        "#SBATCH --ntasks=1",
        "#SBATCH -e slurm.err",
        "#SBATCH --cpus-per-task=1"
    ]

    s = File.new("slurm.sh", "w+")
    sbatch_boilerplate.each {|l| s.puts l }
    s.puts command
    s.close

    return "slurm.sh"

end

def submit_job(file)

    slurm_id = `sbatch #{file}`.slice(/\d+/)
    return slurm_id.to_i

end

def get_status(slurm_id)

    status = `scontrol show job #{slurm_id}`
    
    if status == ""
        return "unkown"
    else
        job_state = status.slice(/JobState=[A-Z]*/).split("=")[-1].downcase
        return job_state
    end

end

def find_report(job)

    run_dir = job["run_dir"]

    report = nil

    if File.directory?("#{job['run_dir']}/results/reports")
        htmls = Dir["#{run_dir}/results/reports/*.html"]
        warn htmls.inspect
        if htmls.length > 1
            report = htmls.find{|h| !h.include?("multiqc") && !h.include?("illumina") && !h.include?("nanopore")}
        elsif htmls.length == 1
            report = htmls.shift
        end
    end

    if report
        return File.expand_path(report)
    else
        return nil
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

opts.parse! 

# The ngs-dashboard REST endpoint
$server	= 'localhost:3000/api/v1'

jobs = rest_get("jobs")

jobs.each do |job|

    status = job["status"]

    case status
    when "created"
        # submit the job
        warn "Found new job - submitting"
        job_id = nil
        Dir.chdir(job["run_dir"]) do |dir|
            file = build_slurm_script(job)
            job_id = submit_job(file)
        end
        payload = { job: { id: job["id"], job_id: job_id , status: "submitted"} }
        rest_post("jobs/#{job['id']}/update", payload)
    when "submitted" || "running" || "pending"
        # update job
        warn "Active job #{job['slurm_id']}, updating status..."
        status = get_status(job["job_id"])
        payload = { job: { id: job["id"], status: status} }
        if !job["log"]
            payload["log"] = "#{job['run_dir']}/slurm.err"
        end
        rest_post("jobs/#{job['id']}/update", payload)
    when "failed"
        # resubmit if applicable
        warn "Failed job #{job['slurm_id']}..."
        if job["attempts"] < 3
            warn "\tResubmitting!"
            job_id = nil
            Dir.chdir(job["run_dir"]) do |dir|
                job_id = submit_job("slurm.sh")
            end  
            attempts = job["attempts"].to_i+1
            payload = { job: { id: job["id"], status: "submitted", attempts: attempts, job_id: job_id} }
            rest_post("jobs/#{job['id']}/update", payload)
        end
    when "complete"
        if !job["completed"]
          
            # remove the work directory
            wd = "#{job['run_dir']}/work"
            if File.directory?(wd)
                system("rm -Rf #{wd}")
            end
            payload = { job: { id: job["id"], complete: true } }
            # if no report has been attached to this job, try and do that now
            if !job["report"] && job["command"].include?("nextflow")
                report = find_report(job)
                if report
                    payload[job_id:][report:  report]
                end
            end
            rest_post("jobs/#{job['id']}", payload)

            if job["depends_on"]
                { job: { is_archived: true } }
                rest_post("jobs/#{job['depends_on']}", payload)
            end

        end
        # Stage out
    end

end