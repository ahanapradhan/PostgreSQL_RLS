import matplotlib.pyplot as plt
import numpy as np

# Data
categories = ["scan", "join-filter", "group-agg", "sort"]
woRLS = np.array([44.4431, 5.8219, 33.4271, 26.5701])
wRLS = np.array([81.6566, 47.6920, 75.2548, 59.5619])
view = np.array([87.4787, 8.9226, 81.0151, 73.8750])

# Compute relative overhead ratios
wRLS_ratio = wRLS / woRLS
view_ratio = view / woRLS

# X locations
x = np.arange(len(categories))
width = 0.35

# Create plot
plt.figure()
plt.bar(x - width/2, wRLS_ratio, width, label="RLS / baseline")
plt.bar(x + width/2, view_ratio, width, label="view / baseline")

plt.xticks(x, categories, fontsize=16)
plt.yticks(fontsize=18)
#plt.xlabel("Query Type", fontsize=18)
plt.ylabel("Relative Runtime (ratio)", fontsize=18)
#plt.title("Relative Overhead Comparison")
plt.legend(fontsize=18)

# Save figure
plt.savefig("semijoin_profile.png", dpi=300)
plt.close()

plt.show()
