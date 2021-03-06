% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/plot_circos.r
\name{circos_hist}
\alias{circos_hist}
\title{Write histograms of arbitrary floating point data in circos.}
\usage{
circos_hist(
  cfg,
  df,
  colname = "logFC",
  basename = "",
  color = "blue",
  fill_color = "blue",
  fill_under = "yes",
  extend_bin = "no",
  thickness = "0",
  orientation = "out",
  outer = 0.9,
  width = 0.08,
  spacing = 0
)
}
\arguments{
\item{cfg}{Result of circos_prefix(), contains a bunch of useful material.}

\item{df}{Dataframe with starts/ends and the floating point information.}

\item{colname}{Name of the column with the data of interest.}

\item{basename}{Location to write the circos data (usually cwd).}

\item{color}{Color of the plotted data.}

\item{fill_color}{Guess}

\item{fill_under}{The circos histogram fill under parameter}

\item{extend_bin}{Extend bins?}

\item{thickness}{histogram thickness.}

\item{orientation}{facing in or out?}

\item{outer}{Floating point radius of the circle into which to place the data.}

\item{width}{Radial width of each tile.}

\item{spacing}{Distance between outer, inner, and inner to whatever follows.}
}
\value{
Radius after adding the histogram and the spacing.
}
\description{
This function tries to make the writing of histogram data in circos
easier.  Like circos_plus_minus() it works in 3 stages,
It writes out a data file using cfgout as a basename and the data
from df in the circos histogram format into
circos/data/bob_hist.txt
It then writes out a configuration plot stanza in
circos/conf/bob_hist.conf
and finally adds an include to circos/bob.conf
}
