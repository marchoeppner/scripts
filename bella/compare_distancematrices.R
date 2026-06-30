#!/usr/bin/env Rscript

# Cluster distance matrix version 0.0.1
# Copyright (C) 2020 onwards Carlus Deneke

# parse input files

# supress warnings
options(warn=-1)

# load libraries
suppressPackageStartupMessages(library(optparse))
suppressPackageStartupMessages(library(reshape2))

options(warn=0)

# option parsing #

parser <- OptionParser()

parser <- add_option(parser, 
                     opt_str = c("-a", "--matrix1"), 
                     type = "character",
                     dest = 'matrix1',
                     help="First distance matrix input file (required). Default format is space-separated and without header."
)

parser <- add_option(parser, 
                     opt_str = c("-b", "--matrix2"), 
                     type = "character",
                     dest = 'matrix2',
                     help="Second distance matrix input file (required). Default format is space-separated and without header."
)


parser <- add_option(parser, 
                     opt_str = c("-o", "--outdir"), 
                     type = "character",
                     dest = 'output.dir',
                     default=NA,
                     help="Output directory (optional, default is current working directory)."
)


parser <- add_option(parser,
                     opt_str = c( "--header"),
                     action = "store_true",
                     dest = 'header',
                     help="TRUE or FALSE (the default). When true, the first line in the distance matrix is the header"
)

parser <- add_option(parser,
                     opt_str = c( "--tsv"),
                     action = "store_true",
                     dest = 'tsv',
                     help="TRUE or FALSE (the default). When true, the distance matrix is tab separated (else space separated)"
)

parser <- add_option(parser, 
                     opt_str = c("-c", "--cutoff"), 
                     type="numeric", 
                     default=20,
                     dest = 'threshold',
                     help="An allele threshold for a closer analysis. Default=20 AD"
)

parser <- add_option(parser,
                     opt_str = c("-f", "--force"),
                     action = "store_true",
                     dest = 'force',
                     help="TRUE or FALSE (the default). When true, existing output files will be overwritten"
)

opt = parse_args(parser)

# define data ------------
# TODO remove
#distance_matrix_1.file <- "/cephfs/abteilung4/deneke/Projects/chewiesnake_validation/cgmlst_all_data/chewiesnake/cgmlst/distance_matrix.tsv"
#distance_matrix_2.file <- "/cephfs/abteilung4/deneke/Projects/chewiesnake_validation/cgmlst_all_data/chewiesnake_v2/cgmlst/distance_matrix.tsv"
#distance_matrix_2.file <- "/cephfs/abteilung4/deneke/Projects/chewiesnake_validation/cgmlst_all_data/chewiesnake_v2/cgmlst/distance_matrix_recompute.tsv"



if (length(opt$matrix1)==1) {
  distance_matrix_1.file = opt$matrix1
} else {
  stop("First distance matrix must be supplied via -a or --matrix1. See script usage (--help)")
}

if (length(opt$matrix2)==1) {
  distance_matrix_2.file = opt$matrix2
} else {
  stop("Second distance matrix must be supplied via -b or --matrix2. See script usage (--help)")
}


if(isTRUE(opt$force)){
  Force <- T
} else {
  Force <- F
}


if(is.numeric(opt$threshold)){
  distance_threshold  <- opt$threshold  
} else {
  distance_threshold  <- 20
  warning("Setting distance_threshold = 20")
}


if(isTRUE(opt$header)){
  header <- T
} else {
  header <- F
}

#, sep = sep, header = header

if(isTRUE(opt$tsv)){
  sep <- "\t"
} else {
  sep <- " "
}


if(!is.na(opt$output.dir)){
  outdir <- opt$output.dir  
}else {
  outdir <- getwd()
}

# check if dir exists
if(!dir.exists(outdir)){
  warning(paste("Directory",outdir,"does not exist"))
  dir.create(outdir)
} 


# define outfiles
distances_comparison.file <- file.path(outdir,"distance_comparison_table_all.tsv")
distances_comparison_closeup_diffsonly.file <- file.path(outdir,"distance_comparison_table_subset_belowthreshold_withmethoddifference.tsv")

if(file.exists(distances_comparison.file) & !isTRUE(Force) ){
  stop("File ",distances_comparison.file," already exists. Use flag --force to overwrite")
}


# functions --------------

create_combo_accesion <- function(twosampleinput){
  
  comboaccession_sorted <- apply(twosampleinput, 1, function(x){
    #print(x)
    x_sorted <- sort(x)  
    if(all(x_sorted == x)){
      #print("Sorted"); return(T)
      return(paste(x[1],x[2],sep="_"))
    } else {
      #print("Unsorted");return(F)
      return(paste(x[2],x[1],sep="_"))
    }
  })
}


#source("/home/DenekeC/Rscripts/functions.R")
# function for reading distance matrix, as provided by grapetree or snp-dist
read_distance_matrix <- function(file, sep = " ", header = FALSE){
  if(!file.exists(file)) {stop(paste("File",file,"does Not exist")); return(NA)}
  distance_matrix <- read.delim(file, sep=sep, stringsAsFactors = F, header = header)
  rownames(distance_matrix) <- sub(".fasta","",distance_matrix[,1])
  distance_matrix <- distance_matrix[,-1]
  colnames(distance_matrix) <- rownames(distance_matrix)
  distance_matrix <- as.matrix(distance_matrix[order(colnames(distance_matrix)),order(colnames(distance_matrix))])
  return(distance_matrix)
}


# check existence
if(!file.exists(distance_matrix_1.file)){
  stop("File ",distance_matrix_1.file," does NOT exist")
}

if(!file.exists(distance_matrix_2.file)){
  stop("File ",distance_matrix_2.file," does NOT exist")
}


# load data
distance_matrix_1 <- read_distance_matrix(distance_matrix_1.file, sep = sep, header = header)
distance_matrix_2 <- read_distance_matrix(distance_matrix_2.file, sep = sep, header = header)

# check size differences
if(nrow(distance_matrix_1) == nrow(distance_matrix_2)){
  print(paste("Both distance matrices have the same size: ",nrow(distance_matrix_1)))
} else {
  print(paste("Distance matrices have different size: matrix1: ",nrow(distance_matrix_1),"; matrix2: ",nrow(distance_matrix_2)))
}


# melt matrices
distance_matrix_1.m <- melt(distance_matrix_1)
colnames(distance_matrix_1.m) <- c("sample1","sample2","distance_1")

# create combo names
distance_matrix_1.m$sample_combo <- create_combo_accesion (distance_matrix_1.m[,1:2])
# remove duplicates
distance_matrix_1.m <- distance_matrix_1.m[!duplicated(distance_matrix_1.m$sample_combo),]
# remove self-hits
distance_matrix_1.m <- distance_matrix_1.m[distance_matrix_1.m$sample1 != distance_matrix_1.m$sample2,]


distance_matrix_2.m <- melt(distance_matrix_2)
colnames(distance_matrix_2.m) <- c("sample1","sample2","distance_2")

# create combo names
distance_matrix_2.m$sample_combo <- create_combo_accesion (distance_matrix_2.m[,1:2])
# remove duplicates
distance_matrix_2.m <- distance_matrix_2.m[!duplicated(distance_matrix_2.m$sample_combo),]
# remove self-hits
distance_matrix_2.m <- distance_matrix_2.m[distance_matrix_2.m$sample1 != distance_matrix_2.m$sample2,]

# merge ---------------------

# merge cgmlst and snp data
distances_comparison <- merge(distance_matrix_1.m,distance_matrix_2.m,by="sample_combo")


# TODO clean colnames(distances_comparison)

# method differences
distances_comparison$methoddifference <- distances_comparison$distance_1 - distances_comparison$distance_2


distances_comparison_closeup <- distances_comparison[distances_comparison$distance_1 < distance_threshold,]


distances_comparison_closeup_diffsonly <- distances_comparison_closeup[distances_comparison_closeup$methoddifference != 0,]


# export

write.table(distances_comparison_closeup_diffsonly[,c(2,3,4,7,8)],distances_comparison_closeup_diffsonly.file,sep="\t",quote = F, row.names = F)
write.table(distances_comparison[,c(2,3,4,7,8)],distances_comparison.file,sep="\t",quote = F, row.names = F)


# reporting -----------------
print(paste("Comparison of",distance_matrix_1.file,"with",nrow(distance_matrix_1),"rows and",distance_matrix_2.file,"with",nrow(distance_matrix_2),"rows"))

cat()
print(paste("Overall",nrow(distances_comparison),"pairwise differences were compared"))
print(paste("Among these,",sum(distances_comparison$methoddifference != 0),"showed an allele difference(",round(mean(distances_comparison$methoddifference != 0)*100,1),"%)"))

print("Table of overall allele differences between methods")
cat()
cat("---------------------")
table(distances_comparison$methoddifference)

# closeup
cat()
cat("---------------------")
print("Method differences for samples below distance threshold",distance_threshold)

print(paste("Below threshold",nrow(distances_comparison_closeup),"pairwise differences were compared"))
print(paste("Among these,",sum(distances_comparison_closeup$methoddifference != 0),"showed an allele difference(",round(mean(distances_comparison_closeup$methoddifference != 0)*100,1),"%)"))


print("The first 10 pairs with method differences below the threshold are")

knitr::kable(head(distances_comparison_closeup_diffsonly[,c(2,3,4,7,8)],10), row.names = F)

cat()
print("Table of allele differences between methods below threshold")
table(distances_comparison_closeup$methoddifference)


cat()
print("Thank you for using compare_distancematrices.R")



