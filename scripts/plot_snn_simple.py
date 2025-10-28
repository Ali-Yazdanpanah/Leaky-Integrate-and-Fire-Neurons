#!/usr/bin/env python3
"""
Plot snn_simple testbench traces recorded in snn_simple_trace.csv.
"""

import argparse
from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd
import seaborn as sns


def load_trace(path: Path) -> pd.DataFrame:
    if not path.is_file():
        raise FileNotFoundError(f"Trace file not found: {path}")
    return pd.read_csv(path)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Plot waveforms from snn_simple_trace.csv"
    )
    parser.add_argument(
        "csv",
        nargs="?",
        default="snn_simple_trace.csv",
        help="Path to CSV trace file (default: %(default)s)",
    )
    args = parser.parse_args()

    df = load_trace(Path(args.csv))
    if len(df) > 500:
        df = df.iloc[:500].copy()  # Limit plots to first 500 samples for readability

    sns.set_theme(style="whitegrid")

    fig, axes = plt.subplots(3, 1, figsize=(12, 8), sharex=True)

    sns.lineplot(
        ax=axes[0],
        data=df,
        x="time_ns",
        y="n0_v_real",
        label="n0_v",
        color="tab:blue",
    )
    sns.lineplot(
        ax=axes[0],
        data=df,
        x="time_ns",
        y="n1_v_real",
        label="n1_v",
        color="tab:orange",
    )
    axes[0].set_ylabel("Membrane (V)")
    axes[0].set_title("Neuron membrane voltages")
    axes[0].legend(loc="upper right")

    sns.lineplot(
        ax=axes[1],
        data=df,
        x="time_ns",
        y="in0_spk",
        label="in0_spk",
        drawstyle="steps-post",
        color="tab:green",
    )
    sns.lineplot(
        ax=axes[1],
        data=df,
        x="time_ns",
        y="in1_spk",
        label="in1_spk",
        drawstyle="steps-post",
        color="tab:red",
    )
    axes[1].set_ylabel("Input spikes")
    axes[1].set_ylim(-0.1, 1.1)
    axes[1].legend(loc="upper right")

    for neuron, color in (("n0_spk", "tab:blue"), ("n1_spk", "tab:orange")):
        spike_times = df.loc[df[neuron] == 1, "time_ns"]
        axes[2].eventplot(
            spike_times,
            colors=color,
            lineoffsets=1 if neuron == "n0_spk" else 0,
            linelengths=0.4,
        )
    axes[2].set_yticks([0, 1])
    axes[2].set_yticklabels(["n1", "n0"])
    axes[2].set_ylabel("Spikes")
    axes[2].set_xlabel("Time (ns)")
    axes[2].set_title("Neuron spike events")

    fig.tight_layout()
    plt.show()


if __name__ == "__main__":
    main()
