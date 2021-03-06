% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/annotation_biomart.r
\name{load_biomart_annotations}
\alias{load_biomart_annotations}
\title{Extract annotation information from biomart.}
\usage{
load_biomart_annotations(
  species = "hsapiens",
  overwrite = FALSE,
  do_save = TRUE,
  host = NULL,
  trymart = "ENSEMBL_MART_ENSEMBL",
  archive = TRUE,
  default_hosts = c("useast.ensembl.org", "uswest.ensembl.org", "www.ensembl.org",
    "asia.ensembl.org"),
  year = NULL,
  month = NULL,
  drop_haplotypes = TRUE,
  trydataset = NULL,
  gene_requests = c("ensembl_gene_id", "version", "ensembl_transcript_id",
    "transcript_version", "hgnc_symbol", "description", "gene_biotype"),
  length_requests = c("ensembl_transcript_id", "cds_length", "chromosome_name",
    "strand", "start_position", "end_position"),
  include_lengths = TRUE
)
}
\arguments{
\item{species}{Choose a species.}

\item{overwrite}{Overwite an existing save file?}

\item{do_save}{Create a savefile of annotations for future runs?}

\item{host}{Ensembl hostname to use.}

\item{trymart}{Biomart has become a circular dependency, this makes me sad,
now to list the marts, you need to have a mart loaded.}

\item{archive}{Try an archive server instead of a mirror?  If this is a
character, it will assume it is a specific archive hostname.}

\item{default_hosts}{List of biomart mirrors to try.}

\item{year}{Choose specific year(s) for the archive servers?}

\item{month}{Choose specific month(s) for the archive server?}

\item{drop_haplotypes}{Some chromosomes have stupid names because they are
from non-standard haplotypes and they should go away.  Setting this to
false stops that.}

\item{trydataset}{Choose the biomart dataset from which to query.}

\item{gene_requests}{Set of columns to query for description-ish annotations.}

\item{length_requests}{Set of columns to query for location-ish annotations.}

\item{include_lengths}{Also perform a search on structural elements in the genome?}
}
\value{
List containing: a data frame of the found annotations, a copy of
 The mart instance to help with finding problems, the hostname queried, the
 name of the mart queried, a vector of rows queried, vector of the available
 attributes, and the ensembl dataset queried.
}
\description{
Biomart is an amazing resource of information, but using it is a bit
annoying.  This function hopes to alleviate some common headaches.
}
\details{
Tested in test_40ann_biomart.R
This goes to some lengths to find the relevant tables in biomart.  But
biomart is incredibly complex and one should carefully inspect the output if
it fails to see if there are more appropriate marts, datasets, and columns to
download.
}
\examples{
 ## This downloads the hsapiens annotations by default.
 hs_biomart_annot <- load_biomart_annotations()
 summary(hs_biomart_annot)
 dim(hs_biomart_annot$annotation)
}
\seealso{
\pkg{biomaRt}
 \code{\link[biomaRt]{listDatasets}} \code{\link[biomaRt]{getBM}}
}
