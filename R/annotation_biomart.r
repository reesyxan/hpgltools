## annotation_biomart.r: A group of functions to simplify extracting annotations
## from biomart. Most of our projects use Ensembl gene IDs, thus having
## consistent access to the ensembl annotations is quite useful.

#' Find a functional biomart instance.
#'
#' In my experience, the various biomart mirrors are not varyingly likely to be
#' functional at any given time.  In addition, I often find it useful to use an
#' archive instance rather than the most recent ensembl instance.  This function
#' therefore iterates over the various mirrors; or if archive = TRUE it will try a
#' series of archive servers from 1, 2, and 3 years ago.
#'
#' @param default_hosts List of biomart mirrors to try.
#' @param trymart Specific mart to query.
#' @param archive Try an archive server instead of a mirror?  If this is a
#'  character, it will assume it is a specific archive hostname.
#' @param year Choose specific year(s) for the archive servers?
#' @param month Choose specific month(s) for the archive servers?
#' @return Either a mart instance or NULL if no love was forthcoming.
#' @export
find_working_mart <- function(default_hosts = c("useast.ensembl.org", "uswest.ensembl.org",
                                              "www.ensembl.org", "asia.ensembl.org"),
                              trymart = "ENSEMBL_MART_ENSEMBL", archive = FALSE,
                              year = NULL, month = NULL) {
  if (isTRUE(archive)) {
    if (is.null(month)) {
      ## Then assume this month
      month_numeric <- lubridate::month(lubridate::date(lubridate::now()))
      month_nums <- c(month_numeric, month_numeric - 1, month_numeric - 2)
      for (m in 1:length(month_nums)) {
        if (month_nums[m] < 1) {
          month_nums[m] <- month_nums[m] + 12
        }
      }
      month_strings <- as.character(lubridate::month(month_nums, label = TRUE, abbr = TRUE))
    }
    if (is.null(year)) {
      year_numeric <- lubridate::year(lubridate::date(lubridate::now()))
      year_strings <- as.character(c(year_numeric - 1, year_numeric - 2, year_numeric - 3))
    }
    archives <- c()
    for (y in year_strings) {
      for (m in month_strings) {
        archives <- c(archives, paste0(m, y))
      }
    }
    default_hosts <- paste0(archives, ".archive.ensembl.org")
  } else if ("character" %in% class(archive)) {
    default_hosts <- archive
  }

  mart <- NULL
  used_host <- NULL
  used_mart <- NULL
  for (host in default_hosts) {
    mart <- try(biomaRt::useMart(biomart = trymart, host = host), silent = TRUE)
    cmart <- class(mart)
    if (cmart[1] == "Mart") {
      message("Using mart: ", trymart, " from host: ", host, ".")
      used_host <- host
      used_mart <- trymart
      break
    } else if ("try-error" %in% cmart) {
      if (grepl(pattern = "Timeout", x = mart[1])) {
        message("Timed out when trying ", host, ".")
        next
      } else if (grepl(pattern = "Unexpected format", x = mart[1])) {
        message("Got a bad mart type when trying host ", host, " mart ", trymart, ".")
        next
      } else {
        message("Unable to perform useMart, perhaps the host/mart is incorrect: ",
                host, " ", trymart, ".")
        marts <- biomaRt::listMarts(host = host)
        mart_names <- as.character(marts[[1]])
        message("The available marts are: ")
        message(toString(mart_names))
        message("Trying the first one.")
        mart <- try(biomaRt::useMart(biomart = marts[[1, 1]], host = host))
        if (! "try-error" %in% class(mart)) {
          used_host <- host
          used_mart <- marts[[1, 1]]
          break
        } else {
          used_mart <- trymart
          used_host <- host
          break
        }
      } ## End checking the state of the chosen mart.
    } else {
      ## This is neither a mart nor is it a try-error.
      stop("I do not know what this is: ", class(mart))
    }
  } ## End iterating over the hosts.
  retlist <- list(
      "host" = used_host,
      "used_mart" = used_mart,
      "mart" = mart)
  return(retlist)
}

#' Extract annotation information from biomart.
#'
#' Biomart is an amazing resource of information, but using it is a bit
#' annoying.  This function hopes to alleviate some common headaches.
#'
#' Tested in test_40ann_biomart.R
#' This goes to some lengths to find the relevant tables in biomart.  But
#' biomart is incredibly complex and one should carefully inspect the output if
#' it fails to see if there are more appropriate marts, datasets, and columns to
#' download.
#'
#' @param species Choose a species.
#' @param overwrite Overwite an existing save file?
#' @param do_save Create a savefile of annotations for future runs?
#' @param host Ensembl hostname to use.
#' @param trymart Biomart has become a circular dependency, this makes me sad,
#'  now to list the marts, you need to have a mart loaded.
#' @param archive Try an archive server instead of a mirror?  If this is a
#'  character, it will assume it is a specific archive hostname.
#' @param default_hosts List of biomart mirrors to try.
#' @param year Choose specific year(s) for the archive servers?
#' @param month Choose specific month(s) for the archive server?
#' @param drop_haplotypes Some chromosomes have stupid names because they are
#'  from non-standard haplotypes and they should go away.  Setting this to
#'  false stops that.
#' @param trydataset Choose the biomart dataset from which to query.
#' @param gene_requests Set of columns to query for description-ish annotations.
#' @param length_requests Set of columns to query for location-ish annotations.
#' @param include_lengths Also perform a search on structural elements in the genome?
#' @return List containing: a data frame of the found annotations, a copy of
#'  The mart instance to help with finding problems, the hostname queried, the
#'  name of the mart queried, a vector of rows queried, vector of the available
#'  attributes, and the ensembl dataset queried.
#' @seealso \pkg{biomaRt}
#'  \code{\link[biomaRt]{listDatasets}} \code{\link[biomaRt]{getBM}}
#' @examples
#'  ## This downloads the hsapiens annotations by default.
#'  hs_biomart_annot <- load_biomart_annotations()
#'  summary(hs_biomart_annot)
#'  dim(hs_biomart_annot$annotation)
#' @export
load_biomart_annotations <- function(species = "hsapiens", overwrite = FALSE, do_save = TRUE,
                                     host = NULL, trymart = "ENSEMBL_MART_ENSEMBL", archive = TRUE,
                                     default_hosts = c("useast.ensembl.org", "uswest.ensembl.org",
                                                       "www.ensembl.org", "asia.ensembl.org"),
                                     year = NULL, month = NULL, drop_haplotypes = TRUE, trydataset = NULL,
                                     gene_requests = c("ensembl_gene_id",
                                                     "version",
                                                     "ensembl_transcript_id",
                                                     "transcript_version", "hgnc_symbol",
                                                     "description", "gene_biotype"),
                                     length_requests = c("ensembl_transcript_id",
                                                       "cds_length", "chromosome_name",
                                                       "strand", "start_position",
                                                       "end_position"),
                                     include_lengths = TRUE) {
  savefile <- glue("{species}_biomart_annotations.rda")
  biomart_annotations <- NULL
  if (file.exists(savefile) & overwrite == FALSE) {
    fresh <- new.env()
    message("The biomart annotations file already exists, loading from it.")
    ## load_string <- paste0("load('", savefile, "', envir = fresh)")
    load_string <- glue("load('{savefile}', envir = fresh)")
    eval(parse(text = load_string))
    biomart_annotations <- fresh[["biomart_annotations"]]
    retlist <- list(
      "annotation" = biomart_annotations,
      "mart" = "savefile",
      "host" = "savefile",
      "mart_name" = "savefile",
      "rows" = "savefile",
      "dataset" = "savefile"
    )
    return(retlist)
  }
  martlst <- NULL
  if (is.null(host) & is.null(default_hosts)) {
    stop("both host and default_hosts are null.")
  } else if (is.null(host)) {
    martlst <- find_working_mart(default_hosts = default_hosts, trymart = trymart,
                                 archive = archive, year = year, month = month)
  } else {
    martlst <- find_working_mart(default_hosts = host, trymart = trymart,
                                 archive = FALSE)
  }
  used_mart <- NULL
  mart <- NULL
  host <- NULL
  if (!is.null(martlst)) {
    used_mart <- martlst[["used_mart"]]
    host <- martlst[["host"]]
    mart <- martlst[["mart"]]
  }
  chosen_dataset <- NULL
  dataset <- NULL
  if (!is.null(trydataset)) {
    dataset <- trydataset
  } else {
    ## dataset <- paste0(species, "_gene_ensembl")
    dataset <- glue("{species}_gene_ensembl")
  }
  ## second_dataset <- paste0(species, "_eg_gene")
  second_dataset <- glue("{species}_eg_gene")
  ensembl <- try(biomaRt::useDataset(dataset, mart = mart), silent = TRUE)
  if (class(ensembl) == "try-error") {
    ensembl <- try(biomaRt::useDataset(second_dataset, mart = mart), silent = TRUE)
    if (class(ensembl) == "try-error") {
      message("Unable to perform useDataset, the given dataset is incorrect: ", dataset, ".")
      datasets <- biomaRt::listDatasets(mart = mart)
      message(toString(datasets))
      return(NULL)
    } else {
      message("Successfully connected to the ", second_dataset, " database.")
      chosen_dataset <- second_dataset
    }
  } else {
    message("Successfully connected to the ", dataset, " database.")
    chosen_dataset <- dataset
  }
  ## The following was stolen from Laura's logs for human annotations.
  ## To see possibilities for attributes, use head(listAttributes(ensembl), n = 20L)
  gene_ids <- biomaRt::getBM(attributes = "ensembl_gene_id", mart = ensembl)
  chosen_annotations <- c()
  available_attribs <- biomaRt::listAttributes(ensembl)[["name"]]
  found_attribs <- gene_requests %in% available_attribs
  if (length(gene_requests) != sum(found_attribs)) {
    message("Some attributes in your request list were not in the ensembl database.")
    gene_requests <- gene_requests[found_attribs]
  }
  gene_annotations <- biomaRt::getBM(attributes = gene_requests,
                                     filters = "ensembl_gene_id",
                                     values = gene_ids,
                                     mart = ensembl)
  chosen_annotations <- c(gene_requests)
  message("Finished downloading ensembl gene annotations.")
  biomart_annotations <- NULL
  if (isTRUE(include_lengths)) {
    found_attribs <- length_requests %in% available_attribs
    if (length(length_requests) != sum(found_attribs)) {
      message("Some attributes in your request list were not in the ensembl database.")
      length_requests <- length_requests[found_attribs]
    }
    ## The following 10ish lines are in an attempt to work around annoying timeouts by biomart.
    ## Asking for the set of coordinates by transcript is more than asking by gene,
    ## So, first try asking by transcript and if that fails, try by gene.
    ## If that also fails, then eff it.
    tmp_annot <- data.table::as.data.table(gene_annotations)
    tmp_length_requests <- length_requests
    chosen_by <- "ensembl_transcript_id"
    structure_annotations <- try(biomaRt::getBM(attributes = tmp_length_requests,
                                                filters = "ensembl_gene_id",
                                                values = gene_ids,
                                                mart = ensembl))
    if (class(structure_annotations)[1] == "try-error") {
      chosen_by <- "ensembl_gene_id"
      tmp_length_requests[1] <- chosen_by
      structure_annotations <- try(biomaRt::getBM(attributes = tmp_length_requests,
                                                  mart = ensembl))
    }

    if ("try-error" %in% class(structure_annotations)) {
      biomart_annotations <- tmp_annot
    } else {
      message("Finished downloading ensembl structure annotations.")
      tmp_struct <- data.table::as.data.table(structure_annotations)
      biomart_annotations <- merge(tmp_annot, tmp_struct, by = chosen_by, all.x = TRUE)
      biomart_annotations <- as.data.frame(biomart_annotations)
      chosen_annotations <- c(chosen_annotations, length_requests)
    }
  } else {
    ## Do not include the lengths
    biomart_annotations <- gene_annotations
  }
  ## rownames(biomart_annotations) <- make.names(biomart_annotations[,
  ## "transcriptID"], unique = TRUE) It is not valid to arbitrarily set it to
  ## 'transcriptID' because we cannot guarantee that will be the column name,
  ## but I think we can safely assume it will be the 1st column.
  biomart_annotations <- as.data.frame(biomart_annotations)
  rownames(biomart_annotations) <- make.names(biomart_annotations[, 1], unique = TRUE)

  ## In order for the return from this function to work with other functions in
  ## this, the rownames must be set.

  ## Set strand to +/-
  if (!is.null(biomart_annotations[["strand"]])) {
    biomart_annotations[["strand"]] <- ifelse(biomart_annotations[["strand"]] == "1", "+", "-")
  }

  ## Steve has some excellent questions regarding multiple gene IDs for a single known locus:
  ## Example: hgnc_id:TNF which lies on chromosome 6 has 8 gene IDs, 7 of which appear to be
  ## associated with haplotype chromosomes with names like 'CHR_HSCHR6_MHC_DBB_CTG1' as opposed
  ## to the rather simpler chromosome name '6'.
  ## Thus, if one wishes to get rid of these putatively spurious annotations, we should be
  ## able to grep -v chromosomes with MHC in them.
  if (isTRUE(drop_haplotypes)) {
    if (!is.null(biomart_annotations[["chromosome_name"]])) {
      message("Dropping haplotype chromosome annotations, ",
              "set drop_haplotypes = FALSE if this is bad.")
      good_idx <- grepl(x = biomart_annotations[["chromosome_name"]],
                        pattern = "^[[:alnum:]]{1,2}$")
      biomart_annotations <- biomart_annotations[good_idx, ]
    } else {
      message("drop_haplotypes is TRUE, but there is no chromosome information.")
    }
  } else {
    message("Not dropping haplotype chromosome annotations, ",
            "set drop_haplotypes = TRUE if this is bad.")
  }

  if (isTRUE(do_save)) {
    message("Saving annotations to ", savefile, ".")
    save(list = ls(pattern = "biomart_annotations"), file = savefile)
    message("Finished save().")
  }
  retlist <- list(
    "annotation" = biomart_annotations,
    "mart" = ensembl,
    "host" = host,
    "mart_name" = used_mart,
    "columns" = chosen_annotations,
    "possible_attribs" = available_attribs,
    "dataset" = chosen_dataset
  )
  return(retlist)
}

#' Extract gene ontology information from biomart.
#'
#' I perceive that every time I go to acquire annotation data from biomart, they
#' have changed something important and made it more difficult for me to find
#' what I want. I recently found the *.archive.ensembl.org, and so this function
#' uses that to try to keep things predictable, if not consistent.
#'
#' Tested in test_40ann_biomart.R
#' This function makes a couple of attempts to pick up the correct tables from
#' biomart.  It is worth noting that it uses the archive.ensembl host(s) because
#' of changes in table organization after December 2015 as well as an attempt to
#' keep the annotation sets relatively consistent.
#'
#' @param species Species to query.
#' @param overwrite Overwrite existing savefile?
#' @param do_save Create a savefile of the annotations? (if not false, then a filename.)
#' @param host Ensembl hostname to use.
#' @param trymart Biomart has become a circular dependency, this makes me sad,
#'  now to list the marts, you need to have a mart loaded.
#' @param archive Try an archive server instead of a mirror?  If this is a
#'  character, it will assume it is a specific archive hostname.
#' @param default_hosts List of biomart mirrors to try.
#' @param year Choose specific year(s) for the archive servers?
#' @param month Choose specific month(s) for the archive servers?
#' @param drop_haplotypes Some chromosomes have stupid names because they are
#'  from non-standard haplotypes and they should go away.  Setting this to
#'  false stops that.
#' @param secondtry The newer mart name.
#' @param dl_rows List of rows from the final biomart object to download.
#' @param dl_rowsv2 A second list of potential rows.
#' @return List containing the following:  data frame of ontology data, a copy
#'  of the biomart instance for further querying, the host queried, the biomart
#'  queried, a vector providing the attributes queried, and the ensembl dataset
#'  queried.
#' @seealso \pkg{biomaRt}
#'  \code{\link[biomaRt]{listMarts}} \code{\link[biomaRt]{useDataset}}
#'  \code{\link[biomaRt]{getBM}}
#' @examples
#'  hs_biomart_ontology <-load_biomart_go()
#'  summary(hs_biomart_ontology)
#'  dim(hs_biomart_ontology$go)
#' @export
load_biomart_go <- function(species = "hsapiens", overwrite = FALSE, do_save = TRUE,
                            host = NULL, trymart = "ENSEMBL_MART_ENSEMBL", archive = TRUE,
                            default_hosts = c("useast.ensembl.org", "uswest.ensembl.org",
                                              "www.ensembl.org", "asia.ensembl.org"),
                            year = NULL, month = NULL, drop_haplotypes = TRUE,
                            secondtry = "_gene", dl_rows = c("ensembl_gene_id", "go_accession"),
                            dl_rowsv2 = c("ensembl_gene_id", "go_id")) {
  secondtry <- glue("{species}{secondtry}")
  savefile <- glue("{species}_go_annotations.rda")
  if (!identical(FALSE, do_save)) {
    if (class(do_save)[1] == "character") {
      savefile <- do_save
      do_save <- TRUE
    }
  }

  if (file.exists(savefile) & overwrite == FALSE) {
    fresh <- new.env()
    message("The biomart annotations file already exists, loading from it.")
    ## load_string <- paste0("load('", savefile, "', envir = fresh)")
    load_string <- glue("load('{savefile}', envir = fresh)")
    eval(parse(text = load_string))
    biomart_go <- fresh[["biomart_go"]]
    retlist <- list(
      "go" = biomart_go,
      "mart" = "savefile",
      "host" = "savefile",
      "mart_name" = "savefile",
      "rows" = "savefile",
      "dataset" = "savefile"
    )
    return(retlist)
  }

  martlst <- NULL
  if (is.null(host) & is.null(default_hosts)) {
    stop("both host and default_hosts are null.")
  } else if (is.null(host)) {
    martlst <- find_working_mart(default_hosts = default_hosts, trymart = trymart,
                                 archive = archive, year = year, month = month)
  } else {
    martlst <- find_working_mart(default_hosts = host, trymart = trymart,
                                 archive = FALSE)
  }
  used_mart <- NULL
  mart <- NULL
  host <- NULL
  if (!is.null(martlst)) {
    used_mart <- martlst[["used_mart"]]
    host <- martlst[["host"]]
    mart <- martlst[["mart"]]
  }
  chosen_dataset <- NULL
  dataset <- NULL

  used_mart <- NULL
  mart <- try(biomaRt::useMart(biomart = trymart, host = host), silent = TRUE)
  if (class(mart) == "try-error") {
    message("Unable to perform useMart, perhaps the host/mart is incorrect: ",
            host, " ", trymart, ".")
    marts <- biomaRt::listMarts(host = host)
    mart_names <- as.character(marts[[1]])
    message("The available marts are: ")
    message(mart_names)
    message("Trying the first one.")
    mart <- biomaRt::useMart(biomart = marts[[1, 1]], host = host)
    used_mart <- marts[[1, 1]]
  } else {
    used_mart <- trymart
  }

  chosen_dataset <- NULL
  ## dataset <- paste0(species, "_gene_ensembl")
  dataset <- glue("{species}_gene_ensembl")
  ensembl <- try(biomaRt::useDataset(dataset, mart = mart), silent = TRUE)
  if (class(ensembl) == "try-error") {
    message("Unable to perform useDataset, perhaps the given dataset is incorrect: ",
            dataset, ".")
    datasets <- biomaRt::listDatasets(mart = mart)
    ## try_again <- paste0(species, "_eg_gene")
    try_again <- glue("{species}_eg_gene")
    message("Trying instead to use the dataset: ", try_again)
    ensembl <- biomaRt::useDataset(try_again, mart = mart)
    if (class(ensembl)[[1]] == "Mart") {
      message("That seems to have worked, extracting the resulting annotations.")
      chosen_dataset <- try_again
    } else {
      message("The second attempt failed as well, the following are the available datasets:")
      message(toString(datasets))
      return(NULL)
    }
  } else {
    chosen_dataset <- dataset
  }

  biomart_go <- try(biomaRt::getBM(attributes = dl_rows, mart = ensembl), silent = TRUE)
  if (class(biomart_go) == "try-error") {
    biomart_go <- try(biomaRt::getBM(attributes = dl_rowsv2, mart = ensembl), silent = TRUE)
    dl_rows <- dl_rowsv2
  }
  if (class(biomart_go) == "try-error") {
    message("Unable to download annotation data.")
    return(NULL)
  }
  message("Finished downloading ensembl go annotations, saving to ", savefile, ".")

  if (length(colnames(biomart_go)) == 2) {
    colnames(biomart_go) <- c("ID", "GO")
  }
  if (isTRUE(do_save)) {
    message("Saving ontologies to ", savefile, ".")
    save(list = ls(pattern = "biomart_go"), file = savefile)
    message("Finished save().")
  }

  retlist <- list(
    "go" = biomart_go,
    "mart" = ensembl,
    "host" = host,
    "mart_name" = used_mart,
    "attributes" = dl_rows,
    "dataset" = chosen_dataset
  )
  return(retlist)
}

#' Use biomart to get orthologs between supported species.
#'
#' Biomart's function getLDS is incredibly powerful, but it makes me think very
#' polite people are going to start knocking on my door, and it fails weirdly
#' pretty much always. This function attempts to alleviate some of that frustration.
#'
#' Tested in test_40ann_biomart.R
#' As with my other biomart functions, this one grew out of frustrations when
#' attempting to work with the incredibly unforgiving biomart service.  It does
#' not attempt to guarantee a useful biomart connection, but will hopefully
#' point out potentially correct marts and attributes to use for a successful
#' query.  I can say with confidence that it works well between mice and
#' humans.
#'
#' @param gene_ids List of gene IDs to translate.
#' @param first_species Linnean species name for one species.
#' @param second_species Linnean species name for the second species.
#' @param host Ensembl server to query.
#' @param trymart Assumed mart name to use.
#' @param attributes Key to query
#' @return list of 4 elements:  The first is the set of all ids, as getLDS seems
#'  to always send them all; the second is the subset corresponding to the
#'  actual ids of interest, and the 3rd/4th are other, optional ids from other datasets.
#' @seealso \pkg{biomaRt} \code{\link[biomaRt]{getLDS}}
#'  \code{\link[biomaRt]{useMart}}
#' @examples
#'  mouse_yeast_orthologs <- load_biomart_orthologs(gene_ids = NULL, first_species = "mmusculus",
#'                                                  second_species = "scerevisiae")
#'  head(mouse_yeast_orthologs$all_linked_genes)
#' @export
load_biomart_orthologs <- function(gene_ids = NULL, first_species = "hsapiens",
                                   second_species = "mmusculus",
                                   host = "dec2016.archive.ensembl.org",
                                   trymart = "ENSEMBL_MART_ENSEMBL",
                                   attributes = "ensembl_gene_id") {
  first_mart <- NULL
  first_mart <- try(biomaRt::useMart(biomart = trymart, host = host), silent = TRUE)
  if (class(first_mart) == "try-error") {
    message("Unable to perform useMart, perhaps the host/mart is incorrect: ",
            host, " ", trymart, ".")
    first_marts <- biomaRt::listMarts(host = host)
    first_mart_names <- as.character(first_marts[[1]])
    message("The available first_marts are: ")
    message(first_mart_names)
    message("Trying the first one.")
    first_mart <- biomaRt::useMart(biomart = first_marts[[1, 1]], host = host)
  }
  ## first_dataset <- paste0(first_species, "_gene_ensembl")
  first_dataset <- glue("{first_species}_gene_ensembl")
  first_ensembl <- try(biomaRt::useDataset(first_dataset, mart = first_mart), silent = TRUE)
  if (class(first_ensembl) == "try-error") {
    message("Unable to perform useDataset, perhaps the given dataset is incorrect: ",
            first_ensembl, ".")
    datasets <- biomaRt::listDatasets(mart = first_mart)
    message(toString(datasets))
    return(NULL)
  }

  second_mart <- NULL
  second_mart <- try(biomaRt::useMart(biomart = trymart, host = host), silent = TRUE)
  if (class(second_mart) == "try-error") {
    message("Unable to perform useMart, perhaps the host/mart is incorrect: ",
            host, " ", trymart, ".")
    second_marts <- biomaRt::listMarts(host = host)
    second_mart_names <- as.character(second_marts[[1]])
    message("The available second_marts are: ")
    message(second_mart_names)
    message("Trying the first one.")
    second_mart <- biomaRt::useMart(biomart = second_marts[[1, 1]], host = host)
  }
  ## second_dataset <- paste0(second_species, "_gene_ensembl")
  second_dataset <- glue("{second_species}_gene_ensembl")
  second_ensembl <- try(biomaRt::useDataset(second_dataset, mart = second_mart), silent = TRUE)
  if (class(second_ensembl) == "try-error") {
    message("Unable to perform useDataset, perhaps the given dataset is incorrect: ",
            second_ensembl, ".")
    datasets <- biomaRt::listDatasets(mart = second_mart)
    message(toString(datasets))
    return(NULL)
  }

  possible_first_attributes <- biomaRt::listAttributes(first_ensembl)
  possible_second_attributes <- biomaRt::listAttributes(second_ensembl)

  ## That is right, I had forgotten but it seems to me that no matter
  ## what list of genes I give this stupid thing, it returns all genes.

  ## Note: As of 2018-03 getLDS is more stringent in the queries it allows.  One
  ## must choose the same attributes from the first and second marts, otherwise
  ## it throws an error which looks like: "The query to the BioMart webservice
  ## returned an invalid result: the number of columns in the result table does
  ## not equal the number of attributes in the query. Please report this to the
  ## mailing list."
  ## Therefore I am dropping the arguments first_attributes/second_attributes
  ## and just leaving behind 'attributes'.
  linked_genes <- biomaRt::getLDS(attributes = attributes, values = gene_ids,
                                  mart = first_ensembl, attributesL = attributes,
                                  martL = second_ensembl)
  kept_genes <- linked_genes
  if (!is.null(gene_ids)) {
    kept_idx <- linked_genes[[1]] %in% gene_ids
    kept_genes <- linked_genes[kept_idx, ]
  }
  new_colnames <- colnames(linked_genes)
  new_colnames[[1]] <- first_species
  second_position <- length(attributes) + 1
  new_colnames[[second_position]] <- second_species
  colnames(kept_genes) <- new_colnames
  colnames(linked_genes) <- new_colnames

  linked_genes <- list(
    "all_linked_genes" = linked_genes,
    "subset_linked_genes" = kept_genes,
    "first_attribs" = possible_first_attributes,
    "second_attribs" = possible_second_attributes)
  return(linked_genes)
}

## EOF
