#!/usr/bin/env python3
"""
Simulate Oxford Nanopore R10.4.3 metabarcoding amplicon reads with selectable
Dorado basecalling models (FAST, HAC, SUP) and custom abundance tables.
Assumes target FASTA sequences already represent full-length amplicons.
"""

import argparse
import csv
import math
import random
import sys
from pathlib import Path

# R10.4.3 + Dorado Basecalling Model Profiles
MODEL_PROFILES = {
    "fast": {
        "sub_rate": 0.0110,        # ~96.5% modal accuracy (~Q14-Q15)
        "ins_rate": 0.0100,
        "del_rate": 0.0130,
        "hp_threshold": 3,
        "hp_indel_scale": 0.025,
        "end_degradation_bp": 20,
        "q_offset": -3.5,
    },
    "hac": {
        "sub_rate": 0.0035,        # ~98.8% modal accuracy (~Q19)
        "ins_rate": 0.0030,
        "del_rate": 0.0040,
        "hp_threshold": 4,
        "hp_indel_scale": 0.015,
        "end_degradation_bp": 15,
        "q_offset": 0.0,
    },
    "sup": {
        "sub_rate": 0.0012,        # ~99.5% modal accuracy (~Q23+)
        "ins_rate": 0.0012,
        "del_rate": 0.0018,
        "hp_threshold": 5,
        "hp_indel_scale": 0.008,
        "end_degradation_bp": 12,
        "q_offset": 3.0,
    },
}

SUB_MATRIX = {
    "A": [("G", 0.50), ("C", 0.25), ("T", 0.25)],
    "G": [("A", 0.50), ("C", 0.25), ("T", 0.25)],
    "C": [("T", 0.50), ("A", 0.25), ("G", 0.25)],
    "T": [("C", 0.50), ("A", 0.25), ("G", 0.25)],
}

COMPLEMENT = str.maketrans("ACGTacgtNn", "TGCAtgcaNn")


def rev_comp(seq: str) -> str:
    return seq.translate(COMPLEMENT)[::-1]


def parse_fasta(filepath: Path) -> list[tuple[str, str]]:
    records = []
    header = None
    seq_chunks = []
    with open(filepath, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            if line.startswith(">"):
                if header is not None:
                    records.append((header, "".join(seq_chunks).upper()))
                header = line[1:].split()[0]
                seq_chunks = []
            else:
                seq_chunks.append(line)
        if header is not None:
            records.append((header, "".join(seq_chunks).upper()))
    return records


def load_abundance_table(filepath: Path, targets: list[tuple[str, str]]) -> list[float]:
    """Read a 2-column TSV/CSV (target_id, weight) and align to FASTA records."""
    weight_map = {}
    with open(filepath, "r", encoding="utf-8") as f:
        sample = f.read(1024)
        f.seek(0)
        dialect = csv.Sniffer().sniff(sample, delimiters="\t,")
        reader = csv.reader(f, dialect)
        for row in reader:
            if not row or row[0].startswith("#"):
                continue
            target_id = row[0].strip()
            try:
                val = float(row[1].strip())
                if val < 0:
                    raise ValueError
                weight_map[target_id] = val
            except (IndexError, ValueError):
                # Skip header rows like "taxon\tabundance"
                continue

    weights = []
    missing = []
    for header, _ in targets:
        if header in weight_map:
            weights.append(weight_map[header])
        else:
            weights.append(0.0)
            missing.append(header)

    if sum(weights) <= 0:
        sys.exit("Error: No positive abundance weights matched FASTA headers.")
    if missing:
        print(
            f"Warning: {len(missing)} FASTA targets missing from abundance table (assigned weight 0).",
            file=sys.stderr,
        )
    return weights


def get_homopolymer_lengths(seq: str) -> list[int]:
    n = len(seq)
    hp_lens = [1] * n
    i = 0
    while i < n:
        j = i + 1
        while j < n and seq[j] == seq[i]:
            j += 1
        run_len = j - i
        for k in range(i, j):
            hp_lens[k] = run_len
        i = j
    return hp_lens


def phred_char(q_score: int) -> str:
    q_clamped = max(2, min(42, int(round(q_score))))
    return chr(q_clamped + 33)


def weighted_choice(choices: list[tuple[str, float]]) -> str:
    r = random.random()
    upto = 0.0
    for base, weight in choices:
        upto += weight
        if r <= upto:
            return base
    return choices[-1][0]


def simulate_read(seq: str, profile: dict) -> tuple[str, str]:
    read_error_mult = random.gammavariate(4.0, 0.25)
    hp_lens = get_homopolymer_lengths(seq)
    out_bases = []
    out_quals = []
    seq_len = len(seq)
    q_offset = profile["q_offset"]

    for idx, base in enumerate(seq):
        if base not in "ACGT":
            base = random.choice("ACGT")

        dist_from_end = min(idx, seq_len - 1 - idx)
        end_mult = 1.8 if dist_from_end < profile["end_degradation_bp"] else 1.0

        hp_len = hp_lens[idx]
        hp_penalty = 0.0
        if hp_len >= profile["hp_threshold"]:
            hp_penalty = (hp_len - profile["hp_threshold"] + 1) * profile["hp_indel_scale"]

        p_sub = profile["sub_rate"] * read_error_mult * end_mult
        p_del = (profile["del_rate"] + hp_penalty * 0.6) * read_error_mult * end_mult
        p_ins = (profile["ins_rate"] + hp_penalty * 0.4) * read_error_mult * end_mult

        roll = random.random()

        if roll < p_del:
            continue

        elif roll < p_del + p_sub:
            mut_base = weighted_choice(SUB_MATRIX[base])
            out_bases.append(mut_base)
            q = random.gauss(11.0 + q_offset, 3.0)
            out_quals.append(phred_char(q))

        else:
            out_bases.append(base)
            local_err = max(1e-4, min(0.5, p_sub + p_del + p_ins))
            expected_q = -10.0 * math.log10(local_err)
            q = random.gauss(expected_q, 3.5)
            out_quals.append(phred_char(q))

            if roll < p_del + p_sub + p_ins:
                ins_base = base if hp_len >= 3 else random.choice("ACGT")
                out_bases.append(ins_base)
                out_quals.append(phred_char(random.gauss(12.0 + q_offset, 3.0)))

    return "".join(out_bases), "".join(out_quals)


def main():
    parser = argparse.ArgumentParser(
        description="Simulate ONT R10.4.3 metabarcoding reads with model selection and custom abundance tables."
    )
    parser.add_argument("-i", "--input", required=True, type=Path, help="Input multi-FASTA file")
    parser.add_argument("-o", "--output", required=True, type=Path, help="Output FASTQ file")
    parser.add_argument("-n", "--num-reads", type=int, default=1000, help="Total reads to simulate (default: 1000)")
    parser.add_argument(
        "-m",
        "--model",
        choices=["fast", "hac", "sup"],
        default="hac",
        help="R10.4.3 Dorado basecalling model: fast (~Q15), hac (~Q19), sup (~Q23+) (default: hac)",
    )
    parser.add_argument(
        "--abundance",
        choices=["uniform", "lognormal"],
        default="lognormal",
        help="Built-in abundance distribution if --abundance-table is not provided (default: lognormal)",
    )
    parser.add_argument(
        "-a",
        "--abundance-table",
        type=Path,
        default=None,
        help="Optional 2-column TSV/CSV file mapping FASTA header IDs to relative abundances or read counts",
    )
    parser.add_argument("--chimera-rate", type=float, default=0.01, help="PCR chimera rate (default: 0.01)")
    parser.add_argument("--seed", type=int, default=42, help="Random seed (default: 42)")
    args = parser.parse_args()

    random.seed(args.seed)
    profile = MODEL_PROFILES[args.model]
    targets = parse_fasta(args.input)
    if not targets:
        sys.exit("Error: No valid FASTA records found.")

    if args.abundance_table:
        weights = load_abundance_table(args.abundance_table, targets)
    elif args.abundance == "uniform":
        weights = [1.0] * len(targets)
    else:
        weights = [random.lognormvariate(0, 1.2) for _ in targets]

    total_w = sum(weights)
    probs = [w / total_w for w in weights]

    cum_probs = []
    acc = 0.0
    for p in probs:
        acc += p
        cum_probs.append(acc)

    def pick_target():
        r = random.random()
        for idx, cp in enumerate(cum_probs):
            if r <= cp:
                return targets[idx]
        return targets[-1]

    with open(args.output, "w", encoding="utf-8") as out_fq:
        for read_idx in range(1, args.num_reads + 1):
            if len(targets) > 1 and random.random() < args.chimera_rate:
                h1, s1 = pick_target()
                h2, s2 = pick_target()
                bp1 = random.randint(len(s1) // 4, 3 * len(s1) // 4)
                bp2 = random.randint(len(s2) // 4, 3 * len(s2) // 4)
                amplicon_seq = s1[:bp1] + s2[bp2:]
                source_label = f"chimera_{h1}_x_{h2}"
            else:
                header, amplicon_seq = pick_target()
                source_label = header

            # 50/50 forward vs. reverse strand sequencing
            strand = "+"
            if random.random() < 0.5:
                amplicon_seq = rev_comp(amplicon_seq)
                strand = "-"

            sim_seq, sim_qual = simulate_read(amplicon_seq, profile)
            read_id = f"@sim_r1043_{args.model}_{read_idx:06d} source={source_label} strand={strand}"
            out_fq.write(f"{read_id}\n{sim_seq}\n+\n{sim_qual}\n")

    print(
        f"Done. Simulated {args.num_reads} R10.4.3 ({args.model.upper()}) reads "
        f"from {len(targets)} targets -> {args.output}"
    )


if __name__ == "__main__":
    main()
