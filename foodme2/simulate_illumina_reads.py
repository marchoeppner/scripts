#!/usr/bin/env python3
"""
Simulate demultiplexed Illumina paired-end (R1/R2) metabarcoding amplicon reads
with a realistic position-dependent substitution error profile and R2 quality decay.
"""

import argparse
import csv
import math
import random
import sys
from pathlib import Path

# Illumina Sequencing-by-Synthesis Error Profile (MiSeq / NextSeq / NovaSeq)
ILLUMINA_PROFILE = {
    "r1_base_err": 0.0008,      # ~0.08% error at 5' start (~Q31)
    "r1_end_err": 0.0150,       # ~1.5% error at 3' end (~Q18)
    "r2_base_err": 0.0012,      # R2 starts slightly noisier (~Q29)
    "r2_end_err": 0.0300,       # R2 decays steeper at 3' end (~Q15)
    "decay_exponent": 2.4,      # Exponential quality drop-off along read cycle
    "indel_fraction": 0.01,     # ~1% of total errors are indels; ~99% are substitutions
    "chimera_rate": 0.01,       # 1% PCR chimera rate
}

# Illumina-typical substitution bias (A<->C and G<->T transversions are slightly elevated)
SUB_MATRIX = {
    "A": [("C", 0.40), ("G", 0.35), ("T", 0.25)],
    "C": [("A", 0.40), ("T", 0.35), ("G", 0.25)],
    "G": [("T", 0.40), ("A", 0.35), ("C", 0.25)],
    "T": [("G", 0.40), ("C", 0.35), ("A", 0.25)],
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


def phred_char(q_score: float) -> str:
    q_clamped = max(2, min(40, int(round(q_score))))
    return chr(q_clamped + 33)


def weighted_choice(choices: list[tuple[str, float]]) -> str:
    r = random.random()
    upto = 0.0
    for base, weight in choices:
        upto += weight
        if r <= upto:
            return base
    return choices[-1][0]


def simulate_illumina_single(
    amplicon: str, max_read_len: int, is_r2: bool, profile: dict
) -> tuple[str, str]:
    """
    Simulate a single R1 or R2 read up to max_read_len with 3' exponential error decay.
    If the amplicon is shorter than max_read_len, sequencing stops at the amplicon end.
    """
    template = amplicon[:max_read_len]
    effective_len = len(template)

    base_err = profile["r2_base_err"] if is_r2 else profile["r1_base_err"]
    end_err = profile["r2_end_err"] if is_r2 else profile["r1_end_err"]
    exp = profile["decay_exponent"]
    indel_frac = profile["indel_fraction"]

    # Slight cluster-to-cluster signal intensity variance
    cluster_mult = random.gammavariate(9.0, 1.0 / 9.0)

    out_bases = []
    out_quals = []
    idx = 0

    while idx < effective_len:
        base = template[idx]
        if base not in "ACGT":
            base = random.choice("ACGT")

        # Scale error curve against the nominal sequencing run length
        rel_pos = idx / max(1, max_read_len - 1)
        p_err = (base_err + (end_err - base_err) * (rel_pos ** exp)) * cluster_mult
        p_err = max(1e-5, min(0.45, p_err))

        expected_q = -10.0 * math.log10(p_err)
        roll = random.random()

        if roll < p_err:
            # Rare indel vs dominant substitution
            if random.random() < indel_frac and idx < effective_len - 1:
                if random.random() < 0.5:
                    # 1 bp deletion
                    idx += 1
                    continue
                else:
                    # 1 bp insertion
                    out_bases.append(random.choice("ACGT"))
                    out_quals.append(phred_char(random.gauss(expected_q - 6.0, 2.5)))
                    if len(out_bases) >= max_read_len:
                        break
            # Substitution
            mut_base = weighted_choice(SUB_MATRIX[base])
            out_bases.append(mut_base)
            q = random.gauss(expected_q - 8.0, 3.0)
            out_quals.append(phred_char(q))
        else:
            out_bases.append(base)
            q = random.gauss(expected_q, 2.0)
            out_quals.append(phred_char(q))

        idx += 1

    return "".join(out_bases), "".join(out_quals)


def main():
    parser = argparse.ArgumentParser(
        description="Simulate demultiplexed Illumina paired-end metabarcoding reads from a multi-FASTA."
    )
    parser.add_argument("-i", "--input", required=True, type=Path, help="Input multi-FASTA file")
    parser.add_argument("-o", "--out-prefix", required=True, type=str, help="Output prefix (creates _R1.fastq and _R2.fastq)")
    parser.add_argument("-n", "--num-pairs", type=int, default=10000, help="Number of read pairs to simulate (default: 10000)")
    parser.add_argument("-l", "--read-length", type=int, default=250, help="Maximum read length in bp for R1 and R2 (default: 250)")
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
        help="Optional 2-column TSV/CSV file mapping FASTA header IDs to abundances or read counts",
    )
    parser.add_argument(
        "--mixed-orientation",
        action="store_true",
        help="Simulate 50/50 forward/reverse amplicon orientation (typical for ligation-based Illumina library prep)",
    )
    parser.add_argument("--chimera-rate", type=float, default=0.01, help="PCR chimera rate (default: 0.01)")
    parser.add_argument("--seed", type=int, default=42, help="Random seed (default: 42)")
    args = parser.parse_args()

    random.seed(args.seed)
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

    r1_path = Path(f"{args.out_prefix}_R1.fastq")
    r2_path = Path(f"{args.out_prefix}_R2.fastq")

    with open(r1_path, "w", encoding="utf-8") as fq1, open(r2_path, "w", encoding="utf-8") as fq2:
        for pair_idx in range(1, args.num_pairs + 1):
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

            strand = "+"
            if args.mixed_orientation and random.random() < 0.5:
                amplicon_seq = rev_comp(amplicon_seq)
                strand = "-"

            r1_seq, r1_qual = simulate_illumina_single(
                amplicon_seq, args.read_length, is_r2=False, profile=ILLUMINA_PROFILE
            )
            r2_seq, r2_qual = simulate_illumina_single(
                rev_comp(amplicon_seq), args.read_length, is_r2=True, profile=ILLUMINA_PROFILE
            )

            base_header = f"@sim_illumina_2x{args.read_length}_{pair_idx:06d} source={source_label} strand={strand}"
            fq1.write(f"{base_header} 1:N:0:1\n{r1_seq}\n+\n{r1_qual}\n")
            fq2.write(f"{base_header} 2:N:0:1\n{r2_seq}\n+\n{r2_qual}\n")

    print(
        f"Done. Simulated {args.num_pairs} paired-end 2x{args.read_length} bp reads "
        f"from {len(targets)} targets -> {r1_path} & {r2_path}"
    )


if __name__ == "__main__":
    main()
