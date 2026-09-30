#!/usr/bin/env ruby
# == NAME
# script.rb
#
# == AUTHOR
#  Marc Hoeppner, mphoeppner@gmail.com

require 'optparse'
require 'ostruct'
require 'json'

### Get the script arguments and open relevant files
options = OpenStruct.new()
opts = OptionParser.new()
opts.on("-i","--infile", "=INFILE","Input file") {|argument| options.infile = argument }
opts.on("-o","--outfile", "=OUTFILE","Output file") {|argument| options.outfile = argument }
opts.on("-h","--help","Display the usage information") {
    puts opts
    exit
}

opts.parse! 

data = JSON.load_file(options.infile)

puts data["sample"]

efsa_experiment = {
    "localRawReadId" =>  null,
    "instrumentModelCode" =>  null,
    "isolateSpecieCode" =>  null,
    "libraryLayoutCode" =>  2,
    "fastQ1FileName" =>  null,
    "fastQ1Md5" =>  null,
    "fastQ2FileName" =>  null,
    "fastQ2Md5" =>  null
}

efsa_typing = {
    "localRawReadId" =>  null,
    "AnalyticalPipelineInfoTag" => "bio-raum/gabi",
    "QualityCheck" =>  {
        "Fastp" =>  {
            "ReadMeanLength" =>  null,
            "Q30Rate" =>  null,
            "TotalBases" =>  null
        },
        "AssemblyQualityStatistics" =>  {
            "AssemblyCoverage" =>  null,
            "AssemblyStatistics" =>  {
                "N50Contigs" =>  null,
                "GenomeSize" =>  null,
                "NumberOfContigs" =>  null
            }
        }
    }
    
}

typing_ecoli = {
    "Results" =>  {
        "ParamCode" =>  {
            "PredictedPathotype" =>  {
                "Pathotype" =>  "NA",
                "VeroToxin" =>  {
                    "VT1Positive" =>  null,
                    "VT2Positive" =>  null
                },
                "AdhesionGenes" =>  {
                    "eaePositive" =>  null,
                    "aatPositive" =>  null,
                    "aggRPositive" =>  null,
                    "aaiCPositive" =>  null
                },
                "Software" =>  null,
                "GeneList" =>  [
                    {
                        "GeneName" =>  null,
                        "Identity" =>  null,
                        "Coverage" => null
                    }
                ]
            },
            "PredictedSerotype" =>  {
                "Serotype" =>  null,
                "Software" =>  null
            },
            "PredictedStxType" =>  null,
            "MLSTSequenceType" =>  {
                "ST" =>  null,
                "Software" =>  "mlst",
                "GeneList" =>  [
                    {
                        
                    }
                ]
            }
        }
    }
}
