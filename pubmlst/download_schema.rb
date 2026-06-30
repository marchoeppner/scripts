#!/usr/bin/env ruby
# == NAME
# script.rb
#
# == AUTHOR
#  Marc Hoeppner, mphoeppner@gmail.com

require 'optparse'
require 'ostruct'
require 'rest_client'
require 'json'
require 'fileutils'
require 'progressbar'

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

$server = "https://rest.pubmlst.org"

### Get the script arguments and open relevant files
options = OpenStruct.new()
opts = OptionParser.new()
opts.on("-s","--s", "=SPECIES","Query species") {|argument| options.species = argument }
opts.on("-o","--outfile", "=OUTFILE","Output file") {|argument| options.outfile = argument }
opts.on("-h","--help","Display the usage information") {
    puts opts
    exit
}

opts.parse! 

species = rest_get("db")

species.each do |s|
  
    name = s["name"]

    if name.include?("campylobacter")
      
        dbs = s["databases"]
        
        schema_dbs = dbs.select{ |d| d["name"].include?("seqdef")}
       
        schema_dbs.each do |db|

            # uses: https://rest.pubmlst.org/db/pubmlst_campylobacter_seqdef
            url = db["href"].split(".org/")[-1]
            name = db["name"]

            # Get schemas for this db entry (two calls in one)
            schemas = rest_get(url + "/schemes")["schemes"]
             
            # Only consider cgMLST schemas
            cgmlst_schemes = schemas.select {|s| s["description"].include?("cgMLST")}

            # If we have more than one cgMLST schema, add a counter to their name
            counter = 0
            cgmlst_schemes.each do |cgmlst_scheme|
                counter += 1

                scheme_url = cgmlst_scheme["scheme"].split(".org/")[-1]
                this_scheme = rest_get(scheme_url)
                
                locus_list = this_scheme["loci"]

                schema_dir = "#{name}_#{counter}"

                FileUtils.mkdir_p(schema_dir)

                Dir.chdir(schema_dir) do |dir|

                    pg = ProgressBar.create(:title => "cgMLST Loci - #{schema_dir}", :total => locus_list.length)
                    locus_list.each do |locus|
                        pg.increment
                        url = locus.split(".org/")[-1]
                        locus_entry = rest_get(url)
                        if locus_entry
                            locus_name = locus_entry["id"]
                            if !File.exist?("#{locus_name}.fasta")    
                                url = locus_entry["alleles_fasta"]
                                command = "wget --quiet -O #{locus_name}.fasta #{url}"
                                system(command)
                            end
                        end
                    end
                    pg.finish
                end

            end
        end
    end
    
end

