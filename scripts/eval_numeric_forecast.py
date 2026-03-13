#!/usr/bin/env python3
"""Evaluate numeric forecasting outputs from a CSV file.

Input CSV must contain:
- y_true: ground-truth numeric value
- y_pred: predicted numeric value

Prints MAE, RMSE, MAPE, and directional accuracy.
"""

from __future__ import annotations

import argparse
import math

import pandas as pd


def main():
    p = argparse.ArgumentParser(description="Evaluate numeric forecast predictions")
    p.add_argument("--predictions-csv", required=True, help="CSV containing y_true,y_pred columns")
    args = p.parse_args()

    df = pd.read_csv(args.predictions_csv)
    required = {"y_true", "y_pred"}
    missing = required - set(df.columns)
    if missing:
        raise ValueError(f"Missing required columns: {sorted(missing)}")

    y_true = df["y_true"].astype(float)
    y_pred = df["y_pred"].astype(float)
    err = y_pred - y_true

    mae = err.abs().mean()
    rmse = math.sqrt((err ** 2).mean())

    denom = y_true.abs().replace(0.0, pd.NA)
    mape = ((err.abs() / denom).dropna() * 100.0).mean()

    if len(y_true) >= 2:
        true_diff = y_true.diff().fillna(0.0)
        pred_diff = y_pred.diff().fillna(0.0)
        directional_acc = (true_diff.mul(pred_diff) >= 0).mean() * 100.0
    else:
        directional_acc = float("nan")

    print("--- Forecast Metrics ---")
    print(f"rows:               {len(df)}")
    print(f"mae:                {mae:.6f}")
    print(f"rmse:               {rmse:.6f}")
    print(f"mape_percent:       {mape:.4f}")
    print(f"directional_acc_%:  {directional_acc:.2f}")


if __name__ == "__main__":
    main()
