% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/annotation_uniprot.r
\name{load_uniprot_annotations}
\alias{load_uniprot_annotations}
\title{Read a uniprot text file and extract as much information from it as possible.}
\usage{
load_uniprot_annotations(file = NULL, species = NULL, savefile = TRUE)
}
\arguments{
\item{file}{Uniprot file to read and parse}

\item{species}{Species name to download/load.}

\item{savefile}{Do a save?}
}
\value{
Big dataframe of annotation data.
}
\description{
I spent entirely too long fighting with Uniprot.ws, finally got mad and wrote this.
}
\examples{
 sc_uniprot_annot <- load_uniprot_annotations(file = uniprot_sc_downloaded$filename)
 dim(sc_uniprot_annot)
}
