% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/de_plots.r
\name{extract_coefficient_scatter}
\alias{extract_coefficient_scatter}
\title{Perform a coefficient scatter plot of a limma/deseq/edger/basic table.}
\usage{
extract_coefficient_scatter(
  output,
  toptable = NULL,
  type = "limma",
  x = 1,
  y = 2,
  z = 1.5,
  p = NULL,
  lfc = NULL,
  n = NULL,
  loess = FALSE,
  alpha = 0.4,
  color_low = "#DD0000",
  z_lines = FALSE,
  color_high = "#7B9F35",
  ...
)
}
\arguments{
\item{output}{Result from the de_ family of functions, all_pairwise, or
combine_de_tables().}

\item{toptable}{Chosen table to query for abundances.}

\item{type}{Query limma, deseq, edger, or basic outputs.}

\item{x}{The x-axis column to use, either a number of name.}

\item{y}{The y-axis column to use.}

\item{z}{Define the range of genes to color (FIXME: extend this to p-value
and fold-change).}

\item{p}{Set a p-value cutoff for coloring the scatter plot (currently not
supported).}

\item{lfc}{Set a fold-change cutoff for coloring points in the scatter plot
(currently not supported.)}

\item{n}{Set a top-n fold-change for coloring the points in the scatter plot
(this should work, actually).}

\item{loess}{Add a loess estimation (This is slow.)}

\item{alpha}{How see-through to make the dots.}

\item{color_low}{Color for the genes less than the mean.}

\item{z_lines}{Add lines to show the z-score demarcations.}

\item{color_high}{Color for the genes greater than the mean.}

\item{...}{More arguments are passed to arglist.}
}
\description{
Plot the gene abundances for two coefficients in a differential expression
comparison. By default, genes past 1.5 z scores from the mean are colored
red/green.
}
\examples{
\dontrun{
 expt <- create_expt(metadata = "some_metadata.xlsx", gene_info = annotations)
 pairwise_output <- all_pairwise(expt)
 scatter_plot <- extract_coefficient_scatter(pairwise_output,
                                             type = "deseq", x = "uninfected", y = "infected")
}
}
\seealso{
\pkg{ggplot2}
 \code{\link{plot_linear_scatter}}
}
