#!/usr/bin/env python3
"""Build autoresearch-compatible parquet shards from numeric time-series CSV.

Expected input: CSV with at least two numeric columns (source, target). Optionally a
separate time column for sorting.

The output writes parquet shards with a single `text` column into
~/.cache/autoresearch/data (or --output-dir), using shard names expected by prepare.py.
"""

from __future__ import annotations

import argparse
import math
import os
from pathlib import Path

import pandas as pd


def format_number(x: float, precision: int) -> str:
    return f"{x:.{precision}f}" if isinstance(x, float) else str(x)


def make_examples(df: pd.DataFrame, source_col: str, target_col: str, context: int, horizon: int, precision: int):
    examples = []
    n = len(df)
    max_start = n - (context + horizon) + 1
    for start in range(max(0, max_start)):
        src_vals = df[source_col].iloc[start : start + context].tolist()
        tgt_future = df[target_col].iloc[start + context : start + context + horizon].tolist()
        src_txt = " ".join(format_number(v, precision) for v in src_vals)
        tgt_txt = " ".join(format_number(v, precision) for v in tgt_future)
        text = (
            "Task: predict future target sequence from source history. "
            f"SourceHistory: {src_txt} "
            f"TargetFuture: {tgt_txt}"
        )
        examples.append(text)
    return examples


def write_shard(texts: list[str], out_dir: Path, shard_id: int):
    out_dir.mkdir(parents=True, exist_ok=True)
    path = out_dir / f"shard_{shard_id:05d}.parquet"
    pd.DataFrame({"text": texts}).to_parquet(path, index=False)
    return path


def main():
    p = argparse.ArgumentParser(description="Build parquet shards for numeric time-series forecasting")
    p.add_argument("--input-csv", required=True, help="Path to CSV input")
    p.add_argument("--source-col", required=True, help="Column used as conditioning sequence")
    p.add_argument("--target-col", required=True, help="Column used as future prediction target")
    p.add_argument("--time-col", default=None, help="Optional timestamp column for sorting")
    p.add_argument("--context", type=int, default=32, help="Number of source steps per example")
    p.add_argument("--horizon", type=int, default=8, help="Number of future target steps")
    p.add_argument("--val-ratio", type=float, default=0.1, help="Validation split fraction")
    p.add_argument("--precision", type=int, default=6, help="Float formatting precision")
    p.add_argument(
        "--output-dir",
        default=os.path.join(os.path.expanduser("~"), ".cache", "autoresearch", "data"),
        help="Directory to write shard_XXXXX.parquet files",
    )
    args = p.parse_args()

    df = pd.read_csv(args.input_csv)
    for col in (args.source_col, args.target_col):
        if col not in df.columns:
            raise ValueError(f"Column '{col}' not found in CSV")

    if args.time_col:
        if args.time_col not in df.columns:
            raise ValueError(f"Column '{args.time_col}' not found in CSV")
        df = df.sort_values(args.time_col).reset_index(drop=True)

    examples = make_examples(df, args.source_col, args.target_col, args.context, args.horizon, args.precision)
    if not examples:
        raise ValueError("Not enough rows for requested --context and --horizon")

    val_count = max(1, int(math.ceil(len(examples) * args.val_ratio)))
    val_examples = examples[-val_count:]
    train_examples = examples[:-val_count]

    if not train_examples:
        raise ValueError("No training examples left after validation split; lower --val-ratio")

    out_dir = Path(args.output_dir)
    train_path = write_shard(train_examples, out_dir, 0)
    val_path = write_shard(val_examples, out_dir, 1)

    print(f"Wrote train shard: {train_path} ({len(train_examples)} rows)")
    print(f"Wrote val shard:   {val_path} ({len(val_examples)} rows)")
    print("Set MAX_SHARD=1 and VAL_SHARD=1 in prepare.py before running prepare.py")


if __name__ == "__main__":
    main()
