# Goal
Train a small forecasting model that predicts future values of target stream B from recent source stream A.

# Constraints
- Keep each iteration small and reversible.
- Do not increase peak VRAM unless metric improves clearly.
- Prefer stable training over ambitious architecture changes.

# Data assumptions
- Training text format is:
  "Task: predict future target sequence from source history. SourceHistory: <numbers> TargetFuture: <numbers>"
- Validate on held-out time windows only (no random leakage across time).

# Experiment loop
1. Propose one small train.py change.
2. Run one training experiment.
3. Report:
   - val_bpb
   - peak_vram_mb
   - tokens/sec
4. Keep change only if val_bpb is better and memory is not worse.
5. Every 5 accepted changes, summarize what worked.

# Safety checks
- Abort/revert if NaN loss or exploding loss appears.
- If OOM happens, reduce MAX_SEQ_LEN / batch before changing model depth.
