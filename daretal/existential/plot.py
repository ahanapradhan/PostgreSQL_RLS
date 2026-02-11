import pandas as pd
import matplotlib.pyplot as plt
import numpy as np

# Load data
df = pd.read_csv("semijoin_rls.csv")

# Discard baseline from plot
plot_df = df.reset_index(drop=True)

# Plot setup
labels = plot_df["attack_name"]
x = np.arange(len(labels))
width = 0.5

plt.figure(figsize=(5, 5))

# Order: Min, Avg, Max
plt.bar(x, plot_df["rel_avg"], width)

# Formatting
plt.axhline(1.0, linestyle="--", linewidth=1)
plt.ylabel("Relative Slow-down", fontsize=18)
plt.xticks(x, labels, rotation=35, ha="right", fontsize=16)
plt.yticks(fontsize=12)
plt.tight_layout()

# Save figure
plt.savefig("semijoin_rls.png", dpi=300)
plt.close()

