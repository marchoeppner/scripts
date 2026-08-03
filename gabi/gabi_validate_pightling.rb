require 'json'
require 'optparse'
require 'ostruct'

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

categories = {
    "intra_0.05" => { "label" => "intra_0.05", "filter" => [ "0.05" ], "bucket" => 
        { 
            "Ec" => { "tp" => 0, "fp" => 0, "tn" => 0, "fn" => 0 },
            "Lm" => { "tp" => 0, "fp" => 0, "tn" => 0, "fn" => 0 },
            "Se" => { "tp" => 0, "fp" => 0, "tn" => 0, "fn" => 0 },
            "Ca" => { "tp" => 0, "fp" => 0, "tn" => 0, "fn" => 0 }
        }
    },
    "intra_0.5" => { "label" => "intra_0.5", "filter" => [ "0.5" ], "bucket" => 
        { 
            "Ec" => { "tp" => 0, "fp" => 0, "tn" => 0, "fn" => 0 },
            "Lm" => { "tp" => 0, "fp" => 0, "tn" => 0, "fn" => 0 },
            "Se" => { "tp" => 0, "fp" => 0, "tn" => 0, "fn" => 0 },
            "Ca" => { "tp" => 0, "fp" => 0, "tn" => 0, "fn" => 0 }
        }
    },
    "intra_5" => { "label" => "intra_5", "filter" => [ "5" ], "bucket" =>
        { 
            "Ec" => { "tp" => 0, "fp" => 0, "tn" => 0, "fn" => 0 },
            "Lm" => { "tp" => 0, "fp" => 0, "tn" => 0, "fn" => 0 },
            "Se" => { "tp" => 0, "fp" => 0, "tn" => 0, "fn" => 0 },
            "Ca" => { "tp" => 0, "fp" => 0, "tn" => 0, "fn" => 0 }
        }
    }
}

lines = IO.readlines(options.infile).map {|l| l.strip }

lines.each do |l|
    
    sample,status = l.strip.split("\t")
   
    species,dist,contam,foreign = sample.split("_")

    status == "true" ? observed_contamination = true : observed_contamination = false
    contam == "0" ? known_contamination = false : known_contamination = true

    if dist == "close"
        dist = "0.05"
    elsif dist == "intermediate"
        dist = "0.5"
    elsif dist == "far"
        dist = "5"
    end
    dist.gsub!("-",".")


    categories.each do |label, category|
        if category["filter"].include?(dist)

            key = nil
            if observed_contamination
                # Confindr says this is contaminated
                if known_contamination # and it should be
                    key = "tp"
                else
                    key = "fp"
                end
            else
                # Confindr does not detect contamination
                if known_contamination # but it should be
                    key = "fn"
                else
                    key = "tn"
                end

            end

            categories[label]["bucket"][species][key] += 1

        end
            
    end

end

puts "Species\tDistance\tRecall\tPrecision"

categories.each do |label,category|

    bucket = category["bucket"]
    bucket.each do |s,data|
        tp = data["tp"].to_f
        fp = data["fp"].to_f
        tn = data["tn"].to_f
        fn = data["fn"].to_f

        precision = (tp / (tp+fp)).round(2)
        recall = (tp / (tp+fn)).round(2)

        puts "#{s}\t#{label}\t#{recall}\t#{precision}"
    end
end