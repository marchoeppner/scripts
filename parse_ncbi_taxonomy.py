#!/usr/bin/env python3
# -*- coding: utf-8 -*-


import argparse
import taxidTools
import requests, sys

parser = argparse.ArgumentParser(description="Script options")
parser.add_argument("--input", help="A NCBI taxonomy ID")
parser.add_argument("--output")
args = parser.parse_args()


def main(input, output):
    tax = taxidTools.read_taxdump('nodes.dmp', 'rankedlineage.dmp', 'merged.dmp')

    ancestor = tax.getChildren(input)

    for node in ancestor:

        parse_node(node)
        

def parse_node(node):

    if node.rank == "species":
        translation = node.name
        print(f"{node.name}\t{translation}\t{node.node_info}")
    else:
        children = node.children
        for child in children:
            parse_node(child)

def rest_call(name):
    server = "http://localhost:5000"
    ext = "/translate"

    payload = {"q": name, "source": "en", "target": "de"}
    r = requests.get(server+ext, data=payload, headers={ "Content-Type" : "application/json"})

    if not r.ok:
        r.raise_for_status()
        sys.exit()
    
    decoded = r.json()
    answer = decoded["translatedText"]

if __name__ == '__main__':
    main(args.input, args.output)
