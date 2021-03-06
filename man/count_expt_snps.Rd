% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/variants.r
\name{count_expt_snps}
\alias{count_expt_snps}
\title{Gather snp information for an expt}
\usage{
count_expt_snps(
  expt,
  type = "counts",
  annot_column = "bcftable",
  tolower = TRUE,
  snp_column = "diff_count"
)
}
\arguments{
\item{expt}{an expressionset from which to extract information.}

\item{type}{Use counts / samples or ratios?}

\item{annot_column}{Column in the metadata for getting the table of bcftools calls.}

\item{tolower}{Lowercase stuff like 'HPGL'?}

\item{snp_column}{Which column of the parsed bcf table contains our interesting material?}
}
\value{
A new expt object
}
\description{
This function attempts to gather a set of variant positions using an extant
expressionset.  This therefore seeks to keep the sample metadata consistent
with the original data.  In its current iteration, it therefore makes some
potentially bad assumptions about the naming conventions for its input
files.  It furthermore assumes inputs from the variant calling methods in
cyoa.
}
\examples{
  \dontrun{
 expt <- create_expt(metadata, gene_information)
 snp_expt <- count_expt_snps(expt)
 ## This assumes that the metadata has a column named 'bcftable' with one file per
 ## cell.  These files in turn should have a column named 'diff_count' which will
 ## be the source of the numbers found when doing exprs(snp_expt).
}
}
