#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import argparse

parser = argparse.ArgumentParser(description="Script options")
parser.add_argument("--input", help="An input option")
parser.add_argument("--output")
args = parser.parse_args()


def main(input, output):
    # something here


if __name__ == '__main__':
    main(args.input, args.output)
