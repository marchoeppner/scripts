#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import argparse
import os
import sys
import logging

parser = argparse.ArgumentParser(description="Script options")
parser.add_argument("--input", help="An input option")
parser.add_argument("--folder", help="The input folder")
parser.add_argument("--output")
args = parser.parse_args()

logger = logging.getLogger(__name__)

def main(input, folder, output):

    logging.basicConfig(filename='rename_alleles.log', level=logging.INFO)
    logger.info('Started')

    lookup = {}

    with open(input, "r") as file:
        for line in file:
            elements = line.strip().split("\t")
            if len(elements) < 2:
                logger.info("Nothing to do")
                sys.exit(0)

            lookup[elements[0]] = elements[1]

    dump_folder = folder + "/old"
    if not os.path.exists(dump_folder):
        logger.info("Creating backup dir for old alleles")
        os.makedirs(dump_folder)

    for old,new in lookup.items():
        old_file = folder + "/" + old + ".fasta"

        if os.path.exists(old_file):
            new_file = folder + "/" + new + ".fasta"

            logger.info(f"Creating new allele file {new_file}")
            command = "cp " + old_file + " " + new_file
            os.system(command)
            command = "mv " + old_file + " " + folder + "/old"
            os.system(command)

    logger.info('Finished')


if __name__ == '__main__':
    main(args.input, args.folder, args.output)
