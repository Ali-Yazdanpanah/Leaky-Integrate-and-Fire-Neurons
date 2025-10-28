#!/usr/bin/env python3
"""
Plot snn_suite testbench traces recorded in snn_suite_trace.csv.
"""

import argparse
from pathlib import Path
from typing import Dict

import matplotlib.pyplot as plt
import pandas as pd
import seaborn as sns


def load_trace(path: Path) -> pd.DataFrame:
    if not path.is_file():
        raise FileNotFoundError(f"Trace file not found: {path}")
    return pd.read_csv(path)


def add_scene_spans(ax, df: pd.DataFrame, palette: Dict[str, str]) -> None:
    current_scene = None
    span_start = None
    last_time = None
    for _, row in df.iterrows():
        scene = row["scene"]
        time = row["time_ns"]
        if scene != current_scene:
            if current_scene is not None and span_start is not None:
                ax.axvspan(
                    span_start,
                    time,
                    alpha=0.08,
                    color=palette[current_scene],
                    linewidth=0,
                )
            current_scene = scene
            span_start = time
        last_time = time
    if current_scene is not None and span_start is not None and last_time is not None:
        ax.axvspan(
            span_start,
            last_time,
            alpha=0.08,
            color=palette[current_scene],
            linewidth=0,
        )


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Plot waveforms from snn_suite_trace.csv"
    )
    parser.add_argument(
        "csv",
        nargs="?",
        default="snn_suite_trace.csv",
        help="Path to CSV trace file (default: %(default)s)",
    )
    args = parser.parse_args()

    df = load_trace(Path(args.csv))
    if len(df) > 500:
        df = df.iloc[:500].copy()  # Limit plots to first 500 samples for readability

    sns.set_theme(style="whitegrid")
    scenes = df["scene"].unique()
    palette = dict(
        zip(
            scenes,
            sns.color_palette("husl", len(scenes)),
        )
    )

    fig, axes = plt.subplots(3, 1, figsize=(12, 9), sharex=True)

    add_scene_spans(axes[0], df, palette)
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
    mem_handles, mem_labels = axes[0].get_legend_handles_labels()

    add_scene_spans(axes[1], df, palette)
    sns.lineplot(
        ax=axes[1],
        data=df,
        x="time_ns",
        y="n0_i_real",
        label="n0_i",
        color="tab:green",
    )
    sns.lineplot(
        ax=axes[1],
        data=df,
        x="time_ns",
        y="n1_i_real",
        label="n1_i",
        color="tab:red",
    )
    sns.lineplot(
        ax=axes[1],
        data=df,
        x="time_ns",
        y="n0_g_exc_real",
        label="n0_g_exc",
        color="tab:purple",
        linestyle="--",
    )
    sns.lineplot(
        ax=axes[1],
        data=df,
        x="time_ns",
        y="n1_g_exc_real",
        label="n1_g_exc",
        color="tab:brown",
        linestyle="--",
    )
    axes[1].set_ylabel("Currents / conductances")
    axes[1].legend(loc="upper right")

    add_scene_spans(axes[2], df, palette)
    for offset, (neuron, color) in enumerate(
        (("n0_spk", "tab:blue"), ("n1_spk", "tab:orange"))
    ):
        spike_times = df.loc[df[neuron] == 1, "time_ns"]
        axes[2].eventplot(
            spike_times,
            colors=color,
            lineoffsets=offset,
            linelengths=0.6,
        )
    axes[2].set_yticks([0, 1])
    axes[2].set_yticklabels(["n0", "n1"])
    axes[2].set_ylabel("Spikes")
    axes[2].set_xlabel("Time (ns)")
    axes[2].set_title("Spike events by scene")

    scene_patches = [
        plt.Line2D([0], [0], color=palette[scene], lw=6, alpha=0.4, label=scene)
        for scene in scenes
    ]
    axes[0].legend(
        handles=mem_handles + scene_patches,
        labels=mem_labels + list(scenes),
        loc="upper left",
        title="Membrane / scenes",
    )

    fig.tight_layout()
    plt.show()


if __name__ == "__main__":
    main()
