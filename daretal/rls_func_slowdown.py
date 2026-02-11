import pandas as pd
import matplotlib.pyplot as plt
import numpy as np

# Load data
df = pd.read_csv("rls_func_slowdown.csv")

# Extract baseline row
baseline = df[df["attack"] == "Baseline scan"]
if baseline.empty:
    raise ValueError("Baseline scan row not found")

baseline_avg = baseline["avg_ms"].iloc[0]
baseline_min = baseline["min_ms"].iloc[0]
baseline_max = baseline["max_ms"].iloc[0]

# Compute slowdowns
df["avg_slowdown"] = df["avg_ms"] / baseline_avg
df["min_slowdown"] = df["min_ms"] / baseline_min
df["max_slowdown"] = df["max_ms"] / baseline_max

# Discard baseline from plot
plot_df = df[df["attack"] != "Baseline scan"].reset_index(drop=True)

# Plot setup
labels = plot_df["attack"]
x = np.arange(len(labels))
width = 0.25

plt.figure(figsize=(12, 5))

# Order: Min, Avg, Max
plt.bar(x - width, plot_df["min_slowdown"], width, label="Relative Min")
plt.bar(x,         plot_df["avg_slowdown"], width, label="Relative Avg")
plt.bar(x + width, plot_df["max_slowdown"], width, label="Relative Max")

# Formatting
plt.axhline(1.0, linestyle="--", linewidth=1)
plt.ylabel("Slow-down vs Baseline scan")
plt.xticks(x, labels, rotation=35, ha="right")
plt.legend()
plt.tight_layout()

# Save figure
plt.savefig("rls_func_slowdown.png", dpi=300)
plt.close()

print("Saved figure: view_slowdown.png")
