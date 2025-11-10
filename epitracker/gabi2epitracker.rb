#!/usr/bin/env ruby
# == NAME
# script.rb
#
# == AUTHOR
#  Marc Hoeppner, mphoeppner@gmail.com

require 'optparse'
require 'ostruct'
require 'epitracker'
require "zlib"
require 'base64'
require 'digest'

def validate_gabi_folder(folder)

    valid = true

    if !Dir.exist?(folder)
        return false
    end

    if !File.exist?("#{folder}/samples")
        return false
    end

    if Dir["#{folder}/samples/*/*qc.json"].empty?
        return false
    end

    if Dir["#{folder}/samples/*/assembly/*.fasta"].empty?
        return false
    end

    return valid

end

### Get the script arguments and open relevant files
options = OpenStruct.new()
opts = OptionParser.new()
opts.on("-i","--input", "=INPUT","Path to GABI results folder") {|argument| options.input = argument }
opts.on("-d","--db", "=DB","Path to db file") {|argument| options.db = argument }
opts.on("-o","--outfile", "=OUTFILE","Output file") {|argument| options.outfile = argument }
opts.on("-h","--help","Display the usage information") {
    puts opts
    exit
}
opts.parse! 

options.db ? db_file = options.db : db_file = "/home/mhoeppner/git/epitracker/storage/development.sqlite3"

Epitracker::DBConnection.connect({database: db_file})

@cache = []

is_valid = validate_gabi_folder(options.input)

if !is_valid
    warn "Not a valid GABI result folder!"
    exit
end

jsons = Dir["#{options.input}/samples/*/*.qc.json"].map {|j| JSON.parse(IO.readlines(j).join)}
assemblies = Dir["#{options.input}/samples/*/assembly/*.fasta"].select{|f| !f.include?("chromosome")}

failed = []
jsons.each do |json|
    
    if json["qc"]["status"] == "fail"
        failed << j["sample"]
    end
end
if !failed.empty?

    proceed = false

    while proceed == false

        warn "We have #{failed.length} samples - proceed by skipping these (y/n)?"
        answer = gets.chomp

        if answer == "y"
            proceed = true
        elsif answer == "n"
            exit
        end

    end
end
jsons.each do |json|

    next if json["qc"]["status"] == "failed"

    genus,species = json["taxon"].split(" ")

    if genus.nil? || species.nil?
        warn "Species name not following genus/species convention (was: #{genus} #{species})"
        exit
    end

    sample = json["sample"]
    version = json["software"]["Workflow"]["bio-raum/gabi"]

    o = Epitracker::Organism.where(genus: genus, species: species).first

    if !o
        warn "Taxon #{genus} #{species} not found in database!"
        exit
    end

    assembly = assemblies.find {|a| a.include?(sample)}

    if !assembly
        warn "No assembly found for sample #{sample}"
        exit
    end

    s = Epitracker::Sample.find_by_name(sample)

    if s
        warn "Sample #{sample} already in the database, skiping!"
    else
        payload = {
            "organism_id" => o.id,
            "name" => sample
        }
        s = Epitracker::Sample.create(payload)

        fasta = IO.readlines(assembly).join("\n")
        compressed_fasta = Zlib::Deflate.deflate(fasta)
        encoded_fasta = Base64.encode64(compressed_fasta)
        md5 = Digest::MD5.hexdigest(fasta)

        payload = {
            "sample_id" => s.id,
            "fasta" => encoded_fasta,
            "fasta_md5" => md5,
            "pipeline" => "GABI",
            "pipeline_version" => version
        }

        a = Epitracker::Assembly.create(payload)

        serotype = nil
        n50 = nil
        n_scaffolds= nil
        qc = nil
        mlst_type = nil
        mlst_schema = nil
        pathotype = nil
        busco = nil

        if json["serotype"] && json["serotype"].length > 0
            serodata = json["serotype"]
            serodata.each do |tool,sd|
                if sd["Pathotype"]
                    pathotype = sd["Pathotype"]
                end
                if sd["Serotype"]
                    serotype = sd["Serotype"]
                elsif sd["SEROTYPE"]
                    serotype = sd["SEROTYPE"]
                end
            end
        end

        if json["mlst"] && json["mlst"].length > 0
            mdata = json["mlst"].first
            mlst_schema = mdata["scheme"]
            mlst_type = mdata["sequence_type"]
        end

        qc = json["qc"]["call"]

        n50 = json["quast"]["N50"]
        n_scaffolds = json["quast"]["# contigs"]
        assembly_size = json["quast"]["Total length"]

        busco = json["busco"]["one_line_summary"]

        payload = {
            "assembly_id" => a.id,
            "serotype" => serotype,
            "n50" => n50,
            "n_scaffolds" => n_scaffolds,
            "qc" => qc,
            "mlst_type" => mlst_type,
            "mlst_schema" => mlst_schema,
            "pathotype" => pathotype,
            "busco" => busco,
            "assembly_size" => assembly_size
        }

        i = Epitracker::AssemblyInfo.create(payload)

            
    end

end
