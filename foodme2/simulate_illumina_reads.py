#!/usr/bin/env python3
"""
Simulate demultiplexed Illumina paired-end (R1/R2) metabarcoding amplicon reads
with cycle-dependent error modeling for XLEAP-SBS and Legacy SBS chemistries.
"""

import argparse
import bisect
import csv
import math
import random
import sys
from pathlib import Path

# Cycle-driven Chemistry Error Profiles
PROFILES = {
    # Modern XLEAP-SBS (NovaSeq X / NextSeq 1000/2000): Flat through 300+ cycles
    "xleap": {
        "r1_base_err": 0.0002,       # ~Q37 baseline
        "r2_base_err": 0.0003,       # ~Q35 baseline
        "per_cycle_drift": 1.0e-6,   # Minimal linear drift per cycle
        "decay_onset_cycle": 280,    # Almost no tail spike within standard 2x150 or 2x300
        "tail_ramp_rate": 1.5e-5,    # Gentle rise only beyond onset
        "decay_exponent": 1.8,
        "indel_fraction": 0.005,     # ~0.5% of errors are indels
        "max_q": 42,                 # XLEAP frequently reports Q40+ scores
    },
    # Legacy SBS (MiSeq v3 / older NextSeq): Low up to ~220 bp, steep decay >250 bp
    "legacy": {
        "r1_base_err": 0.0008,       # ~Q31 baseline
        "r2_base_err": 0.0012,       # ~Q29 baseline
        "per_cycle_drift": 6.0e-6,   # Gradual phasing drift in early/mid cycles
        "decay_onset_cycle": 220,    # Steep degradation kicks in approaching >250 bp
        "tail_ramp_rate": 3.5e-4,    # Heavy tail penalty past onset
        "decay_exponent": 2.2,
        "indel_fraction": 0.01,      # ~1% of errors are indels
        "max_q": 40,
    },
}

# Illumina-typical substitution bias (A<->C and G<->T transversions slightly elevated)
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


def phred_char(q_score: float, max_q: int = 40) -> str:
    q_clamped = max(2, min(max_q, int(round(q_score))))
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
    Simulate a single R1 or R2 read where error rate is driven by absolute cycle index
    rather than normalized read length, keeping <=250 bp reads accurate while penalizing >250 bp tails.
    """
    template = amplicon[:max_read_len]
    effective_len = len(template)

    base_err = profile["r2_base_err"] if is_r2 else profile["r1_base_err"]
    r2_mult = 1.6 if is_r2 else 1.0
    drift = profile["per_cycle_drift"] * r2_mult
    onset = profile["decay_onset_cycle"]
    ramp = profile["tail_ramp_rate"] * r2_mult
    exp = profile["decay_exponent"]
    indel_frac = profile["indel_fraction"]
    max_q = profile.get("max_q", 40)

    # Tighter cluster-to-cluster signal variance for patterned flow cells (XLEAP)
    gamma_shape = 16.0 if max_q > 40 else 9.0
    cluster_mult = random.gammavariate(gamma_shape, 1.0 / gamma_shape)

    out_bases = []
    out_quals = []
    idx = 0

    while idx < effective_len:
        base = template[idx]
        if base not in "ACGT":
            base = random.choice("ACGT")

        # 1. Gentle baseline drift by absolute cycle number
        p_err = base_err + (idx * drift)

        # 2. Tail decay only triggers once cycle exceeds the chemistry's onset threshold
        if idx > onset:
            excess_cycles = (idx - onset) / 50.0  # scaled per 50 bp past onset
            p_err += ramp * (excess_cycles ** exp)

        p_err = max(1e-5, min(0.45, p_err * cluster_mult))

        expected_q = -10.0 * math.log10(p_err)
        roll = random.random()

        if roll < p_err:
            if random.random() < indel_frac and idx < effective_len - 1:
                if random.random() < 0.5:
                    # 1 bp deletion
                    idx += 1
                    continue
                else:
                    # 1 bp insertion
                    out_bases.append(random.choice("ACGT"))
                    out_quals.append(phred_char(random.gauss(expected_q - 6.0, 2.5), max_q))
                    if len(out_bases) >= max_read_len:
                        break
            # Substitution
            mut_base = weighted_choice(SUB_MATRIX[base])
            out_bases.append(mut_base)
            q = random.gauss(expected_q - 8.0, 3.0)
            out_quals.append(phred_char(q, max_q))
        else:
            out_bases.append(base)
            q = random.gauss(expected_q, 1.5 if max_q > 40 else 2.0)
            out_quals.append(phred_char(q, max_q))

        idx += 1

    return "".join(out_bases), "".join(out_quals)


def make_chimera(seq1: str, seq2: str) -> str:
    min_len = min(len(seq1), len(seq2))
    if min_len < 20:
        return seq1
    breakpoint = random.randint(int(min_len * 0.2), int(min_len * 0.8))
    return seq1[:breakpoint] + seq2[breakpoint:]


def main():
    parser = argparse.ArgumentParser(
        description="Simulate demultiplexed Illumina paired-end metabarcoding reads from a multi-FASTA."
    )
    parser.add_argument("-i", "--input", required=True, type=Path, help="Input multi-FASTA file")
    parser.add_argument("-o", "--out-prefix", required=True, type=str, help="Output prefix (creates _R1.fastq and _R2.fastq)")
    parser.add_argument("-n", "--num-pairs", type=int, default=10000, help="Number of read pairs to simulate (default: 10000)")
    parser.add_argument("-l", "--read-length", type=int, default=250, help="Maximum read length in bp for R1 and R2 (default: 250)")
    parser.add_argument(
        "--chemistry",
        choices=["xleap", "legacy"],
        default="xleap",
        help="Illumina sequencing chemistry error profile (default: xleap)",
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
    profile = PROFILES[args.chemistry]
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

    def pick_target() -> tuple[str, str]:
        idx = bisect.bisect_left(cum_probs, random.random())
        return targets[min(idx, len(targets) - 1)]

    r1_path = Path(f"{args.out_prefix}_R1.fastq")
    r2_path = Path(f"{args.out_prefix}_R2.fastq")

    with open(r1_path, "w", encoding="utf-8") as f_r1, open(r2_path, "w", encoding="utf-8") as f_r2:
        for i in range(1, args.num_pairs + 1):
            header, seq = pick_target()

            if len(targets) > 1 and random.random() < args.chimera_rate:
                header2, seq2 = pick_target()
                if header2 != header:
                    seq = make_chimera(seq, seq2)
                    header = f"{header}_chimera_{header2}"

            if args.mixed_orientation and random.random() < 0.5:
                fwd_template = rev_comp(seq)
                rev_template = seq
            else:
                fwd_template = seq
                rev_template = rev_comp(seq)

            r1_seq, r1_qual = simulate_illumina_single(fwd_template, args.read_length, is_r2=False, profile=profile)
            r2_seq, r2_qual = simulate_illumina_single(rev_template, args.read_length, is_r2=True, profile=profile)

            read_id = f"@SIM:{i}:{header}"
            f_r1.write(f"{read_id} 1:N:0:1\n{r1_seq}\n+\n{r1_qual}\n")
            f_r2.write(f"{read_id} 2:N:0:1\n{r2_seq}\n+\n{r2_qual}\n")


if __name__ == "__main__":
    main()
9