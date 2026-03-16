#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import argparse
import csv
import json

parser = argparse.ArgumentParser(description="Script options")
parser.add_argument("--input", help="A BarBeQue consensus file in tab format")
parser.add_argument("--sample", help="Sample name")
parser.add_argument("--output")
args = parser.parse_args()


def main(input, sample, output):

    data = {"sample": sample}
    histo = {}

    with open(input) as tsv:
        tsvreader = csv.DictReader(tsv, delimiter="\t")

        for entry in tsvreader:
            amlen = len(entry["amplicon"])

            if amlen in histo:
                histo[amlen] += 1
            else:
                histo[amlen] = 1

    data["histogram"] = histo

    with open(output, "w") as fout:
        json.dump(data, fout, indent=4, sort_keys=True)


if __name__ == '__main__':

    main(args.input, args.sample, args.output)
