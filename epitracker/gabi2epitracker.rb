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

options.db ? db_file = options.db : db_file = "/home/marc/git/epitracker/storage/development.sqlite3"

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

        warn "We have #{failed.length} samples - proceed (y/n)?"
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

end
