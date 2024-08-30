#!/usr/bin/env python3
# -*- coding: utf-8 -*-


import argparse
from ete3 import NCBITaxa
import requests, sys


parser = argparse.ArgumentParser(description="Script options")
parser.add_argument("--input", help="NCBI tax id")
parser.add_argument("--output")
args = parser.parse_args()


def main(input, output):
    
    ncbi = NCBITaxa()

    taxonomy = ncbi.get_descendant_taxa(input,collapse_subspecies=True, return_tree=True)

    for taxon in taxonomy:
        if taxon.common_name:
            translation = rest_call(taxon.common_name)
            print(f"{taxon.sci_name}\t{taxon.common_name}\t{translation}")
        
def rest_call(name):
    server = "http://127.0.0.1:5000/translate"
    
    payload = {"q": name, "source": "en", "target": "de", "format": "text", "alternatives": 3}

    r = requests.post(server, json=payload, headers={ "Content-Type" : "application/json"})

    if not r.ok:
        r.raise_for_status()
        sys.exit()
    
    decoded = r.json()
    answer = decoded["translatedText"].title()
    if "alternatives" in decoded:

        # LibreTranslate tends to return the german plural, so we check if we also have a singular form (which often is fully contained within the plural)
        # schafe -> schaf, pferde -> pferd
        alts = decoded["alternatives"]
        for alt in alts:
            if alt.title() in answer:
                answer = alt

    return answer.title()


if __name__ == '__main__':
    main(args.input, args.output)
