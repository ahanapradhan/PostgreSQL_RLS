import matplotlib.pyplot as plt
import numpy as np

timings = {
    "group_agg": 1976.6233,
"group_agg_view": 66.4950,
"group_agg_without_rls": 22.6289,
"join-filter": 1974.2998,
"join-filter_view": 29.2025,
"join-filter_without_rls": 20.3624,
"order_by": 1976.1800,
"order_by_view": 82.4158,
"order_by_without_rls": 126.0892,
"scan": 1951.1054,
"scan_view": 82.2724,
"scan_without_rls": 117.9531,
}

categories = ["scan", "join-filter", "group-agg", "sort"]
woRLS = np.array([
    timings["scan_without_rls"],
    timings["join-filter_without_rls"],
    timings["group_agg_without_rls"],
    timings["order_by_without_rls"]
])

wRLS = np.array([
    timings["scan"],
    timings["join-filter"],
    timings["group_agg"],
    timings["order_by"]
])

view = np.array([
    timings["scan_view"],
    timings["join-filter_view"],
    timings["group_agg_view"],
    timings["order_by_view"]
])



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
plt.savefig("join_profile.png", dpi=300)
plt.close()

plt.show()
