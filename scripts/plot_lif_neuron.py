#!/usr/bin/env python3
"""
Plot lif_neuron testbench traces using seaborn.

Usage:
    python scripts/plot_lif_neuron.py [path/to/lif_neuron_trace.csv]
"""

import argparse
from pathlib import Path

import pandas as pd
import seaborn as sns
import matplotlib.pyplot as plt


def load_data(csv_path: Path) -> pd.DataFrame:
    if not csv_path.is_file():
        raise FileNotFoundError(f"CSV file not found: {csv_path}")
    df = pd.read_csv(csv_path)
    return df


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Plot lif_neuron waveforms captured by tb_lif_neuron.sv."
    )
    parser.add_argument(
        "csv",
        nargs="?",
        default="lif_neuron_trace.csv",
        help="Path to lif_neuron_trace.csv (default: %(default)s)",
    )
    args = parser.parse_args()

    csv_path = Path(args.csv)
    df = load_data(csv_path)
    if len(df) > 500:
        df = df.iloc[:500].copy()  # Limit plots to first 500 samples for readability

    sns.set_theme(style="whitegrid")

    fig, axes = plt.subplots(3, 1, figsize=(10, 8), sharex=True)

    sns.lineplot(
        ax=axes[0],
        data=df,
        x="time_ns",
        y="v_mem_real",
        label="v_mem",
        color="tab:blue",
    )
    sns.lineplot(
        ax=axes[0],
        data=df,
        x="time_ns",
        y="exp_vmem_real",
        label="expected v_mem",
        color="tab:orange",
        linestyle="--",
    )
    if "exp_vmem_pre_real" in df.columns:
        sns.lineplot(
            ax=axes[0],
            data=df,
            x="time_ns",
            y="exp_vmem_pre_real",
            label="pre-reset v_mem",
            color="tab:olive",
            linestyle=":",
        )
    axes[0].axhline(1.0, color="tab:red", linestyle=":", linewidth=1.0, label="V_TH")
    axes[0].set_ylabel("Membrane (V)")
    axes[0].set_title("Membrane voltage vs. expected")

    sns.lineplot(
        ax=axes[1],
        data=df,
        x="time_ns",
        y="i_in_real",
        label="i_in",
        color="tab:green",
    )
    sns.lineplot(
        ax=axes[1],
        data=df,
        x="time_ns",
        y="exc_delayed_real",
        label="exc_delayed",
        color="tab:purple",
    )
    sns.lineplot(
        ax=axes[1],
        data=df,
        x="time_ns",
        y="inh_delayed_real",
        label="inh_delayed",
        color="tab:red",
    )
    axes[1].set_ylabel("Current (A)")
    axes[1].set_title("Input currents")

    spike_times = df.loc[df["spike"] == 1, "time_ns"]
    axes[2].eventplot(spike_times, colors="tab:blue", lineoffsets=1, linelengths=0.8)
    axes[2].set_ylim(0.5, 1.5)
    axes[2].set_yticks([])
    axes[2].set_ylabel("Spikes")
    axes[2].set_title("Spike events")

    axes[2].set_xlabel("Time (ns)")
    axes[0].legend()
    axes[1].legend()

    fig.tight_layout()
    plt.show()


if __name__ == "__main__":
    main()
