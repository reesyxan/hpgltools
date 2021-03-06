% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/annotation_txt.r
\name{load_trinotate_go}
\alias{load_trinotate_go}
\title{Read a csv file from trinotate and extract ontology data from it.}
\usage{
load_trinotate_go(trinotate = "reference/trinotate.csv")
}
\arguments{
\item{trinotate}{CSV of trinotate annotation data.}
}
\value{
List of the extracted GO data, a table of it, length data, and the
  resulting length table.
}
\description{
Trinotate performs some neat sequence searches in order to seek out likely
annotations for the trinity contigs.  This function extracts ontology data
from it.  Keep in mind that this data is primarily from Blast2GO.
}
\examples{
 trinotate_go <- load_trinotate_go(trinotate = trinotate)
 dim(trinotate_go$go_data)
 dim(trinotate_go$go_table)
}
